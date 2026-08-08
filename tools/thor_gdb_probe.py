import socket, sys, time
def chk(p): return '{:02x}'.format(sum(ord(c) for c in p) % 256)
def pkt(p): return ('$'+p+'#'+chk(p)).encode()
s = socket.create_connection(('127.0.0.1', 2345), timeout=5)
s.settimeout(3)
def ask(q):
    s.sendall(pkt(q))
    data = b''
    t0 = time.time()
    while time.time() - t0 < 2.5:
        try:
            b = s.recv(4096)
        except socket.timeout:
            break
        if not b: break
        data += b
        if b'#' in data and data.count(b'#') >= 1 and len(data) > 3:
            s.sendall(b'+')          # acknowledge, or the server stalls
            break
    return data.decode('latin1')
for q in ['qSupported','?','qfThreadInfo','qC','Hg0','g']:
    r = ask(q)
    print('  ->', q)
    print('     <=', repr(r[:200]))
s.close()
