#!/usr/bin/env python3
"""A newcomer spawns FACING THE PLAZA (spec 04 §2: 'the table and Old Ash in front of the eyes'). Before the fix the
SpawnLocation slab in build.py stood without a rotation (LookVector -Z): the player looked at the stall and the sea, Old Ash behind the back (frame
runs/roblox_build_2026-10-20/newcomer20/E0001_spawn.jpg). Check on P8 (after open_local.sh): start the game, in the first seconds -
the character LookVector along +Z (toward the plaza), Old Ash in the camera frame, the Keeper bubble (Quests.KeeperSays) visible; frame F0_spawn.jpg."""
import os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("spawn_face_check")
from p8lib import *  # noqa: F401,F403

start()
time.sleep(1.5)
shot("F0_spawn")
look = C("local r=game.Players.LocalPlayer.Character.HumanoidRootPart local l=r.CFrame.LookVector return string.format('%.2f,%.2f,%.2f|%.1f,%.1f,%.1f', l.X, l.Y, l.Z, r.Position.X, r.Position.Y, r.Position.Z)")
P("look|pos:", look)
lz = float(look.split("|")[0].split(",")[2]) if "|" in look else -9
ok("the character after spawning looks toward the plaza (LookVector.Z > 0.7)", lz > 0.7, look)
sp = S("local s=workspace:FindFirstChildWhichIsA('SpawnLocation') return s and string.format('%.2f,%.2f,%.2f', s.CFrame.LookVector.X, s.CFrame.LookVector.Y, s.CFrame.LookVector.Z) or '-'")
ok("the SpawnLocation slab faces +Z", sp.split(",")[-1].strip() not in ("-",) and float(sp.split(",")[-1]) > 0.99, sp)
keeper = C("local cam=workspace.CurrentCamera local k for _,m in workspace:GetDescendants() do if m:IsA('Model') and m:GetAttribute('DisplayName')=='Old Ash' then k=m end end "
           "if not k then return 'nokeeper' end local p=k:GetPivot().Position local v,on=cam:WorldToViewportPoint(p) return string.format('%s|%d,%d|%.0f', tostring(on), v.X, v.Y, (p-cam.CFrame.Position).Magnitude)")
P("Old Ash in frame|screen|distance:", keeper)
ok("Old Ash in the camera frame on spawn", keeper.startswith("true"), keeper)
camclear = C("local cam=workspace.CurrentCamera local parts=workspace:GetPartBoundsInBox(cam.CFrame, Vector3.new(1.5,1.5,1.5)) local t={} for _,p in parts do if p.Transparency<1 then t[#t+1]=p.Name end end "
             "local r=game.Players.LocalPlayer.Character.HumanoidRootPart return string.format('%d|%s|camdist=%.1f', #t, table.concat(t,','), (cam.CFrame.Position-r.Position).Magnitude)")
ok("the camera on spawn is not inside a part (the stall awning)", camclear.startswith("0|"), camclear)
says = C("local q=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Quests') local s=q and q:FindFirstChild('KeeperSays',true) if not s then for _,o in (q and q:GetDescendants() or {}) do if o:IsA('TextLabel') and o.Text=='Old Ash' and o.Visible then s=o end end end return tostring(s~=nil and s.Visible)")
ok("the Keeper bubble (Old Ash) is visible on spawn", says == "true", f"KeeperSays visible={says}")
time.sleep(4); shot("F1_spawn_5s")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l]
ok("console without game errors", not errs, " ;; ".join(errs[:4]))
stop()
write_result("Newcomer spawns facing the plaza (20.10)")
s.close()
