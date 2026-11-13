#!/usr/bin/env python3
"""The heather under_heather (own gpt-image-2 cards, without
alpha - a purple lump) is replaced with realistic Creator Store kinds, the layout does not shift. In a LOCAL file on P8:
before - the heather spots (terrace garden, terrace foot, the thicket on the meadow) are written to spots.json, frames from 4 sides and from above,
close-ups of the candidates (cs_wildflower, cs_flower, cs_bush, under_heather) and the part count per kind; after - the same spots
(spots.json), heather in the layout and in the world 0, in the heather spots - the new kinds.
Run: python3 tests/p8/heather_swap_check.py before|after (after tools/p8/open_local.sh). Output: p8lib.OUT/<tag>_*."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
TAG = sys.argv[1] if len(sys.argv) > 1 else "after"
p8lib.begin("heather_swap_check")
from p8lib import *  # noqa: F401,F403
SPOTS_FILE = os.path.join(p8lib.OUT, "spots.json")

stop(); start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
for _ in range(40):
    if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
        break
    time.sleep(3)

KINDS = ("under_heather", "cs_wildflower", "cs_flower", "cs_bush", "under_shrub")
LAYOUT = S("local RS=game.ReplicatedStorage local DL=require(RS.Shared.Core.DecorLayout) local c={} "
           "for _,it in DL.items() do c[it.kind]=(c[it.kind] or 0)+1 end local t={} "
           "for _,k in {%s} do t[#t+1]=k..'='..tostring(c[k] or 0) end return table.concat(t,' ')" % ",".join(f"'{k}'" for k in KINDS))
P(f"[{TAG}] layout:", LAYOUT)
WORLD = S("local M=workspace.World.Meshes local t={} for _,k in {%s} do local f=M:FindFirstChild(k) local n,p=0,0 "
          "if f then for _,m in f:GetChildren() do n+=1 for _,d in m:GetDescendants() do if d:IsA('BasePart') then p+=1 end end end end "
          "t[#t+1]=string.format('%%s=%%d (parts %%d, per piece %%.1f)',k,n,p,if n>0 then p/n else 0) end return table.concat(t,'; ')"
          % ",".join(f"'{k}'" for k in KINDS))
P(f"[{TAG}] in the world:", WORLD)

if TAG == "before":
    # spots: terrace garden (y = terrace), terrace foot / Springs (own y), the heather thicket on the meadow (most neighbours within 25 studs)
    SP = S("local RS=game.ReplicatedStorage local W=require(RS.Shared.Config).World local DL=require(RS.Shared.Core.DecorLayout) "
           "local items=DL.items() local g,f,best,bn=nil,nil,nil,-1 local ground={} "
           "for i,it in items do if it.kind=='under_heather' then if it.y==W.terrace.y then g=g or i elseif it.y~=nil then f=f or i else table.insert(ground,i) end end end "
           "for _,i in ground do local a=items[i] local n=0 for _,j in ground do local b=items[j] if (a.x-b.x)^2+(a.z-b.z)^2<625 then n+=1 end end if n>bn then best,bn=i,n end end "
           "local function s(name,i) if not i then return name..' none' end local it=items[i] return string.format('%s %d %.1f %.1f %s',name,i,it.x,it.z,tostring(it.y)) end "
           "return s('garden',g)..'|'..s('foot',f)..'|'..s('meadow',best)..'|n='..bn")
    P("heather spots:", SP)
    spots = []
    for part in SP.split("|"):
        m = re.match(r"(\w+) (\d+) (-?[\d.]+) (-?[\d.]+) (\S+)", part)
        if m:
            spots.append({"name": m.group(1), "i": int(m.group(2)), "x": float(m.group(3)), "z": float(m.group(4))})
    json.dump(spots, open(SPOTS_FILE, "w"), ensure_ascii=False, indent=1)
    ok("BEFORE the fix: heather exists in the layout and in the world (reproduction)", "under_heather=0" not in LAYOUT and "under_heather=0 " not in WORLD, LAYOUT)
else:
    spots = json.load(open(SPOTS_FILE))
    ok("no heather in the layout", "under_heather=0" in LAYOUT, LAYOUT)
    ok("no heather in the world", WORLD.startswith("under_heather=0 "), WORLD)
    SWAP = S("local DL=require(game.ReplicatedStorage.Shared.Core.DecorLayout) local items=DL.items() local t={} "
             "for _,i in {%s} do local it=items[i] t[#t+1]=string.format('%%d %%s %%.1f %%.1f',i,it.kind,it.x,it.z) end return table.concat(t,' | ')"
             % ",".join(str(sp["i"]) for sp in spots))
    P("in the heather spots:", SWAP)
    same = all(f"{sp['i']} " in SWAP and f"{sp['x']:.1f} {sp['z']:.1f}" in SWAP for sp in spots)
    ok("the layout did not shift: the same numbers have the same coordinates, the kind is new", same and "under_heather" not in SWAP, SWAP)
    # Creator Store cs_bush in a local file is not loaded by InsertService (like the spruces/pines) - only for the frames: the same asset via
    # GetObjects (Studio context; a foreign Script inside the bush is deleted BEFORE insertion, like Decor.preparePbr) at the cs_bush spots within 40 studs of the points, by height h and ground, like Decor.placeWorld
    FILL = S("local DL=require(game.ReplicatedStorage.Shared.Core.DecorLayout) local ok,objs=pcall(function() return game:GetObjects('rbxassetid://106219688090496') end) "
             "if not ok or not objs[1] then return 'none: '..tostring(objs) end local src=objs[1] for _,d in src:GetDescendants() do if d:IsA('LuaSourceContainer') or d:IsA('Sound') then d:Destroy() end end local f=Instance.new('Folder') f.Name='P8_bush_fill' f.Parent=workspace "
             "local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Include rp.FilterDescendantsInstances={workspace.Terrain} local n=0 "
             "for _,it in DL.items() do if it.kind=='cs_bush' then local near=false for _,p in {%s} do if (it.x-p[1])^2+(it.z-p[2])^2<1600 then near=true end end "
             "if near then local m=src:Clone() if not m:IsA('Model') then local w=Instance.new('Model') m.Parent=w m=w end for _,d in m:GetDescendants() do if d:IsA('BasePart') then d.Anchored=true d.CanCollide=false end end "
             "local c,sz=m:GetBoundingBox() m:ScaleTo(m:GetScale()*it.h/sz.Y) local y=it.y if y==nil then local h=workspace:Raycast(Vector3.new(it.x,400,it.z),Vector3.new(0,-500,0),rp) y=h and h.Position.Y or 0 end "
             "local c2,s2=m:GetBoundingBox() m:PivotTo(CFrame.new(it.x,y+s2.Y/2-0.2,it.z)*CFrame.Angles(0,math.rad(it.yaw),0)*(c2:ToObjectSpace(m:GetPivot()))) m.Parent=f n+=1 end end end "
             "return 'placed '..n" % ",".join(f"{{{sp['x']},{sp['z']}}}" for sp in spots))
    P("stand: cs_bush bushes for the frames:", FILL)


def cam(eye, look):
    C("local c=workspace.CurrentCamera local cf=CFrame.lookAt(Vector3.new(%s),Vector3.new(%s)) local RunS=game:GetService('RunService') "
      "pcall(function() RunS:UnbindFromRenderStep('p8cam') end) RunS:BindToRenderStep('p8cam',Enum.RenderPriority.Last.Value+1,function() "
      "c.CameraType=Enum.CameraType.Scriptable c.CFrame=cf end) return 'ok'" % (eye, look))
    time.sleep(2.0)


def ground_y(x, z):
    gy = S(f"local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances={{workspace.World.Meshes, workspace:FindFirstChild('P8_bush_fill')}} "
           f"local h=workspace:Raycast(Vector3.new({x},400,{z}),Vector3.new(0,-500,0),rp) return h and string.format('%.1f',h.Position.Y) or 'none'")
    return float(gy) if gy != "none" else 10.0


def park(x, y, z):
    # the character high above the point, as an anchor: streaming keeps the place loaded, it does not get into the frame
    S("local p=game.Players:GetPlayers()[1] local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart') "
      f"if r then r.Anchored=true p.Character:PivotTo(CFrame.new({x},{y + 220},{z})) end return 'ok'")
    time.sleep(3)


for sp in spots:
    x, z = sp["x"], sp["z"]
    y = ground_y(x, z)
    park(x, y, z)
    for d, dx, dz in (("S", 0, 9), ("E", 9, 0), ("N", 0, -9), ("W", -9, 0)):
        cam(f"{x + dx},{y + 4},{z + dz}", f"{x - dx * 0.2},{y + 1},{z - dz * 0.2}"); shot(f"{TAG}_{sp['name']}_{d}")
    cam(f"{x + 1},{y + 30},{z + 1}", f"{x},{y},{z}"); shot(f"{TAG}_{sp['name']}_top")

if TAG == "before":
    # close-ups of the candidates: the first piece of each kind on the ground
    for k in ("cs_wildflower", "cs_flower", "cs_bush", "under_heather"):
        pos = S(f"local f=workspace.World.Meshes:FindFirstChild('{k}') if not f then return 'none' end for _,m in f:GetChildren() do "
                "local c,s=m:GetBoundingBox() if c.Position.Y<80 then return string.format('%.1f %.1f %.1f %.1f',c.Position.X,c.Position.Y,c.Position.Z,s.Y) end end return 'none'")
        P(f"close-up {k}:", pos)
        if pos == "none":
            continue
        x, y, z, h = map(float, pos.split())
        park(x, y, z)
        r = max(5.0, h * 2.2)
        cam(f"{x + r},{y + h * 0.6},{z + r * 0.4}", f"{x},{y},{z}"); shot(f"cand_{k}")

C("game:GetService('RunService'):UnbindFromRenderStep('p8cam') workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 'ok'")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|build failed|no height", l) and "ExecuteLuau" not in l]
ok(f"[{TAG}] console without script errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result(f"Heather -> realistic kinds ({TAG})")
s.close()
