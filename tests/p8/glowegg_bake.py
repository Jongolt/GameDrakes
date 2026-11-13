#!/usr/bin/env python3
"""Ember glow templates (4 stages, masks A Config.Glow) into the place in Studio edit mode (the Plugin right -
only here, recipe of the light session: runs/roblox_glow_phone_test_2026-10-25/tpl_only.py), saving the file Ctrl+S, the file - to the VPS (publishing
via Open Cloud separately). Then Play: after the 'flight' the own glowing egg on the islet, pickup (glow), bowl, hatch -> Glow dragon, at night
GlowSA on its meshes, console without errors. Run: python3 tests/p8/glowegg_bake.py (after open_local with the glow-egg build)."""
import os, re, sys, time, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("glowegg_bake")
from p8lib import *  # noqa: F401,F403

def E(code): return run(code, "Edit")
def ld(c): return S(LD + f"return ld('{c}')")
def prof(expr): return S(LD + "local d=game:GetService('HttpService'):JSONDecode(ld('dump')) return " + expr)
# no require: a module loaded in the MCP Studio context crashed ('Requested module experienced an error while loading') - the numbers right here
# (Content.Assets.dragons.ember by stage, Config.Glow masks A Ember by stage, tint, strength)
TPL = """local IS=game:GetService('InsertService') local RS=game:GetService('ReplicatedStorage')
local old=RS:FindFirstChild('GlowTemplates') if old then old:Destroy() end
local f=Instance.new('Folder') f.Name='GlowTemplates' f.Parent=RS local out={}
local function texs(id) local m=IS:LoadAsset(id) local t={} for _,d in m:GetDescendants() do if d:IsA('MeshPart') and d.TextureID~='' and not table.find(t,d.TextureID) then table.insert(t,d.TextureID) end end m:Destroy() return t end
local function make(key,tex,mask,tint,strength)
 for ph,mult in {night=1,dusk=0.5,day=0} do local s=Instance.new('SurfaceAppearance') s.Name=key..'|'..ph
  s.ColorMapContent=Content.fromUri(tex) s.EmissiveMaskContent=Content.fromUri('rbxassetid://'..mask) s.EmissiveTint=Color3.fromRGB(tint[1],tint[2],tint[3])
  s.EmissiveStrength=strength*mult s:SetAttribute('Texture',tex) s.Parent=f end end
local models={78838233837073,85804747975507,76630870920482,120096038626275}
local masks={112800335424601,93773650836684,112926808469068,91904030921853}
for stage=1,4 do for i,t in texs(models[stage]) do make('ember_s'..stage..'_'..i,t,masks[stage],{255,150,60},6) table.insert(out,'s'..stage..'_'..i..'='..t) end end
return #f:GetChildren()..' templates: '..table.concat(out,',')"""

stop()
P("templates:", E(TPL)[:600])
cnt = E("local f=game.ReplicatedStorage:FindFirstChild('GlowTemplates') return f and #f:GetChildren() or 0")
ok("1. Ember templates in the place (4 stages x phases)", str(cnt).isdigit() and int(cnt) >= 12, cnt)
sh("bash tools/p8/keys.sh 'down ctrl;down s;wait 200;up s;up ctrl;wait 3000'")
time.sleep(4)
LOCAL = f"{OUT}/place_baked.rbxlx"
sh(f'scp "${{P8_SSH_OPTS[@]}}" "$P8_USER@$(p8_ip):C:/p8/place.rbxlx" {LOCAL}', 300)
txt = open(LOCAL, encoding="utf-8", errors="replace").read() if os.path.exists(LOCAL) else ""
nsa = len(re.findall(r'class="SurfaceAppearance"', txt))
ok("2. saved file: SurfaceAppearance templates in the place", nsa >= 12 and "EmissiveMask" in txt, f"{nsa} SA, {len(txt)} bytes")

# Play: glowing egg after the flight -> Glow dragon -> light at night
P("seed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end "
               "s.Value='{\"coins\":0,\"onboarding\":{\"flew\":true,\"firstHatch\":true,\"rode\":true}}' return #s.Value", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
egg = None
for _ in range(30):
    egg = S("local f=workspace:FindFirstChild('GlowEggs') local m=f and f:FindFirstChildWhichIsA('Model') if not m then return 'none' end local p=m:GetPivot().Position return string.format('%.1f,%.1f,%.1f',p.X,p.Y,p.Z)")
    if egg != "none": break
    time.sleep(1)
ok("3. after the flight the own glowing egg on the islet", egg not in (None, "none"), egg)
g = C("local pg=game.Players.LocalPlayer.PlayerGui local o={} for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and d.Visible and d.Text~='' then table.insert(o,d.Text) end end return table.concat(o,' | ')")
ok("3b. GLOW step / announcement", "glowing egg" in g.lower() or "GLOWING EGG" in g, g[:240])
if egg not in (None, "none"):
    S("local p=Vector3.new(" + egg + ") game.Players:GetPlayers()[1].Character:PivotTo(CFrame.new(p+Vector3.new(0,4,2))) return 'tp'")
    time.sleep(2.5)
c = prof("tostring(d.eggs.carry and d.eggs.carry.glow)..' '..tostring(d.eggs.carry and d.eggs.carry.element)..' '..tostring(d.glowEgg and d.glowEgg.taken)")
ok("4. egg in the hands: glow true, ember, taken", str(c).startswith("true ember") and not str(c).endswith(" 0"), c)
P("place:", str(ld("place 1"))[:60]); time.sleep(22)
P("hatch:", str(ld("hatch 1"))[:60]); time.sleep(8)
dr = prof("(function() for _,x in d.dragons do if x.glow then return x.name..' '..x.element..' '..x.rarity end end return 'none' end)()")
ok("5. a glowing dragon hatched (glow, Glowing Ember)", str(dr).startswith("Glowing Ember ember"), dr)
gm = C("local n=0 for _,m in game:GetService('CollectionService'):GetTagged('Dragon') do if m:GetAttribute('Glow') then n+=1 end end return n")
ok("5b. dragon model with the Glow attribute", str(gm) != "0", gm)
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','night') task.wait(1) return 'night'"); time.sleep(6)
sa = C("local n,s=0,0 for _,d in workspace:GetDescendants() do if d:IsA('SurfaceAppearance') and d.Name=='GlowSA' then n+=1 s+=d.EmissiveStrength end end return n..' '..s")
ok("6. at night light on the glowing dragon meshes (GlowSA, strength > 0)", str(sa).split(" ")[0] != "0" and float(str(sa).split(" ")[1]) > 0, sa)
desk("night_glow")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[GlowEgg]" in l or "[Glow]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("7. console without game errors", not bad, str(len(bad)))
for l in bad[-8:]: P("  ", l[:220])
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
write_result("Glowing egg: templates and the path in Play")
