#!/usr/bin/env python3
"""The Frost Isle sign: a post in a rock out of the sea (3 Poly Haven stones, solid) and a board
'Frost Isle / Opens in a future update' facing the main island (the island opens in a later update). In a LOCAL file on P8: the board, the post and the rock are in place, the board
faces west (toward the main island), the stones are solid, the bottom of the board is above the rock, the wall is in place; text en and es (LocTest);
frames from the approach, from the side, from flight height.
Run: python3 tests/p8/frost_sign_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("frost_sign_check")
from p8lib import *  # noqa: F401,F403


def edit(code):
    r = s.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}, 60)
    return ((r.get("result") or {}).get("content") or [{}])[0].get("text", "")


def cam(eye, look, name):
    C("local c=workspace.CurrentCamera local cf=CFrame.lookAt(Vector3.new(%s),Vector3.new(%s)) local RunS=game:GetService('RunService') "
      "pcall(function() RunS:UnbindFromRenderStep('p8cam') end) RunS:BindToRenderStep('p8cam',Enum.RenderPriority.Last.Value+1,function() "
      "c.CameraType=Enum.CameraType.Scriptable c.CFrame=cf end) return 'ok'" % (eye, look))
    time.sleep(2.5); shot(name)


for lang in ("en", "es"):
    stop()
    edit("game.ReplicatedStorage:SetAttribute('LocTest', %s) return 'ok'" % ("nil" if lang == "en" else f"'{lang}'"))
    start()
    S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    C("local c=game.Players.LocalPlayer.Character if c then c:PivotTo(CFrame.new(1050, 30, 0)) local r=c:FindFirstChild('HumanoidRootPart') if r then r.Anchored=true end end return 'ok'")
    time.sleep(6)
    if lang == "en":
        st = S("local b,post,wall for _,o in workspace:GetDescendants() do if o.Name=='FrostSign' then b=o elseif o.Name=='FrostSignPost' then post=o elseif o.Name=='FrostWall' then wall=o end end "
               "if not b then return 'nosign' end local n=b.CFrame.LookVector local W=require(game.ReplicatedStorage.Shared.Config).World local FS=W.gates.frost.sign local sx=W.frostIsle.wallX-FS.back "
               "local rocks,solid,top=0,0,-99 for _,r in FS.rocks do local f=workspace.World.Meshes:FindFirstChild(r[4]) if f then for _,m in f:GetChildren() do local cf,sz=m:GetBoundingBox() "
               "if Vector2.new(cf.Position.X-(sx+r[1]),cf.Position.Z-r[2]).Magnitude<3 then rocks+=1 top=math.max(top,cf.Position.Y+sz.Y/2) local sd=false for _,p in m:GetDescendants() do if p:IsA('BasePart') and p.CanCollide then sd=true end end if sd then solid+=1 end end end end end "
               "local t={} for _,l in b:GetDescendants() do if l:IsA('TextLabel') then t[#t+1]=l.Name..'='..l.Text end end "
               "return string.format('front=%.2f,%.2f,%.2f boardBottom=%.1f post=%s wall=%s/%s rocks=%d solid=%d rockTop=%.1f texts=%s', n.X,n.Y,n.Z, b.Position.Y-b.Size.Y/2, tostring(post~=nil), tostring(wall~=nil), tostring(wall and wall.CanCollide), rocks, solid, top, table.concat(t,' | '))")
        P("sign (server):", st)
        mm = re.search(r"front=(-?[\d.]+),.*?boardBottom=(-?[\d.]+) post=true wall=true/true rocks=(\d+) solid=(\d+) rockTop=(-?[\d.]+)", st)
        ok("the board faces west, toward the main island", mm is not None and float(mm.group(1)) < -0.9, st[:200])
        ok("post, wall (solid) and 3 rock stones in place, the stones are solid", mm is not None and mm.group(3) == "3" and mm.group(4) == "3", st[:300])
        ok("the board bottom is above the rock (the board is not in the stone)", mm is not None and float(mm.group(2)) > float(mm.group(5)), st[:300])
        ok("text: Frost Isle / Opens in a future update", "Title=Frost Isle" in st and "Sub=Opens in a future update" in st, st[-160:])
    cl = C("local t={} for _,o in workspace:GetDescendants() do if o.Name=='FrostSign' then for _,l in o:GetDescendants() do if l:IsA('TextLabel') then t[#t+1]=l.Name..'='..l.Text end end end end return table.concat(t,' | ')")
    P(f"[{lang}] sign on the client:", cl)
    want = {"en": ("Frost Isle", "Opens in a future update"), "es": ("Isla Frost", "Se abrirá en una próxima actualización")}[lang]
    ok(f"[{lang}] sign text on the client", f"Title={want[0]}" in cl and f"Sub={want[1]}" in cl, cl)
    cam("1050,12,4", "1094,14,0", f"{lang}_approach")
    if lang == "en":
        cam("1078,12,22", "1094,13,0", "side")
        cam("1010,45,-25", "1094,8,0", "flight")
    C("game:GetService('RunService'):UnbindFromRenderStep('p8cam') workspace.CurrentCamera.CameraType=Enum.CameraType.Custom "
      "local c=game.Players.LocalPlayer.Character local r=c and c:FindFirstChild('HumanoidRootPart') if r then r.Anchored=false end return 'ok'")
stop()
edit("game.ReplicatedStorage:SetAttribute('LocTest', nil) return 'reset'")
write_result("Frost Isle sign on the rock (the island - in a later update)")
s.close()
