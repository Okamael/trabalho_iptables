#!/bin/bash
# Script de Configuração de Firewall - Indústria XYZ
# Firewall central: 192.168.0.1 (interna) / 203.0.113.50 (internet)

# ===== VARIÁVEIS (ajuste ao seu ambiente) =====
ADMIN="192.168.1.0/24"      # Rede de Administração
PROD="192.168.2.0/24"       # Rede de Produção (CNC, SCADA, PLCs)
EXPED="192.168.3.0/24"      # Rede de Expedição
DC="10.0.0.0/24"            # Datacenter interno
DB_SRV="10.0.0.10"          # Servidor de banco de dados (MySQL) - conforme teste 3
ERP_SRV="10.0.0.30"         # Servidor ERP (suposição - ajuste se necessário)
WEB_SRV="10.0.0.20"         # Servidor Web (suposição - ajuste se necessário)
FW_PUB="203.0.113.50"       # IP público do firewall
WAN_IF="${WAN_IF:-eth0}"    # Interface ligada à internet (ajuste: eth0/ens33...)
IF_ADM="${IF_ADM:-eth1}"    # Interface da rede de Administração
IF_PRD="${IF_PRD:-eth2}"    # Interface da rede de Produção
IF_EXP="${IF_EXP:-eth3}"    # Interface da rede de Expedição
IF_DC="${IF_DC:-eth4}"      # Interface do Datacenter

# Habilitar roteamento (necessário para FORWARD/NAT)
echo 1 > /proc/sys/net/ipv4/ip_forward

# Limpar regras anteriores
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Definir políticas padrão
iptables -P INPUT DROP      # Nada entra no firewall sem permissão
iptables -P FORWARD DROP    # Nada atravessa o firewall sem permissão
iptables -P OUTPUT ACCEPT   # Firewall pode originar tráfego (refinado abaixo)

# ===== REGRAS INPUT (Tráfego para o Firewall) =====
# Loopback: comunicação interna do próprio firewall
iptables -A INPUT -i lo -j ACCEPT
# Respostas de conexões já estabelecidas / relacionadas
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# Descarta pacotes inválidos
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
# SSH ao firewall: SOMENTE da rede de Administração
iptables -A INPUT -i $IF_ADM -p tcp -s $ADMIN --dport 22 -m conntrack --ctstate NEW -j ACCEPT
# Ping ao firewall apenas da Administração (diagnóstico)
iptables -A INPUT -p icmp --icmp-type echo-request -s $ADMIN -j ACCEPT
# Qualquer outra tentativa de SSH (Produção, Expedição, DC, Internet) é descartada
iptables -A INPUT -p tcp --dport 22 -j DROP
# (o restante cai na política DROP)

# ===== REGRAS FORWARD (Tráfego entre Redes) =====
# Respostas de conexões já autorizadas (permite o retorno em ambos os sentidos)
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP

# Produção <-> Expedição: BLOQUEADO (segurança operacional), nos dois sentidos
iptables -A FORWARD -i $IF_PRD -o $IF_EXP -j DROP
iptables -A FORWARD -i $IF_EXP -o $IF_PRD -j DROP

# Administração -> Datacenter: acesso total (SSH, HTTP, HTTPS, banco de dados)
iptables -A FORWARD -s $ADMIN -d $DC -j ACCEPT
# Datacenter -> Administração: sentido inverso (Admin <-> DC), apenas novas conexões iniciadas pelo DC
iptables -A FORWARD -s $DC -d $ADMIN -m conntrack --ctstate NEW -j ACCEPT

# Produção -> Datacenter: somente leitura de dados (MySQL 3306) no servidor de BD
iptables -A FORWARD -s $PROD -d $DB_SRV -p tcp --dport 3306 -m conntrack --ctstate NEW -j ACCEPT

# Expedição -> Datacenter: acesso ao ERP (porta 8080)
iptables -A FORWARD -s $EXPED -d $ERP_SRV -p tcp --dport 8080 -m conntrack --ctstate NEW -j ACCEPT

# Saída para Internet: SOMENTE Administração (HTTP/HTTPS + DNS para resolver nomes)
iptables -A FORWARD -s $ADMIN -o $WAN_IF -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -s $ADMIN -o $WAN_IF -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -s $ADMIN -o $WAN_IF -p tcp --dport 53 -j ACCEPT

# Internet -> Servidor Web do DC: apenas HTTPS 443 e SOMENTE tráfego que passou pelo DNAT
# (--ctstate DNAT impede acesso direto a 10.0.0.20 sem passar pelo IP público)
iptables -A FORWARD -i $WAN_IF -o $IF_DC -d $WEB_SRV -p tcp --dport 443 -m conntrack --ctstate DNAT -j ACCEPT

# Todo o resto (ex.: Produção/Expedição -> Internet) cai na política DROP

# ===== REGRAS OUTPUT (Tráfego do Firewall) =====
# Loopback
iptables -A OUTPUT -o lo -j ACCEPT
# Respostas de conexões estabelecidas (ex.: resposta do SSH da Administração)
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# Firewall pode resolver nomes (DNS) e sincronizar hora (NTP) / atualizar (HTTP/HTTPS) na internet
iptables -A OUTPUT -o $WAN_IF -p udp -m multiport --dports 53,123 -j ACCEPT
iptables -A OUTPUT -o $WAN_IF -p tcp -m multiport --dports 53,80,443 -j ACCEPT
# Diagnóstico: ping originado no firewall
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT
# Todo o restante originado no firewall é descartado (inclui novas conexões para
# Produção, Expedição e Datacenter), mantendo -P OUTPUT ACCEPT exigido pelo template
iptables -A OUTPUT -j DROP

# ===== REGRAS SNAT (Mascaramento para Internet) =====
# Tráfego da Administração (única rede com saída) sai com o IP público do firewall
iptables -t nat -A POSTROUTING -s $ADMIN -o $WAN_IF -j SNAT --to-source $FW_PUB

# ===== REGRAS DNAT (Redirecionamento de Entrada) =====
# Internet -> 203.0.113.50:443 é redirecionado para o servidor web interno
iptables -t nat -A PREROUTING -i $WAN_IF -d $FW_PUB -p tcp --dport 443 -j DNAT --to-destination $WEB_SRV:443

# Salvar regras
RULES_FILE="${RULES_FILE:-/etc/iptables/rules.v4}"
mkdir -p "$(dirname "$RULES_FILE")"
iptables-save > "$RULES_FILE"
echo "Firewall aplicado. Regras salvas em $RULES_FILE"
