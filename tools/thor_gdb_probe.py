import socket, time
def chk(p): return '{:02x}'.format(sum(ord(c) for c in p) % 256)
def pkt(p): return ('$'+p+'#'+chk(p)).encode()
s = socket.create_connection(('127.0.0.1', 2345), timeout=5); s.settimeout(3)
def ask(q):
    s.sendall(pkt(q)); data=b''; t0=time.time()
    while time.time()-t0 < 2.5:
        try: b = s.recv(8192)
        except socket.timeout: break
        if not b: break
        data += b
        if b'#' in data and len(data) > 3:
            s.sendall(b'+'); break
    return data.decode('latin1')
ask('qSupported')
# PPU register layout: 32 GPRs (64-bit) then CR, then PC among the specials.
for tid, name in [('0000000001000009','SpursHdlr0'),
                  ('0000000001000008','SpursHdlr1'),
                  ('0000000001000004','busy-PPU')]:
    r = ask('Hg'+tid)
    g = ask('g')
    body = g.split('$',1)[1].split('#')[0] if '$' in g else ''
    print(f'  {name} ({tid[-8:]})  Hg={r.strip()[:12]}  reglen={len(body)} nybbles')
    if len(body) >= 64*16:
        # dump the tail specials where PC/LR usually sit in RPCS3's layout
        tail = body[32*16:]
        print('     first 4 GPRs :', ' '.join(body[i*16:(i+1)*16] for i in range(4)))
        print('     specials tail:', tail[:96])
    else:
        print('     raw:', body[:120])
s.close()
