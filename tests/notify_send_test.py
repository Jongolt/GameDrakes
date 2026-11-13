#!/usr/bin/env python3
"""Tools/notify_send.py without the network - a fake Open Cloud session. Run: python3 tests/notify_send_test.py
Checks: an empty queue, the due time not reached (the cache), sending and deletion, not opted in, throttling and 5xx - the entry stays,
a returning player, an old entry, a deletion failure in the log, a network failure on one entry does not break the run, the key does not get into the log."""
import json, os, sys, tempfile, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import requests  # noqa: E402
import notify_send as ns  # noqa: E402

KEY = "SECRET-KEY-123"
NOW = time.time()


class Resp:
    def __init__(self, code, body):
        self.status_code = code
        self.text = body if isinstance(body, str) else json.dumps(body)

    def json(self):
        return json.loads(self.text)

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(str(self.status_code))


class Fake:
    """The queue and profile storage in memory; post_reply[uid] - the reply to a send."""
    def __init__(self, queue, profiles=None, post_reply=None, delete_fail=(), boom=()):
        self.headers = {}
        self.queue = None if queue is None else dict(queue)
        self.profiles = profiles or {}
        self.post_reply = post_reply or {}
        self.delete_fail = set(delete_fail)
        self.boom = set(boom)
        self.posts, self.deletes = [], []

    def request(self, method, url, timeout=30, **kw):
        base = f"{ns.API}/universes/{ns.UNIVERSE}/data-stores/{ns.STORE}/entries"
        if method == "GET" and url.startswith(base + "?"):
            if self.queue is None:
                return Resp(404, {"code": 5})
            return Resp(200, {"dataStoreEntries": [{"path": f"universes/{ns.UNIVERSE}/data-stores/{ns.STORE}/scopes/global/entries/{u}"} for u in self.queue]})
        uid = url.rstrip("/").rsplit("/", 1)[-1] if "/entries/" in url else url.split("/users/")[1].split("/")[0]
        if uid in self.boom:
            raise requests.ConnectionError("net down")
        if method == "GET" and f"/data-stores/{ns.PROFILE_STORE}/" in url:
            return Resp(200, {"value": {"Data": {"lastSeen": self.profiles[uid]}}}) if uid in self.profiles else Resp(404, {})
        if method == "GET":
            return Resp(200, {"value": self.queue[uid]}) if uid in self.queue else Resp(404, {})
        if method == "POST":
            self.posts.append((uid, kw.get("json")))
            code, body = self.post_reply.get(uid, (200, {"id": "x"}))
            return Resp(code, body)
        if method == "DELETE":
            self.deletes.append(uid)
            if uid in self.delete_fail:
                return Resp(500, {})
            self.queue.pop(uid, None)
            return Resp(200, {})
        raise AssertionError(method + " " + url)


passed = failed = 0


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL", name, detail)


def run(fake, dry=False):
    tmp = tempfile.mkdtemp()
    ns.LOG_DIR, ns.CACHE = tmp, os.path.join(tmp, "cache.json")
    ns.MESSAGE_ID, ns.KEY_FILE = "msg-1", os.path.join(tmp, "key")
    open(ns.KEY_FILE, "w").write(KEY)
    ns.requests.Session = lambda: fake
    ns.time.sleep = lambda *_: None
    sys.argv = ["notify_send.py"] + (["--dry"] if dry else [])
    ns.main()
    logs = []
    for f in os.listdir(tmp):
        if f.endswith(".jsonl"):
            logs += [json.loads(l) for l in open(os.path.join(tmp, f))]
    cache = json.load(open(ns.CACHE)) if os.path.exists(ns.CACHE) else None
    return logs, cache, tmp


def entry(due_off, left_off=-3600, day=2):
    return {"due": NOW + due_off, "left": NOW + left_off, "day": day, "gift": "a Cliffs egg", "dragon": "Ember"}


f = Fake(None)
logs, _, _ = run(f)
check("an empty storage (404) - a summary, no sends", logs and logs[-1].get("summary", {}).get("queue") == 0 and not f.posts)

f = Fake({"1": entry(3600)})
logs, cache, tmp = run(f)
check("the due time not reached - not sent, in the cache", not f.posts and cache.get("1", {}).get("due") and not f.deletes)
f2 = Fake({"1": entry(3600)})
f2_get = []
orig = f2.request
def counting(method, url, **kw):
    if method == "GET" and "/entries/1" in url:
        f2_get.append(url)
    return orig(method, url, **kw)
f2.request = counting
tmp2 = tempfile.mkdtemp()  # the second hour: the same cache, a new log folder
json.dump(cache, open(os.path.join(tmp2, "cache.json"), "w"))
ns.LOG_DIR, ns.CACHE = tmp2, os.path.join(tmp2, "cache.json")
ns.requests.Session = lambda: f2
sys.argv = ["notify_send.py"]
ns.main()
check("the second hour: the entry from the cache is not re-read", not f2_get, str(f2_get))

f = Fake({"1": entry(-60)})
logs, cache, _ = run(f)
body = f.posts[0][1] if f.posts else {}
check("the due time reached - a send and a deletion", f.posts and f.deletes == ["1"] and "1" not in (cache or {}))
check("the body: snake_case, the parameters as strings", body.get("payload", {}).get("message_id") == "msg-1" and body["payload"]["parameters"]["day"] == {"string_value": "2"}
      and body.get("join_experience", {}).get("launch_data") == "src=notify&k=day")

f = Fake({"1": entry(-60)}, post_reply={"1": (400, {"code": "FAILED_PRECONDITION", "message": "User 1 is not opted in to receive notifications"})})
logs, _, _ = run(f)
check("not opted in - delete", f.deletes == ["1"] and any(l.get("outcome") == "not_opted" for l in logs))

f = Fake({"1": entry(-60)}, post_reply={"1": (429, {"message": "throttled"})})
logs, cache, _ = run(f)
check("throttling - the entry stays", not f.deletes and "1" in cache)

f = Fake({"1": entry(-60)}, post_reply={"1": (503, {"message": "unavailable"})})
logs, cache, _ = run(f)
check("5xx - the entry stays", not f.deletes and "1" in cache)

f = Fake({"1": entry(-60, left_off=-3600)}, profiles={"1": NOW - 100})
logs, _, _ = run(f)
check("the player came in after the leave - delete without sending", not f.posts and f.deletes == ["1"])

f = Fake({"1": entry(-60, left_off=-3600)}, profiles={"1": NOW - 3600})
run(f)
check("lastSeen = the leave - a send", len(f.posts) == 1)

f = Fake({"1": entry(-60, left_off=-80 * 3600)})
run(f)
check("older than 72 h - delete without sending", not f.posts and f.deletes == ["1"])

f = Fake({"1": entry(-60)}, delete_fail={"1"})
logs, _, _ = run(f)
check("a deletion failure - in the log", any(l.get("outcome") == "delete_failed" for l in logs))

f = Fake({"1": entry(-60), "2": entry(-60)}, boom={"1"})
logs, _, _ = run(f)
check("a network failure on one entry - the second is sent, the summary exists", [p[0] for p in f.posts] == ["2"] and logs[-1].get("summary", {}).get("error") == 1)

f = Fake({"1": entry(-60)}, post_reply={"1": (400, f"bad request {KEY}")})
logs, _, tmp = run(f)
raw = "".join(open(os.path.join(tmp, x)).read() for x in os.listdir(tmp) if x.endswith(".jsonl"))
check("the key does not get into the log", KEY not in raw and "<key>" in raw)

f = Fake({"1": entry(-60)})
logs, _, _ = run(f, dry=True)
check("--dry: sends and deletes nothing", not f.posts and not f.deletes)

print(f"notify_send_test: {passed} ok, {failed} fail")
sys.exit(1 if failed else 0)
