#!/usr/bin/env python3
"""Mini-substituto do comando `ip` (via netlink), só para montar o laboratório.

Uso (executar dentro do namespace desejado, ex.: com nsenter --net=...):
  nl.py veth NOME PEER NS_PATH   cria par veth; PEER vai para o namespace NS_PATH
  nl.py addr DEV A.B.C.D/LEN     adiciona endereço IPv4
  nl.py up DEV                   ativa a interface
  nl.py route A.B.C.D/LEN GW     adiciona rota via gateway (0.0.0.0/0 = default)
"""
import os
import socket
import struct
import sys

NLM_F_REQUEST, NLM_F_ACK, NLM_F_EXCL, NLM_F_CREATE = 1, 4, 0x200, 0x400
RTM_NEWLINK, RTM_NEWADDR, RTM_NEWROUTE = 16, 20, 24
IFF_UP = 1


def attr(t, data):
    n = 4 + len(data)
    return struct.pack("=HH", n, t) + data + b"\0" * ((4 - n % 4) % 4)


def ifinfo(index=0, flags=0, change=0):
    return struct.pack("=BxHiII", 0, 0, index, flags, change)


def send(mtype, flags, payload):
    s = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, 0)
    s.bind((0, 0))
    hdr = struct.pack("=IHHII", 16 + len(payload), mtype,
                      flags | NLM_F_REQUEST | NLM_F_ACK, 1, 0)
    s.send(hdr + payload)
    r = s.recv(65536)
    _, t, _, _, _ = struct.unpack("=IHHII", r[:16])
    if t == 2:
        err = struct.unpack("=i", r[16:20])[0]
        if err:
            raise OSError(-err, os.strerror(-err))
    s.close()


def veth(name, peer, nspath):
    fd = os.open(nspath, os.O_RDONLY)
    peer_info = ifinfo() + attr(3, peer.encode() + b"\0") + attr(28, struct.pack("=i", fd))
    linkinfo = attr(1, b"veth\0") + attr(2, attr(1, peer_info))
    payload = ifinfo() + attr(3, name.encode() + b"\0") + attr(18, linkinfo)
    send(RTM_NEWLINK, NLM_F_CREATE | NLM_F_EXCL, payload)
    os.close(fd)


def up(dev):
    send(RTM_NEWLINK, 0, ifinfo(socket.if_nametoindex(dev), IFF_UP, IFF_UP))


def addr(dev, cidr):
    ip, plen = cidr.split("/")
    a = socket.inet_aton(ip)
    payload = struct.pack("=BBBBI", socket.AF_INET, int(plen), 0, 0,
                          socket.if_nametoindex(dev)) + attr(2, a) + attr(1, a)
    send(RTM_NEWADDR, NLM_F_CREATE | NLM_F_EXCL, payload)


def route(dst, gw):
    ip, plen = dst.split("/")
    payload = struct.pack("=BBBBBBBBI", socket.AF_INET, int(plen), 0, 0, 254, 3, 0, 1, 0)
    if int(plen) > 0:
        payload += attr(1, socket.inet_aton(ip))
    payload += attr(5, socket.inet_aton(gw))
    send(RTM_NEWROUTE, NLM_F_CREATE | NLM_F_EXCL, payload)


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    {"veth": veth, "addr": addr, "up": up, "route": route}[cmd](*args)
