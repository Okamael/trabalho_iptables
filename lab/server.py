#!/usr/bin/env python3
"""Serviço TCP de teste: responde com o IP de origem que enxerga.
Uso: server.py IP:PORTA [IP:PORTA ...]"""
import selectors
import socket
import sys

sel = selectors.DefaultSelector()
for spec in sys.argv[1:]:
    ip, port = spec.rsplit(":", 1)
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((ip, int(port)))
    s.listen(16)
    sel.register(s, selectors.EVENT_READ, spec)

while True:
    for key, _ in sel.select():
        c, peer = key.fileobj.accept()
        try:
            c.sendall(f"OK {key.data} origem={peer[0]}\n".encode())
        except OSError:
            pass
        c.close()
