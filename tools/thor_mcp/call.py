#!/usr/bin/env python
"""Drive tools/thor_mcp/server.py over stdio JSON-RPC.

The server is the tested harness; AGENTS.md says the LOOP was the defect, not the
primitives. This exists so the tools are usable when the MCP server is not loaded
into the agent session - same code path, no ad-hoc bash reimplementation.

  python tools/thor_mcp/call.py tools/list
  python tools/thor_mcp/call.py thor_state
  python tools/thor_mcp/call.py thor_boot '{"titleId":"BLUS30357"}'

PowerShell can remove the JSON key quotes from a native command argument. Set
THOR_CALL_ARGS to pass the same JSON without native argument conversion.
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    name = sys.argv[1]
    args_text = os.environ.get("THOR_CALL_ARGS")
    if args_text is None:
        args_text = sys.argv[2] if len(sys.argv) > 2 else "{}"
    args = json.loads(args_text)

    env = dict(os.environ)
    env.setdefault("THOR_SERIAL", "192.168.1.3:5555")
    env.setdefault("THOR_CTRL_PORT", "8099")

    reqs = [
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{
            "protocolVersion":"2024-11-05","capabilities":{},
            "clientInfo":{"name":"thor-call","version":"1"}}},
        {"jsonrpc":"2.0","method":"notifications/initialized"},
    ]
    reqs.append({"jsonrpc":"2.0","id":2,"method":"tools/list"} if name == "tools/list"
                else {"jsonrpc":"2.0","id":2,"method":"tools/call",
                      "params":{"name":name,"arguments":args}})

    try:
        p = subprocess.run(
            [sys.executable, os.path.join(HERE, "server.py")],
            input="".join(json.dumps(r) + "\n" for r in reqs).encode(),
            capture_output=True, cwd=ROOT, env=env,
            timeout=int(env.get("THOR_CALL_TIMEOUT", "600")))
    except subprocess.TimeoutExpired:
        stop_result = "not requested"
        if name != "thor_stop":
            stop_reqs = reqs[:2] + [{
                "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                "params": {"name": "thor_stop", "arguments": {}},
            }]
            try:
                stopped = subprocess.run(
                    [sys.executable, os.path.join(HERE, "server.py")],
                    input="".join(json.dumps(r) + "\n" for r in stop_reqs).encode(),
                    capture_output=True, cwd=ROOT, env=env, timeout=120)
                stop_result = stopped.stdout.decode("utf-8", "replace").strip()
            except subprocess.TimeoutExpired:
                stop_result = "the verified stop request also timed out"
        print("ERROR: Thor controller exceeded its host timeout. "
              "A verified stop was requested. stop_result=" + stop_result[-1200:])
        return 1

    for line in p.stdout.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("id") == 2:
            if "error" in msg:
                print("ERROR:", json.dumps(msg["error"], indent=2)); return 1
            res = msg.get("result", {})
            if name == "tools/list":
                for t in res.get("tools", []):
                    req = t.get("inputSchema", {}).get("required", [])
                    print("  %-18s %s" % (t["name"], t.get("description","").split("\n")[0][:100]))
                    if req: print("%22s required: %s" % ("", ", ".join(req)))
            else:
                for c in res.get("content", []):
                    print(c.get("text", json.dumps(c)))
            return 0
    err = p.stderr.decode("utf-8", "replace").strip()
    print("no reply; stderr:", err[-800:] if err else "(none)")
    return 1

sys.exit(main())
