#!/usr/bin/env python3
"""Acceptance of the 'Dragon of the week' stand on the plaza (07 Add. 2.2 P29, server DragonStand, client Shop.view) in a LOCAL
file on P8. Before the update 2 date there is no stand; in the update 2 week - Cinder (Adult, Ember, Epic, preset cinder) on
a stone stand at the stall, a sign (title, name, rarity and element), ProximityPrompt View; the real E key nearby
opens the shop on the Nest tab with the Cinder card; after 7 days there is no stand; in the update 4 week - Nightfall; after its
window - none. Frames of the stand from four sides and from the path from the stall; console.
Run: python3 tests/p8/stand_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("stand_check")
from p8lib import *  # noqa: F401,F403

POLL = 12  # Config.LiveOps.pollSeconds = 10 + margin
U = "local U=require(game.ReplicatedStorage.Shared.Content).Updates "
def lo(cmd): return S(f"return game.ServerStorage.LiveOpsDebug:Invoke('{cmd}')")
def at(expr):  # shift the LiveOps clock to the moment expr (Luau, via U and os.time())
    return S(U + f"return game.ServerStorage.LiveOpsDebug:Invoke('offset '..math.floor(({expr}) - os.time()))")
STAND = ("local m=workspace:FindFirstChild('World') and workspace.World:FindFirstChild('DragonStand') if not m then return 'none' end "
         "local d for _,c in m:GetChildren() do if c:IsA('Model') and c:GetAttribute('Stand') then d=c end end "
         "local b=m:FindFirstChild('StandBase') local pr=b and b:FindFirstChild('StandView') "
         "local cf,sz if d then cf,sz=d:GetBoundingBox() end "
         "local ex={m} for _,p in game.Players:GetPlayers() do if p.Character then ex[#ex+1]=p.Character end end "
         "local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances=ex "
         "local hit=workspace:Raycast(Vector3.new(b.Position.X,120,b.Position.Z),Vector3.new(0,-200,0),rp) "
         "return string.format('sku=%s el=%s rar=%s st=%s preset=%s name=%s tag=%s dragonBottom=%.1f baseTop=%.1f baseBottom=%.1f ground=%.1f groundHit=%s prompt=%s/%s dist=%s size=%.1fx%.1fx%.1f at=%.0f,%.0f', "
         "tostring(m:GetAttribute('Sku')), tostring(d and d:GetAttribute('Element')), tostring(d and d:GetAttribute('Rarity')), tostring(d and d:GetAttribute('Stage')), "
         "tostring(d and d:GetAttribute('Preset')), tostring(d and d:GetAttribute('DragonName')), tostring(game:GetService('CollectionService'):HasTag(m,'DragonStand')), "
         "d and cf.Position.Y-sz.Y/2 or -1, b.Position.Y+b.Size.X/2, b.Position.Y-b.Size.X/2, hit and hit.Position.Y or -1, hit and hit.Instance.Name or '-', "
         "tostring(pr and pr.ActionText), tostring(pr and pr.ObjectText), tostring(pr and pr.MaxActivationDistance), sz and sz.X or 0, sz and sz.Y or 0, sz and sz.Z or 0, b.Position.X, b.Position.Z)")
SIGN = ("local m=workspace:FindFirstChild('World') and workspace.World:FindFirstChild('DragonStand') if not m then return 'none' end "
        "local s=m:FindFirstChild('StandSign') local l=s and s:FindFirstChild('Label') if not l then return 'nolabel' end "
        "local t={} for _,n in {'Title','Name','Kind','Price'} do local x=l:FindFirstChild(n) t[#t+1]=n..'='..(x and x.Text or '?') end return table.concat(t,' | ')")

def stand(): return S(STAND)
def cam_shot(name, eye, look):
    C(f"local c=workspace.CurrentCamera c.CameraType=Enum.CameraType.Scriptable c.CFrame=CFrame.lookAt(Vector3.new({eye}),Vector3.new({look})) return 'ok'")
    time.sleep(1.5); shot(name)

stop(); start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
P("clock:", lo("offset 0"))
time.sleep(POLL)
s0 = stand(); P("today:", s0)
ok("before update 2 there is no stand (server)", s0 == "none", s0)
ok("before update 2 there is no stand (client)", C("return tostring(workspace:FindFirstChild('World') and workspace.World:FindFirstChild('DragonStand') ~= nil)") in ("false", "nil"))

# update 2 week: Cinder
P("clock:", at("U[2].activeFrom + 3600")); time.sleep(POLL)
s1 = stand(); P("update 2:", s1)
m = re.search(r"dragonBottom=([-\d.]+) baseTop=([-\d.]+) baseBottom=([-\d.]+) ground=([-\d.]+)", s1)
ok("update 2 week: Cinder, Ember Epic, Adult, preset cinder, tag", "sku=DragonWeek_1_199 el=ember rar=Epic st=2 preset=cinder name=Cinder tag=true" in s1, s1)
ok("the stand is on the plaza (bottom = ground +-0.3), the dragon on the stand (+-0.3)", m is not None and abs(float(m.group(3)) - float(m.group(4))) <= 0.3 and abs(float(m.group(1)) - float(m.group(2))) <= 0.3, s1)
ok("the View prompt with the name, distance 14", "prompt=View/Cinder dist=14" in s1, s1)
time.sleep(2)
sg = C(SIGN); P("sign (client):", sg)
ok("sign: Dragon of the week / Cinder / Epic Ember", sg.startswith("Title=Dragon of the week | Name=Cinder | Kind=Epic Ember | Price="), sg)
P("price on the sign (empty before 3:00 of the first session - the robuxAllowed rule):", sg.rsplit("Price=", 1)[-1])
# on P8 BillboardGui labels do not get into the frame (at the stall too) - we check that the engine draws it: enabled, on-screen size
lb = C("local m=workspace.World:FindFirstChild('DragonStand') local s=m and m:FindFirstChild('StandSign') local l=s and s:FindFirstChild('Label') "
       "if not l then return 'none' end return tostring(l.Enabled)..' '..math.floor(l.AbsoluteSize.X)..'x'..math.floor(l.AbsoluteSize.Y)")
ok("the sign is drawn (Enabled, on-screen size > 0)", re.match(r"true [1-9]\d*x[1-9]\d*$", lb) is not None, lb)

# frames: four sides and from the path from the stall
bx, bz = 14, -32
mm = re.search(r"at=(-?\d+),(-?\d+)", s1)
if mm: bx, bz = int(mm.group(1)), int(mm.group(2))
for name, dx, dz in (("S1_south", 0, 26), ("S2_east", 26, 0), ("S3_north", 0, -26), ("S4_west", -26, 0)):
    cam_shot(name, f"{bx + dx},{30},{bz + dz}", f"{bx},{24},{bz}")
cam_shot("S5_from_stall_path", "0,26,-14", f"{bx},{23},{bz}")
cam_shot("S6_wide_plaza", "-30,48,30", f"{bx},{20},{bz}")
C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 'ok'"); time.sleep(1)

# View: the player nearby, the real E key
S(f"local ch=game.Players:GetPlayers()[1].Character ch:PivotTo(CFrame.lookAt(Vector3.new({bx - 8},{24},{bz + 6}),Vector3.new({bx},{24},{bz}))) return 'ok'")
time.sleep(3)
pv = C("local pp=game:GetService('ProximityPromptService') return tostring(pp.Enabled)")
P("ProximityPromptService:", pv); shot("V0_prompt")
P(keys("down e;wait 150;up e", t=120)[-80:]); time.sleep(2.5)
book = gui_on("Book")
card_ok = C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local c=b and b:FindFirstChild('Card_DragonWeek_1_199',true) return tostring(c~=nil and c.Visible)")
shot("V1_after_E")
ok("the E key at the stand: the shop is open, the Cinder card in view", book and card_ok == "true", f"book={book} card={card_ok}")
C(CD + "cd('back') return 'ok'"); time.sleep(1)

# after 7 days - none
P("clock:", at("U[2].activeFrom + 7*86400 + 60")); time.sleep(POLL)
s2 = stand(); P("after 7 days:", s2)
ok("7 days after update 2 there is no stand", s2 == "none", s2)
# update 4 week: Nightfall
P("clock:", at("U[4].activeFrom + 3600")); time.sleep(POLL)
s3 = stand(); P("update 4:", s3)
ok("update 4 week: Nightfall, Dusk Legendary, Adult", "sku=DragonWeek_2_299 el=dusk rar=Legendary st=2" in s3 and "name=Nightfall" in s3, s3)
cam_shot("S7_nightfall", f"{bx},{30},{bz + 26}", f"{bx},{24},{bz}")
P("clock:", at("U[4].activeFrom + 7*86400 + 60")); time.sleep(POLL)
s4 = stand(); P("after the Nightfall window:", s4)
ok("after the Nightfall window there is no stand", s4 == "none", s4)
P("clock:", lo("offset 0"))

cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"DragonStand|Stack Begin|attempt to", l) and "not authorized" not in l]
ok("console: without DragonStand and script errors", not errs, " ;; ".join(errs[:6]))
stop()
write_result("Dragon of the week stand")
s.close()
