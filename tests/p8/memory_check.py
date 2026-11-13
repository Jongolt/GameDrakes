#!/usr/bin/env python3
"""CLIENT MEMORY by category on P8 (local file, phone window 812x375).
A real phone showed mem ~1 500 MB against the spec budget of 400. What we measure here:
(1) all Enum.DeveloperMemoryTag + GetTotalMemoryUsageMb on the client at 4 points (join, nest with 3 dragons, meadow, flight);
(2) the Lua heap of OUR VM: gcinfo() on the client and on the server (Roblox CoreScripts are not in it) - before and after collectgarbage;
(3) what is in our heap: the JSON size of each ReplicatedStorage.Shared module (data), instance count by class, unique
MeshId/TextureId/SoundId in the world, the Sound count and their loading, the Terrain size (voxels), GUI objects.
Studio is not a phone: the LuaHeap tag includes Studio plugins; compare gcinfo() and the structure, not the total figure.
Run: python3 tests/p8/memory_check.py (after tools/p8/open_local.sh). Output: $P8_OUT_ROOT/roblox_build_<date>/memory_check/."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("memory_check")
from p8lib import *  # noqa: F401,F403

TAGS = r"""
local Stats=game:GetService('Stats') local out={}
for _,e in Enum.DeveloperMemoryTag:GetEnumItems() do local ok,mb=pcall(function() return Stats:GetMemoryUsageMbForTag(e) end) if ok then out[#out+1]=string.format('%s=%.1f', e.Name, mb) end end
table.sort(out, function(a,b) return tonumber(a:match('=(.*)')) > tonumber(b:match('=(.*)')) end)
return string.format('total=%.0f gc=%.1f | ', Stats:GetTotalMemoryUsageMb(), gcinfo()/1024)..table.concat(out,' ')
"""
GC = "return string.format('%.1f MB (plugin VM; our VM - ClientDebug gc / LoopDebug gc)', collectgarbage('count')/1024)"  # in Roblox Luau collectgarbage only supports 'count'
MODULES = r"""
local HS=game:GetService('HttpService') local out={}
local function size(v) local ok,s=pcall(function() return #HS:JSONEncode(v) end) return ok and s or -1 end
local function scan(folder, prefix, depth)
  for _,m in folder:GetChildren() do
    if m:IsA('ModuleScript') then
      local ok,v=pcall(require, m)
      if ok and type(v)=='table' then local s=size(v) if s>=0 then out[#out+1]={prefix..m.Name, s} end end
    elseif m:IsA('Folder') and depth<2 then scan(m, prefix..m.Name..'/', depth+1) end
  end
end
scan(game.ReplicatedStorage:WaitForChild('Shared'), '', 0)
table.sort(out, function(a,b) return a[2]>b[2] end)
local t={} for i=1,math.min(#out,25) do t[#t+1]=string.format('%s=%.0fKB', out[i][1], out[i][2]/1024) end
return table.concat(t,' ')
"""
INSTANCES = r"""
local cls={} local n=0 for _,d in game:GetDescendants() do n+=1 cls[d.ClassName]=(cls[d.ClassName] or 0)+1 end
local t={} for k,v in cls do t[#t+1]={k,v} end table.sort(t,function(a,b) return a[2]>b[2] end)
local s={} for i=1,math.min(#t,22) do s[#s+1]=t[i][1]..'='..t[i][2] end
return 'total '..n..' | '..table.concat(s,' ')
"""
ASSETS = r"""
local mesh,tex,snd,img={}, {}, {}, {} local nSound,loaded,playing=0,0,0 local mparts=0 local decals=0 local particles=0
for _,d in workspace:GetDescendants() do
  if d:IsA('MeshPart') then mparts+=1 if d.MeshId~='' then mesh[d.MeshId]=(mesh[d.MeshId] or 0)+1 end if d.TextureID~='' then tex[d.TextureID]=true end
  elseif d:IsA('SpecialMesh') then if d.MeshId~='' then mesh[d.MeshId]=(mesh[d.MeshId] or 0)+1 end if d.TextureId~='' then tex[d.TextureId]=true end
  elseif d:IsA('Decal') or d:IsA('Texture') then decals+=1 if d.Texture~='' then img[d.Texture]=true end
  elseif d:IsA('ParticleEmitter') then particles+=1 if d.Texture~='' then img[d.Texture]=true end
  elseif d:IsA('Sound') then nSound+=1 if d.IsLoaded then loaded+=1 end if d.IsPlaying then playing+=1 end if d.SoundId~='' then snd[d.SoundId]=true end end
end
for _,d in game:GetService('SoundService'):GetDescendants() do if d:IsA('Sound') then nSound+=1 if d.IsLoaded then loaded+=1 end if d.IsPlaying then playing+=1 end if d.SoundId~='' then snd[d.SoundId]=true end end end
local function cnt(t) local n=0 for _ in t do n+=1 end return n end
local top={} for id,c in mesh do top[#top+1]={id,c} end table.sort(top,function(a,b) return a[2]>b[2] end)
local tops={} for i=1,math.min(#top,8) do tops[#tops+1]=top[i][1]:gsub('rbxassetid://','')..'x'..top[i][2] end
local mv=game:GetService('MaterialService'):GetChildren() local mvn={} for _,m in mv do if m:IsA('MaterialVariant') then mvn[#mvn+1]=m.Name end end
return string.format('MeshPart %d (unique meshes %d, mesh textures %d; top: %s) | Decal/Texture %d (unique images %d) | ParticleEmitter %d | Sound %d (loaded %d, playing %d, unique %d) | MaterialVariant %d: %s',
  mparts, cnt(mesh), cnt(tex), table.concat(tops,' '), decals, cnt(img), particles, nSound, loaded, playing, cnt(snd), #mvn, table.concat(mvn,','))
"""
GUI = r"""
local pg=game.Players.LocalPlayer.PlayerGui local n=0 local byGui={} for _,g in pg:GetChildren() do local c=#g:GetDescendants() n+=c byGui[#byGui+1]={g.Name,c} end
table.sort(byGui,function(a,b) return a[2]>b[2] end) local s={} for i=1,math.min(#byGui,10) do s[#s+1]=byGui[i][1]..'='..byGui[i][2] end
local img=0 for _,d in pg:GetDescendants() do if d:IsA('ImageLabel') or d:IsA('ImageButton') then img+=1 end end
return 'objects in PlayerGui '..n..' (images '..img..') | '..table.concat(s,' ')
"""
TERRAIN = "local t=workspace.Terrain local r=t.MaxExtents local s=r.Max-r.Min return string.format('voxels %dx%dx%d (%.1f M)', s.X/4, s.Y/4, s.Z/4, (s.X/4)*(s.Y/4)*(s.Z/4)/1e6)"  # Terrain.Decoration is not accessible to scripts

def point(name):
    time.sleep(2)
    tags = run(TAGS, "Client", 120); P(f"[{name}] {tags}")
    gc = C(CD + "return tostring(cd('gc'))"); sgc = S(LD + "return tostring(ld('gc'))"); P(f"[{name}] gc client {gc} | server {sgc}")
    shot(f"MEM_{name}")
    return tags, gc

start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
time.sleep(15)
res_pts = {}
res_pts["spawn"] = point("spawn")
P("Shared modules (JSON, KB):", run(MODULES, "Client", 180))
P("instances:", run(INSTANCES, "Client", 120))
P("world assets:", run(ASSETS, "Client", 180))
P("GUI:", C(GUI))
P("terrain:", C(TERRAIN))
# nest with 3 dragons (table x3 -> bowl -> hatch; time is fast-forwarded)
for k in (1, 2, 3):
    S(LD + f"ld('go table') task.wait(0.8) ld('table {k}') task.wait(0.5) ld('go inc') task.wait(1) ld('place 1') task.wait(0.5) ld('time 900') task.wait(1.5) ld('hatch 1') return 'h{k}'"); time.sleep(9)
    if gui_on("NameDialog"): time.sleep(6)
S(LD + "ld('time 100000') task.wait(3) return 'adults'"); time.sleep(4)
S(LD + "ld('go pile') return 'x'"); time.sleep(6)
res_pts["nest3"] = point("nest3_adults")
P("instances at the nest:", run(INSTANCES, "Client", 120))
# meadow (landing under the ledge)
S("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end p.Character:PivotTo(n:GetPivot()*CFrame.new(0,3,110)) return 'meadow'"); time.sleep(10)
res_pts["meadow"] = point("meadow")
# flight on the adult (up 6 s)
m = S(LD + "return ld('mount d1')"); P("mount:", m[:100]); time.sleep(2)
C(CD + "return tostring(cd('fly up on'))"); time.sleep(6); C(CD + "return tostring(cd('fly off'))"); time.sleep(1)
res_pts["flight"] = point("flight")
C(CD + "return tostring(cd('fly up on'))"); time.sleep(2)  # even higher - loading of the far streaming chunks
C(CD + "return tostring(cd('fly off'))"); time.sleep(8)
res_pts["high"] = point("high")
P("world assets after the flight:", run(ASSETS, "Client", 180))
S(LD + "return ld('dismount')"); time.sleep(3)
# 3 minutes idle at the nest: does the heap grow (a leak)
S(LD + "ld('go pile') return 'x'"); time.sleep(2)
g0 = C(CD + "return tostring(cd('gc'))"); time.sleep(90); g1 = C(CD + "return tostring(cd('gc'))"); time.sleep(90); g2 = C(CD + "return tostring(cd('gc'))")
P("client Lua heap over 3 min idle:", g0, "|", g1, "|", g2)
res_pts["idle3m"] = point("idle3m")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l]
ok("console without game errors", not errs, " ;; ".join(errs[:4]))
ok("memory measurement taken at all points", all(v[0].startswith("total=") for v in res_pts.values()), ", ".join(res_pts))
stop()
write_result("Client memory by category on P8 (20.10)")
s.close()
