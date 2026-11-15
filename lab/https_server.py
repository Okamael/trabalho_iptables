#!/usr/bin/env python3
"""Servidor HTTPS de teste (certificado autoassinado). Uso: https_server.py IP PORTA CERT KEY"""
import http.server
import ssl
import sys
ip, port, cert, key = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"Servidor Web {ip}:{port} - origem da conexao: {self.client_address[0]}\n".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer((ip, port), H)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
