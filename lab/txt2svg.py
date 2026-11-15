#!/usr/bin/env python3
"""Renderiza um arquivo de texto (saída real de terminal) como imagem SVG estilo terminal.
Uso: txt2svg.py ENTRADA.txt SAIDA.svg "título" ["comando exibido no prompt"]
O texto não é alterado; apenas colorido (PASS/OK verde, FAIL/DROP vermelho)."""
import os
import sys
from xml.sax.saxutils import escape

src, dst, title = sys.argv[1], sys.argv[2], sys.argv[3]
cmd = sys.argv[4] if len(sys.argv) > 4 else None
PROMPT = os.environ.get("PROMPT", "root@firewall:~# ")
lines = open(src, encoding="utf-8").read().rstrip("\n").split("\n")
if cmd:
    lines = [("PROMPT", cmd)] + [("OUT", l) for l in lines]
else:
    lines = [("OUT", l) for l in lines]

CW, LH, PAD, BAR = 8.4, 17, 16, 34
width = int(max(len(l[1]) + (len(PROMPT) if l[0] == "PROMPT" else 0) for l in lines) * CW + 2 * PAD)
height = int(len(lines) * LH + 2 * PAD + BAR)

def color(kind, text):
    if kind == "PROMPT":
        return "#8ae234"
    if " FAIL " in text or text.rstrip().endswith("FAIL"):
        return "#ef2929"
    if "PASS" in text or "ABERTA" in text:
        return "#8ae234"
    if "DROP" in text or "BLOQ" in text:
        return "#fcaf3e"
    if text.startswith("---") or text.startswith("#") or text.startswith("Chain"):
        return "#729fcf"
    return "#d3d7cf"

out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
       f'<rect width="{width}" height="{height}" rx="8" fill="#1e1e1e"/>',
       f'<rect width="{width}" height="{BAR}" rx="8" fill="#3c3c3c"/>',
       '<circle cx="20" cy="17" r="6" fill="#ff5f56"/><circle cx="40" cy="17" r="6" fill="#ffbd2e"/><circle cx="60" cy="17" r="6" fill="#27c93f"/>',
       f'<text x="{width // 2}" y="22" fill="#cccccc" font-family="sans-serif" font-size="13" text-anchor="middle">{escape(title)}</text>']
y = BAR + PAD + 10
for kind, text in lines:
    shown = (PROMPT + text) if kind == "PROMPT" else text
    out.append(f'<text x="{PAD}" y="{y}" fill="{color(kind, text)}" font-family="DejaVu Sans Mono, Menlo, Consolas, monospace" '
               f'font-size="14" xml:space="preserve">{escape(shown)}</text>')
    y += LH
out.append("</svg>")
open(dst, "w", encoding="utf-8").write("\n".join(out))
print(dst, f"{width}x{height}")
