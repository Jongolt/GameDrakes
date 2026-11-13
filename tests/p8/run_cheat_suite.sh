#!/bin/bash
# the anti-cheat run on P8 from a copy of the cheat-guard branch (a separate worktree). Run only on purpose:
# P8 and the local file on it are shared with other game sessions. Steps: 1) shared state (foreign commits, P8, fresh probes);
# 2) merge a fresh main into the branch; 3) unit tests + inflation_spec; 4) build + inspect_place; 5) the place on P8 (open_local.sh from the copy);
# 6) cheat_check.py; 7) newcomer_check.py WH - regression of an honest pass against the baseline (newcomer_check_run1).
# Run: bash tests/p8/run_cheat_suite.sh        (FORCE=1 - do not stop on a fresh foreign probe)
set -u
WT=$(cd "$(dirname "$0")/../.." && pwd)
MAIN=${MAIN:-$WT}
BOT=${BOT:?set BOT to the folder that holds tools/luau and tools/lune}
BASE=${BASE:-runs/roblox_build_2026-10-19/newcomer_check_run1/result.md}
cd "$WT" || exit 1
source tools/p8/common.sh
say() { echo; echo "== $*"; }

say "1. shared state"
git -C "$MAIN" fetch origin -q 2>/dev/null
echo "origin/main: $(git -C "$MAIN" log --oneline -1 origin/main)"
echo "main:        $(git -C "$MAIN" log --oneline -1 main)"
echo "branch:      $(git -C "$WT" log --oneline -1)"
echo "changes in the shared tree:"; git -C "$MAIN" status --short | head -10
echo "P8: $(p8_state)"
if [ "$(p8_state)" != "running" ]; then echo "P8 is not running: bash tools/p8/up.sh 90 (on the owner's word)"; exit 2; fi
OUTR=$(grep '^P8_OUT_ROOT' "${P8_ENV:-$HOME/.config/p8/p8.env}" | cut -d= -f2 | tr -d '"')
FRESH=$(find "$OUTR" -maxdepth 3 -newermt '-10 minutes' -type f 2>/dev/null | grep -v cheat_check | head -5)
if [ -n "$FRESH" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "a foreign probe wrote files in the last 10 minutes - P8 is busy:"; echo "$FRESH"; exit 3
fi
p8_ssh 'tasklist /fi "imagename eq RobloxStudioBeta.exe"' 2>/dev/null | tail -2

say "2. fresh main into the branch"
if ! git -C "$WT" merge --no-edit main >/dev/null 2>&1; then
  git -C "$WT" merge --abort 2>/dev/null; echo "merge conflict with main - resolve by hand"; exit 4
fi
git -C "$WT" log --oneline -1

say "3. unit tests"
FAILT=0
for t in run balance_spec shop_spec content_spec hatch_spec voices_spec loc_spec looks_spec inflation_spec; do
  f="$WT/tests/$t.luau"; [ -f "$f" ] || continue
  full=$(cd "$BOT" && timeout 600 tools/luau/luau "$f" 2>&1); rc=$?
  echo "$t: rc=$rc $(echo "$full" | tail -1)"
  if [ $rc != 0 ] || echo "$full" | grep -qE "failed [1-9]|[1-9][0-9]* failed|^FAIL "; then FAILT=1; fi
done
# unknown names (a variable not declared in this file - the game will crash on the first call; the compiler lets that through)
KNOWN="game|workspace|Instance|Vector3|Vector2|CFrame|Enum|task|warn|typeof|Region3|RaycastParams|Color3|UDim2|UDim|script|tick|time|os|math|string|table|debug|utf8|bit32|coroutine|buffer|ColorSequence|NumberSequence|NumberRange|ColorSequenceKeypoint|NumberSequenceKeypoint|Ray|TweenInfo|BrickColor|PhysicalProperties|Font|DateTime|Random|OverlapParams|Faces|Axes|Rect|delay|spawn|wait|elapsedTime|settings|plugin|shared|_G|SharedTable|Content|CatalogSearchParams"
UNK=$(for f in $(find src -name '*.luau'); do "$BOT/tools/luau/luau-analyze" "$f" 2>&1 | grep "Unknown global" | grep -vE "Unknown global '($KNOWN)'"; done)
if [ -n "$UNK" ]; then echo "unknown names:"; echo "$UNK" | head; FAILT=1; else echo "no unknown names"; fi
[ $FAILT = 1 ] && { echo "unit tests are red - not going to P8"; exit 5; }

say "4. build"
python3 build.py | tail -1 || exit 6
(cd "$BOT" && timeout 300 tools/lune/lune run "$WT/tests/inspect_place.luau" "$WT/build/place.rbxlx" | tail -1)
(cd "$BOT" && timeout 300 tools/lune/lune run "$WT/tests/security_place.luau" "$WT/build/place.rbxlx" | tail -1) || { echo "place file security - failed"; exit 6; }

say "5. the place on P8 (a local file from the copy)"
bash tools/p8/open_local.sh || exit 7
sleep 20

say "6. cheat_check"
python3 tests/p8/cheat_check.py; CHEAT=$?

say "7. regression: newcomer_check WH (the guard in Studio only counts)"
bash tools/p8/open_local.sh >/dev/null && sleep 20
python3 tests/p8/newcomer_check.py WH
NEW=$(ls -td "$OUTR"/roblox_build_*/newcomer_check* 2>/dev/null | head -1)/result.md
echo "new FAILs against the 19.10 baseline:"
comm -13 <(grep "| FAIL |" "$BASE" | cut -d'|' -f2 | sort -u) <(grep "| FAIL |" "$NEW" | cut -d'|' -f2 | sort -u)
echo; echo "cheat_check: FAIL $CHEAT; results: $OUTR/roblox_build_$(date -u +%F)/"
