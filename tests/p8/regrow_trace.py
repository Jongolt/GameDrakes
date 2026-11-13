#!/usr/bin/env python3
"""A trace of the remount onto the grown one (regrow_check FAIL: model Stage 2, the rider not in the saddle) - the server every 0.1 s: Mounted, the seat
under the humanoid (whose model, stage), the player's companions in the folder, the Movement console. Run after open_local.sh."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("regrow_trace")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
for _ in range(40):
    if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
        break
    time.sleep(3)
stop(); start(); time.sleep(12)
P(ld("give egg Meadow")[:50]); time.sleep(0.8); P(ld("place 1")[:50]); time.sleep(3.5); P(ld("hatch 1")[:50]); time.sleep(6)
P(ld("time 100000")[:40]); time.sleep(5)
P("mount:", ld("mount")[:60]); time.sleep(2)
TR = ("local p=game.Players:GetPlayers()[1] local out={} local t0=os.clock() "
      "local sv=Instance.new('StringValue') sv.Name='RT' sv.Parent=game.ServerStorage "
      "task.spawn(function() while os.clock()-t0<8 do local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid') local s=h and h.SeatPart "
      "local m=s and s:FindFirstAncestorWhichIsA('Model') local n=0 local st='' for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==p.UserId then n+=1 st=st..tostring(x:GetAttribute('Stage')) end end "
      "out[#out+1]=string.format('%.1f M=%s seat=%s mst=%s comps=%d(%s) sit=%s', os.clock()-t0, tostring(p:GetAttribute('Mounted')), s and s.Name or '-', m and tostring(m:GetAttribute('Stage')) or '-', n, st, h and tostring(h.Sit) or '-') "
      "sv.Value=table.concat(out,'; ') task.wait(0.1) end end) return 'trace'")
P(S(TR)); time.sleep(0.5)
P("time 2:", ld("time 100000")[:40]); time.sleep(8.5)
raw = S("local v=game.ServerStorage:FindFirstChild('RT') return v and v.Value or 'none'")
prev = None
for tok in raw.split("; "):
    body = tok.split(" ", 1)[1] if " " in tok else tok
    if body != prev:
        P(tok); prev = body
cons = s.call("get_console_output", {"studio_id": sid}, 120)
txt = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
P("Movement console:", " | ".join([l for l in txt.splitlines() if "Movement" in l or "regrow" in l or "RGDBG" in l][-8:]))
stop()
