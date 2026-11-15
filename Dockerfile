FROM debian:12-slim

# Dependências do laboratório (não usa o comando `ip`: a topologia é criada via netlink em Python)
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends iptables python3 util-linux procps \
    openssh-server openssh-client iputils-ping telnet curl openssl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY firewall_industria.sh /work/firewall_industria.sh
COPY lab /work/lab

# O laboratório só altera regras dentro de namespaces de rede (nunca as do host).
# Execute com: docker run --rm -it --privileged firewall-lab
CMD ["bash", "lab/run-lab.sh"]
