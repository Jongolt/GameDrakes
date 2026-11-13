#!/usr/bin/env python3
"""A Studio MCP session from the VPS: one bridge, waiting for Studio to connect, a chain of calls, snapshots to files.
Studio connects to a new bridge not right away (~10-30 s), so all the steps are in one session.

    python3 mcp_session.py calls.json [out_dir]
calls.json: [{"tool": "screen_capture", "args": {}}, {"tool": "execute_luau", "args": {"code": "..."}},
             {"sleep": 5}, ...]
The images from the replies are saved to out_dir as NN_tool.png, the text is printed (trimmed).
"""
import base64
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "mcp_bridge.sh")


def load_env():
    """P8 settings (a file outside the repo, $P8_ENV or ~/.config/p8/p8.env): KEY=VALUE lines, a ' # ...' tail is a comment."""
    path = os.environ.get("P8_ENV") or os.path.expanduser("~/.config/p8/p8.env")
    env = {}
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.split(" #")[0].strip().strip('"').strip("'")
    return env


ENV = load_env()


class Session:
    def __init__(self):
        self.p = subprocess.Popen([BRIDGE], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=open(os.path.join(ENV["P8_STATE"], "mcp_session.err"), "w"),
                                  text=True, bufsize=1)
        self.n = 0

    def send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def request(self, method, params, timeout=300):
        self.n += 1
        rid = self.n
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        t = time.time()
        while time.time() - t < timeout:
            line = self.p.stdout.readline()
            if not line:
                raise RuntimeError("the bridge closed")
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if msg.get("id") == rid:
                return msg
        raise TimeoutError(method)

    def call(self, tool, args, timeout=300):
        return self.request("tools/call", {"name": tool, "arguments": args}, timeout)

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(timeout=10)
        except Exception:
            self.p.kill()


def main():
    calls = json.load(open(sys.argv[1]))
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ENV["P8_STATE"], "shots")
    os.makedirs(out, exist_ok=True)
    s = Session()
    s.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                             "clientInfo": {"name": "claude-vps", "version": "0.2"}})
    s.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    t0 = time.time()
    while True:
        r = s.call("list_roblox_studios", {})
        text = r["result"]["content"][0]["text"]
        if '"studios":[]' not in text.replace(" ", ""):
            studio_id = json.loads(text)["studios"][0]["id"]
            print("studio:", text[:200], f"({time.time() - t0:.0f} c)", flush=True)
            break
        if time.time() - t0 > 240:
            print("Studio did not connect within 240 s:", text[:200])
            s.close()
            sys.exit(1)
        time.sleep(4)
    for i, c in enumerate(calls, 1):
        if "sleep" in c:
            time.sleep(c["sleep"])
            continue
        if "bridge" in c:  # wait until the client attribute equals the value, then run the server code
            b = c["bridge"]
            deadline = time.time() + b.get("timeout", 60)
            seen = ""
            while time.time() < deadline:
                r = s.call("execute_luau", {"studio_id": studio_id, "datamodel_type": "Client",
                                            "code": f"return tostring(workspace:GetAttribute('{b['attr']}'))"}, 60)
                seen = ((r.get("result") or {}).get("content") or [{}])[0].get("text", "")
                if b["equals"] in seen:
                    break
                time.sleep(b.get("every", 0.4))
            r = s.call("execute_luau", {"studio_id": studio_id, "datamodel_type": "Server", "code": b["server"]}, 120)
            txt = ((r.get("result") or {}).get("content") or [{}])[0].get("text", "")
            print(f"[{i}] bridge {b['attr']}={b['equals']} seen={seen[:80]} -> server: {txt[:c.get('max', 300)]}", flush=True)
            continue
        if "shell" in c:  # a local command inside the session (P8 screen recording via ssh), the output is printed
            r = subprocess.run(c["shell"], shell=True, capture_output=True, text=True, timeout=c.get("timeout", 120))
            print(f"[{i}] shell: {(r.stdout + r.stderr).strip()[-400:]} (exit {r.returncode})", flush=True)
            continue
        args = dict(c.get("args", {}))
        args.setdefault("studio_id", studio_id)
        r = s.call(c["tool"], args, c.get("timeout", 300))
        res = r.get("result") or {}
        for k, part in enumerate(res.get("content", [])):
            if part.get("type") == "image":
                ext = "png" if "png" in part.get("mimeType", "png") else "jpg"
                path = os.path.join(out, f"{i:02d}_{c['tool']}_{k}.{ext}")
                open(path, "wb").write(base64.b64decode(part["data"]))
                print(f"[{i}] {c['tool']}: image -> {path}", flush=True)
            elif part.get("type") == "text":
                print(f"[{i}] {c['tool']}: {part['text'][:c.get('max', 600)]}", flush=True)
        if r.get("error"):
            print(f"[{i}] {c['tool']}: ERROR {json.dumps(r['error'])[:400]}", flush=True)
    s.close()


if __name__ == "__main__":
    main()
