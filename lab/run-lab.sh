#!/bin/bash
# Laboratório: monta 6 redes isoladas (namespaces), aplica o firewall e roda os testes.
export LC_ALL=C.UTF-8
# Uso: bash lab/run-lab.sh   (como root; não altera as regras reais do host)
LAB="$(cd "$(dirname "$0")" && pwd)"
FW_SCRIPT="${FW_SCRIPT:-$LAB/../firewall_industria.sh}"
EV="$LAB/evidencias"
mkdir -p "$EV"
declare -A PID

cleanup() { for p in "${PID[@]}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT

for n in fw adm prd exp dc inet; do
    unshare -n sleep 3600 & PID[$n]=$!
done
sleep 0.5
N() { local n=$1; shift; nsenter --net=/proc/${PID[$n]}/ns/net "$@"; }
NL="python3 $LAB/nl.py"

# ---------- Topologia ----------
for n in fw adm prd exp dc inet; do N $n $NL up lo; done
N fw $NL addr lo 192.168.0.1/32            # IP de gerência do firewall

link() {  # link <rede> <if-no-fw> <ip-fw/len> <ip-host/len> <gateway-host>
    N fw $NL veth "$2" eth0 /proc/${PID[$1]}/ns/net
    N fw $NL addr "$2" "$3"; N fw $NL up "$2"
    N $1 $NL addr eth0 "$4"; N $1 $NL up eth0
    [ -n "$5" ] && N $1 $NL route 0.0.0.0/0 "$5"
}
link adm  eth-adm 192.168.1.1/24 192.168.1.10/24 192.168.1.1
link prd  eth-prd 192.168.2.1/24 192.168.2.10/24 192.168.2.1
link exp  eth-exp 192.168.3.1/24 192.168.3.10/24 192.168.3.1
link dc   eth-dc  10.0.0.1/24    10.0.0.10/24    10.0.0.1
N dc $NL addr eth0 10.0.0.20/24; N dc $NL addr eth0 10.0.0.30/24
link inet eth-wan 203.0.113.50/24 203.0.113.1/24 ""
N inet $NL addr eth0 198.51.100.10/32      # "site externo" para testar saída/SNAT
N inet $NL route 10.0.0.0/24 203.0.113.50   # permite testar acesso direto (sem DNAT)
N fw $NL route 0.0.0.0/0 203.0.113.1

# ---------- Serviços de teste ----------
S() { local n=$1; shift; N $n python3 $LAB/server.py "$@" >/dev/null 2>&1 & }
S fw   0.0.0.0:22
S dc   10.0.0.10:22 10.0.0.10:80 10.0.0.10:443 10.0.0.10:3306 10.0.0.20:443 10.0.0.20:80 10.0.0.30:8080 10.0.0.30:3306
S adm  192.168.1.10:8080
S prd  192.168.2.10:3306
S exp  192.168.3.10:8080
S inet 198.51.100.10:22 198.51.100.10:80 198.51.100.10:443
sleep 1

# ---------- Aplicar o firewall (o script do trabalho, sem modificações) ----------
echo ">>> Aplicando $(basename "$FW_SCRIPT") no namespace do firewall"
N fw env WAN_IF=eth-wan IF_ADM=eth-adm IF_PRD=eth-prd IF_EXP=eth-exp IF_DC=eth-dc \
    RULES_FILE="$EV/rules.v4" bash "$FW_SCRIPT"
echo

# ---------- Testes ----------
PASS=0; FAIL=0; NUM=0
t() {  # t <esperado OK|BLOQ> <ns-origem> <ip> <porta> <descrição>
    NUM=$((NUM+1))
    local out obt res
    out=$(N "$2" python3 $LAB/probe.py "$3" "$4" 1.5)
    case "$out" in ABERTA*) obt=OK;; *) obt=BLOQ;; esac
    if [ "$obt" = "$1" ]; then res=PASS; PASS=$((PASS+1)); else res=FAIL; FAIL=$((FAIL+1)); fi
    local d="$5"; while [ ${#d} -lt 48 ]; do d="$d "; done   # preenche por caractere (printf conta bytes)
    printf "%2d %s %-5s %-5s %s [%s]\n" $NUM "$d" "$1" "$obt" "$res" "$out"
}
run_tests() {
echo "Nº Teste                                            Esper Obtid Resultado [detalhe]"
echo "--- INPUT (tráfego para o firewall) ---"
t OK   adm  192.168.0.1   22   "SSH Admin -> Firewall 192.168.0.1:22"
t BLOQ prd  192.168.0.1   22   "SSH Produção -> Firewall"
t BLOQ exp  192.168.0.1   22   "SSH Expedição -> Firewall"
t BLOQ dc   192.168.0.1   22   "SSH Datacenter -> Firewall"
t BLOQ inet 203.0.113.50  22   "SSH Internet -> Firewall (203.0.113.50)"
echo "--- FORWARD: Administração <-> Datacenter ---"
t OK   adm  10.0.0.10 22   "Admin -> DC SSH 10.0.0.10:22"
t OK   adm  10.0.0.10 80   "Admin -> DC HTTP 10.0.0.10:80"
t OK   adm  10.0.0.10 443  "Admin -> DC HTTPS 10.0.0.10:443"
t OK   adm  10.0.0.10 3306 "Admin -> DC MySQL 10.0.0.10:3306"
t OK   adm  10.0.0.30 8080 "Admin -> DC ERP 10.0.0.30:8080"
t OK   dc   192.168.1.10 8080 "DC -> Admin 192.168.1.10:8080 (sentido inverso)"
echo "--- FORWARD: Produção -> Datacenter (só 3306 no BD) ---"
t OK   prd  10.0.0.10 3306 "Produção -> DC MySQL 10.0.0.10:3306"
t BLOQ prd  10.0.0.10 22   "Produção -> DC SSH 10.0.0.10:22"
t BLOQ prd  10.0.0.10 443  "Produção -> DC HTTPS 10.0.0.10:443"
t BLOQ prd  10.0.0.30 8080 "Produção -> DC ERP 10.0.0.30:8080"
t BLOQ prd  10.0.0.30 3306 "Produção -> 3306 em outro servidor (.30)"
echo "--- FORWARD: Expedição -> Datacenter (só 8080 no ERP) ---"
t OK   exp  10.0.0.30 8080 "Expedição -> DC ERP 10.0.0.30:8080"
t BLOQ exp  10.0.0.10 3306 "Expedição -> DC MySQL 10.0.0.10:3306"
t BLOQ exp  10.0.0.10 22   "Expedição -> DC SSH 10.0.0.10:22"
echo "--- FORWARD: Produção <-> Expedição (bloqueado) ---"
t BLOQ prd  192.168.3.10 8080 "Produção -> Expedição 192.168.3.10:8080"
t BLOQ exp  192.168.2.10 3306 "Expedição -> Produção 192.168.2.10:3306"
echo "--- SNAT / saída para Internet (só Administração, 80/443) ---"
t OK   adm  198.51.100.10 80  "Admin -> Internet HTTP :80"
t OK   adm  198.51.100.10 443 "Admin -> Internet HTTPS :443"
t BLOQ adm  198.51.100.10 22  "Admin -> Internet SSH :22"
t BLOQ prd  198.51.100.10 80  "Produção -> Internet :80"
t BLOQ exp  198.51.100.10 80  "Expedição -> Internet :80"
t BLOQ dc   198.51.100.10 443 "Datacenter -> Internet :443"
echo "--- DNAT (Internet -> Servidor Web, só 443) ---"
t OK   inet 203.0.113.50 443  "Internet -> 203.0.113.50:443 (DNAT)"
t BLOQ inet 203.0.113.50 80   "Internet -> 203.0.113.50:80"
t BLOQ inet 203.0.113.50 3306 "Internet -> 203.0.113.50:3306"
t BLOQ inet 10.0.0.20 443     "Internet -> 10.0.0.20:443 direto (sem DNAT)"
t BLOQ inet 10.0.0.10 3306    "Internet -> 10.0.0.10:3306 direto"
echo "--- OUTPUT (tráfego originado no firewall) ---"
t OK   fw   198.51.100.10 443 "Firewall -> Internet HTTPS :443"
t BLOQ fw   198.51.100.10 22  "Firewall -> Internet SSH :22"
t BLOQ fw   10.0.0.10 3306    "Firewall -> DC MySQL 10.0.0.10:3306"
t BLOQ fw   192.168.2.10 3306 "Firewall -> Produção :3306"
}
run_tests > "$EV/01-testes.txt"
echo "TOTAL: $NUM testes | PASS=$PASS | FALHOU=$FAIL" >> "$EV/01-testes.txt"
cat "$EV/01-testes.txt"

# ---------- Regras e contadores ----------
{ echo "# iptables -S (filter)"; N fw iptables -S; echo; echo "# iptables -t nat -S"; N fw iptables -t nat -S; } > "$EV/03-regras.txt"
{ N fw iptables -L -n -v --line-numbers; echo; N fw iptables -t nat -L -n -v --line-numbers; } > "$EV/04-contadores.txt"

# ---------- Controle: mesmos acessos SEM firewall ----------
N fw bash -c 'for c in INPUT FORWARD OUTPUT; do iptables -P $c ACCEPT; done; iptables -F; iptables -t nat -F'
{
echo "# CONTROLE: mesmo teste SEM firewall (políticas ACCEPT, regras limpas) - os bloqueios devem sumir"
for x in "prd 10.0.0.10 22" "prd 192.168.3.10 8080" "exp 10.0.0.10 3306" "inet 10.0.0.10 3306" "prd 192.168.0.1 22"; do
    set -- $x; printf "%-5s -> %-14s :%-5s => " $1 $2 $3; N $1 python3 $LAB/probe.py $2 $3 1.5
done
} | tee "$EV/06-controle-sem-firewall.txt"
