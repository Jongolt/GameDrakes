#!/usr/bin/env python3
"""Analysis of a newcomer20_check.py run: minute by minute - what the player saw (step banner, quest, toasts, world labels, HUD buttons,
position, server state) against the lines of spec 02 §2; which spec texts appeared and which did not. Writes minutes.md next to the run.
Run: python3 tests/p8/newcomer20_report.py [run folder]"""
import json, os, re, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get("RUNS_DIR", "runs"), "roblox_build_2026-10-20", "newcomer20")
tl = [json.loads(l) for l in open(f"{OUT}/timeline.jsonl", encoding="utf-8") if l.strip()]
texts = []
for l in open(f"{OUT}/texts.log", encoding="utf-8"):
    m = re.match(r"([\d.]+)\|(.*)", l.rstrip("\n"))
    if m: texts.append((float(m.group(1)), m.group(2)))
ev = json.load(open(f"{OUT}/events.json", encoding="utf-8"))
events = ev["events"]; findings = ev.get("findings", []); onboard = ev.get("onboard", {})

# spec 02 §2 lines (median) - what the player must see in this minute
TZ = {
    0: "spawn on the terrace; Old Ash: 'Welcome, rider. Pick an egg - any of the three.'; arrow to the table; the egg jumps into the hands (0:03-0:10): 'Warm egg! Put it in the nest'; "
       "hatch 0:10-0:13 (3 s scene, label 'Common Ember / 1/s / 1 in N'); name dialog 0:13-0:18 (auto-close 5 s); 0:18 Index 'Meadow set 2/10'; "
       "0:18-0:30 coins: '+1' above the baby, '1/s' above the nest, toast 'Coins fly to you when you walk over them'; 0:30-0:50 Old Ash quest "
       "'A nest grows with eggs. Find one in the meadow - jump off the ledge...', panel 'Keeper 1/15: Find a second egg'; 0:50-1:00 gliding 'Gliding! Steer with the camera'",
    1: "1:00-1:40 glade: the nearest egg glows, an arrow; above the egg 'Meadow egg'; after pickup 'Keep it warm! 1:30'; arrow to the stairs; 1:30-1:45 egg into the incubator "
       "(pill 'Meadow egg 2:59'), Keeper: 'Here are 50 coins. Berries at my stall make a dragon grow twice as fast.'; stall 'Berries - 60 coins' [Feed]; 1:45-2:00 first purchase - 'Fed! Growth x2 for 5:00'",
    2: "2:00-2:30 teen (~2:30): 'Your dragon grew up! Ride it.', above the dragon 'Ride'; 2:30-2:45 riding: 'Riding! Tap Dismount to get off', the Dismount button; 2:45-3:00 Free Gift card 'Welcome gift / Join ... - get a Moss egg (Uncommon or better)' [Join]",
    3: "3:00 at the incubator with an egg (> 30 s left) the button 'Hatch now [Robux] 9'; no windows; 3:30-4:30 second hatch 'An Uncommon Moss hatchling! / 1 in 4'",
    4: "4:00-5:00 quest 3 'Keeper 3/15: Bring an egg from the Cliffs', the Keeper gives 100 coins; the third egg on the shelf/in the incubator",
    5: "5:00 the 5-minute gift: a chest at the nest, 3 minutes of income '5-minute gift: +N coins / Next gift: 10:00'; 5:00-7:30 growth to adult (median 7:20): 'Your dragon can fly!', 2 s camera orbit",
    6: "(teen growth to adult continues; food x2 lasts 5 min from the purchase)",
    7: "5:00-7:30 adult: 'Your dragon can fly!', above the dragon 'Ride'; on mounting 3 s 'Hold Jump to climb. Crouch to dive.' (phone: Up/Down); 7:30-8:00 first flight 45 studs/s, a wind ring with an arrow 'Fly through the wind rings', "
       "the second island with the sign 'Frost Isle - needs an adult Frost dragon', card 'Hatch Party ...' [Invite friends]",
    8: "8:00-10:00 Summit open; goal 'Ascension I: an Adult dragon + 5,000 coins' [View]; panel of 3 dailies 'Daily quests / Collect 3 eggs 0/3 / Hatch 2 dragons 0/2 / Fly for 2 minutes'",
    9: "(the same; the 10-minute gift is getting ready)",
    10: "10:00-20:00 the first weather (storm): 'Storm! Coins x2 for 3:00. Dragons hatched now are Stormborn'; the 10-minute gift; Ascension I when ready 'Ascension I! Income x2'",
}
for m in range(11, 21): TZ[m] = "(10:00-20:00: storm, Ascension I when ready, 10-min gift; spec 02 does not detail further)"

# expected spec 02 texts (verbatim or by key) - did they appear during the run
EXPECT = [
    ("Welcome, rider", "0:00 Old Ash line"), ("Pick an egg", "0:00 line/step"), ("Warm egg", "0:03-0:10 after pickup"),
    ("Put it in the nest", "0:03-0:10"), ("1 in ", "0:10-0:13 rarity chance"), ("Name your dragon", "0:13-0:18 name dialog"),
    ("Index", "0:18 Index"), ("Coins fly to you", "0:18-0:30 toast"), ("Walk over the coins", "0:18-0:30 COINS step (our substitute)"),
    ("Find one in the meadow", "0:30-0:50 line/quest"), ("jump off the ledge", "0:30-0:50 line"), ("Step off the ledge", "0:30-1:00 GLIDE step (18.10)"),
    ("Gliding!", "0:50-1:00 toast"), ("Meadow egg", "1:00-1:40 egg label"), ("Keep it warm", "1:00-1:40 warmth bar"),
    ("Your nest is up the stairs", "02 §3 not carrying for 60 s"), ("Here are 50 coins", "1:30-1:45 Keeper"), ("Berries", "1:30-1:45 stall/quest"),
    ("Fed!", "1:45-2:00 food toast"), ("grew up", "2:00-2:30 teen banner"), ("Ride", "2:00-2:45 Ride"), ("Riding!", "2:30-2:45 toast"),
    ("Dismount", "2:30-2:45 button"), ("Welcome gift", "2:45-3:00 Free Gift card"), ("Join", "2:45-3:00 Join button"),
    ("Hatch now", "3:00 Robux button at the incubator"), ("Cliffs", "4:00-5:00 Cliffs quest"), ("gift", "5:00 5-minute gift"),
    ("Next gift", "5:00 next gift"), ("can fly", "5:00-7:30 adult banner"), ("Hold Jump", "7:30 takeoff hint"),
    ("wind rings", "7:30-8:00 rings"), ("Frost Isle", "7:30-8:00 second island sign"), ("Hatch Party", "7:30-8:00 card"),
    ("Invite", "7:30-8:00 Invite button"), ("Ascension", "8:00-10:00 goal"), ("Daily", "8:00-10:00 dailies"), ("Storm", "10:00-20:00 storm"),
    ("Stormborn", "10:00-20:00 storm"),
]

def fmt(t): t = int(t); return f"{t // 60}:{t % 60:02d}"
def minute_slice(m):
    rec = [r for r in tl if m * 60 <= r["t"] < (m + 1) * 60]
    tx = [(t, s) for t, s in texts if m * 60 <= t < (m + 1) * 60]
    evs = [(t, n, d) for t, n, d in events if m * 60 <= t < (m + 1) * 60]
    return rec, tx, evs
def pick(tx, prefix):
    out = []
    for t, s in tx:
        if s.startswith(prefix) and s not in out: out.append(s)
    return out

with open(f"{OUT}/minutes.md", "w", encoding="utf-8") as f:
    f.write("# Newcomer pass 20 minutes - minute by minute against spec 02 §2\n\n")
    f.write("Actual: probe events, screen texts (recorder 0.5 s: new labels), server state at the end of the minute.\n\n")
    for m in range(0, 21):
        rec, tx, evs = minute_slice(m)
        if not rec and not tx and not evs: continue
        f.write(f"## Minute {m} ({m}:00-{m}:59)\n\n**Spec 02:** {TZ.get(m, '-')}\n\n**Actual:**\n")
        for t, n, d in evs:
            f.write(f"- [{fmt(t)}] {n}" + (f" - {d[:160]}" if d else "") + "\n")
        groups = {}
        for t, s_ in tx:
            g, _, body = s_.partition(": ")
            groups.setdefault(g, [])
            if body not in groups[g]: groups[g].append(body)
        for g in ("StepBanner", "Quests", "Banners", "Toast", "Keeper", "KeeperCallout", "HUD", "Topbar", "FreeGiftCard", "NameDialog", "Gifts", "Weather", "Book", "Social", "Swim", "Movement", "LoadingScreen", "Away", "AwayCard"):
            if g in groups:
                f.write(f"- {g}: " + " / ".join(x[:80] for x in groups[g][:16]) + "\n")
        others = [g for g in groups if g not in ("StepBanner", "Quests", "Banners", "Toast", "Keeper", "KeeperCallout", "HUD", "Topbar", "FreeGiftCard", "NameDialog", "Gifts", "Weather", "Book", "Social", "Swim", "Movement", "LoadingScreen", "Away", "AwayCard")]
        for g in others:
            f.write(f"- {g}: " + " / ".join(x[:80] for x in groups[g][:10]) + "\n")
        worlds = []
        for r in rec:
            for part in r["texts"].split(" || "):
                if part.startswith("WORLD:") and part not in worlds: worlds.append(part)
        if worlds: f.write("- world labels nearby: " + " ; ".join(w[7:][:120] for w in worlds[:4]) + "\n")
        if rec:
            last = rec[-1]
            attr = [p for p in last["texts"].split(" || ") if p.startswith("ATTR")]
            f.write(f"- server at {fmt(last['t'])}: `{last['state'][:200]}`" + (f"; {attr[0]}" if attr else "") + "\n")
        f.write("\n")
    f.write("## Spec 02 texts: did they appear in 20 minutes\n\n| spec text | where by spec | actual (first appearance) |\n|---|---|---|\n")
    alltx = texts + [(r["t"], r["texts"]) for r in tl]
    for key, where in EXPECT:
        hit = next(((t, s_) for t, s_ in alltx if key.lower() in s_.lower()), None)
        f.write(f"| `{key}` | {where} | " + (f"{fmt(hit[0])}: {hit[1][:90].replace('|', '/')}" if hit else "NO") + " |\n")
    f.write("\n## Funnel steps\n\n")
    NAMES = {1: "spawn", 2: "egg_first_pick", 3: "hatch_first", 4: "coins_first_collect", 5: "glide_first", 6: "egg_second", 7: "feed_first",
             8: "juvenile_first", 9: "ride_first", 10: "hatch_second", 11: "adult_first", 12: "fly_first", 13: "ascension_first"}
    for k in sorted(int(x) for x in onboard):
        f.write(f"- {NAMES.get(k, k)}: {fmt(onboard[str(k)] if str(k) in onboard else onboard[k])}\n")
    f.write("\n## Stand discrepancies along the way\n\n")
    for t, txt in findings: f.write(f"- [{fmt(t)}] {txt}\n")
    if not findings: f.write("- none\n")
print("minutes.md:", f"{OUT}/minutes.md", "| timeline records", len(tl), "| texts lines", len(texts), "| events", len(events))
