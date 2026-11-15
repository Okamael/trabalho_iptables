# Fase com ferramentas reais (ssh, ping, telnet, curl). É carregada por run-lab.sh (source),
# usa N, LAB e EV definidos lá e roda com o firewall ATIVO.
# Troca os serviços de teste por serviços reais: sshd no firewall e HTTPS no servidor Web.
pkill -f "server.py 0.0.0.0:22" 2>/dev/null
pkill -f "server.py 10.0.0.10:22" 2>/dev/null
sleep 0.5
S dc 10.0.0.10:3306                                   # banner simples para o telnet
ssh-keygen -A >/dev/null 2>&1; mkdir -p /run/sshd /root/.ssh
id admin >/dev/null 2>&1 || useradd -m -s /bin/bash admin
usermod -p '*' admin
[ -f /root/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f /root/.ssh/id_ed25519
mkdir -p /home/admin/.ssh && cp /root/.ssh/id_ed25519.pub /home/admin/.ssh/authorized_keys
chown -R admin:admin /home/admin/.ssh; chmod 700 /home/admin/.ssh; chmod 600 /home/admin/.ssh/authorized_keys
N fw /usr/sbin/sshd -o ListenAddress=192.168.0.1 -o UsePAM=no -o PasswordAuthentication=no >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=203.0.113.50" \
    -keyout /tmp/web.key -out /tmp/web.crt >/dev/null 2>&1
N dc python3 $LAB/https_server.py 10.0.0.20 443 /tmp/web.crt /tmp/web.key >/dev/null 2>&1 &
sleep 1.5
printf "Host 192.168.0.1\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n  LogLevel ERROR\n  ConnectTimeout 4\n" > /root/.ssh/config
# D <ns> <arquivo> <comando>: grava "# comando" e a saída real do comando
D() { { echo "\$ $3"; N "$1" bash -c "$3" 2>&1; } > "$EV/$2"; }
D adm 07-teste1-ssh.txt "ssh admin@192.168.0.1 'whoami; echo origem=\${SSH_CLIENT%% *}'"
{ cat "$EV/07-teste1-ssh.txt"; echo; D prd tmp.txt "ssh admin@192.168.0.1 whoami; echo \"codigo de saida: \$?\""; cat "$EV/tmp.txt"; rm -f "$EV/tmp.txt"; } > "$EV/tmp2.txt"; mv "$EV/tmp2.txt" "$EV/07-teste1-ssh.txt"
D prd 08-teste2-ping.txt "ping -c 4 -W 1 192.168.3.1; echo; ping -c 4 -W 1 192.168.3.10"
D prd 09-teste3-telnet.txt "sleep 1 | timeout 4 telnet 10.0.0.10 3306; echo; echo '# porta nao liberada (22) para comparar:'; sleep 1 | timeout 4 telnet 10.0.0.10 22; echo \"codigo de saida: \$? (124 = sem resposta)\""
D inet 10-teste4-curl.txt "curl -k -i -sS -m 5 https://203.0.113.50:443; echo; echo '# porta 80 (nao publicada):'; curl -sS -m 3 http://203.0.113.50:80; echo \"codigo de saida: \$?\""
