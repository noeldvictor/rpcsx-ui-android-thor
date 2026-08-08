"""Enumerate every PPU thread the RPCSX GDB stub knows about and report where
each one is parked.

Written for the Folklore SPURS stall (docs/arm64/rsx-boot-hang.md), where four
threads were examined by hand and all four turned out to be behaving correctly.
The fault has to be in one of the ones nobody looked at, so look at all of them.

Usage:  adb forward tcp:2345 tcp:2345 && python tools/thor_gdb_all_threads.py

Traps this encodes, both learned the hard way:
  * the stub goes silent unless every reply is acknowledged with a bare '+'
  * PowerShell's TcpClient is blocked by the sandbox (EPERM); use Python
"""
import socket
import time


def chk(p):
    return '{:02x}'.format(sum(ord(c) for c in p) % 256)


def pkt(p):
    return ('$' + p + '#' + chk(p)).encode()


s = socket.create_connection(('127.0.0.1', 2345), timeout=5)
s.settimeout(3)


def ask(q):
    s.sendall(pkt(q))
    d = b''
    t0 = time.time()
    while time.time() - t0 < 2.5:
        try:
            b = s.recv(65536)
        except socket.timeout:
            break
        if not b:
            break
        d += b
        if b'#' in d and len(d) > 3:
            s.sendall(b'+')          # without this the stub answers once, then stops
            break
    return d.decode('latin1')


def body(r):
    """Strip the $...#xx framing off a reply."""
    if '$' not in r:
        return ''
    return r.split('$', 1)[1].split('#')[0]


ask('qSupported')

# --- enumerate ------------------------------------------------------------
tids = []
r = body(ask('qfThreadInfo'))
while r.startswith('m'):
    tids += [t for t in r[1:].split(',') if t]
    r = body(ask('qsThreadInfo'))

print(f'{len(tids)} threads\n')

for tid in tids:
    extra = body(ask('qThreadExtraInfo,' + tid))
    try:
        name = bytes.fromhex(extra).decode('latin1').strip()
    except ValueError:
        name = extra or '?'

    ask('Hg' + tid)
    g = body(ask('g'))

    # PPU layout: 32 GPR + 32 FPR of 8 bytes each = 1024 nybbles, then PC.
    tail = g[1024:]
    pc = tail[0:16] if len(tail) >= 16 else '?'

    def gpr(n):
        return g[n * 16:(n + 1) * 16]

    # sys_event_queue_receive(equeue_id, dummy_event, timeout): r3 id, r5 timeout.
    # The queue id is what separates SpursHdlr1's forever-by-design service loop
    # from a cellSpursEventFlagWait that is genuinely stuck: different queues.
    print(f'  {tid}  {name:<22} pc={pc}')
    print(f'  {"":18}  {"":22} r3={gpr(3)} r4={gpr(4)} r5={gpr(5)}')
