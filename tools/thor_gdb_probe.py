import socket, time
def chk(p): return '{:02x}'.format(sum(ord(c) for c in p) % 256)
def pkt(p): return ('$'+p+'#'+chk(p)).encode()
s = socket.create_connection(('127.0.0.1', 2345), timeout=5); s.settimeout(3)
def ask(q):
    s.sendall(pkt(q)); d=b''; t0=time.time()
    while time.time()-t0 < 2.5:
        try: b=s.recv(8192)
        except socket.timeout: break
        if not b: break
        d+=b
        if b'#' in d and len(d)>3: s.sendall(b'+'); break
    return d.decode('latin1')
ask('qSupported')
for tid,name in [('0000000001000009','SpursHdlr0'),('0000000001000008','SpursHdlr1')]:
    ask('Hg'+tid); g=ask('g')
    body=g.split('$',1)[1].split('#')[0]
    print(f'== {name}  ({len(body)} nybbles = {len(body)//2} bytes)')
    tail=body[1024:]                      # past 32 GPR + 32 FPR
    # print the tail as 8-byte words
    words=[tail[i:i+16] for i in range(0,len(tail),16)]
    for i,w in enumerate(words):
        if w.strip('0'):
            print(f'   special[{i}] = {w}')
