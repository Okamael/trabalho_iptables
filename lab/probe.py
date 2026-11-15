#!/usr/bin/env python3
"""Cliente de teste. Uso: probe.py IP PORTA [timeout_s]
Imprime ABERTA (com a resposta do servidor), RECUSADA ou BLOQUEADA (timeout)."""
import socket
import sys

ip, port = sys.argv[1], int(sys.argv[2])
timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
s = socket.socket()
s.settimeout(timeout)
try:
    s.connect((ip, port))
    print("ABERTA " + s.recv(200).decode().strip())
except socket.timeout:
    print("BLOQUEADA (timeout)")
except ConnectionRefusedError:
    print("RECUSADA (RST)")
except OSError as e:
    print(f"ERRO ({e})")
