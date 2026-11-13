--!strict
-- The names of the remote calls, their type, the argument schemas and the limits (10 §4). The server creates the objects in ReplicatedStorage/Remotes,
-- the client waits for them to appear. Money, rarities, timers never come from the client.

local Remotes = {}

export type Def = { kind: string, args: { any }?, limit: number? } -- limit: calls per second (Config.RateLimit)

Remotes.Folder = "Remotes"

Remotes.List = {
	-- the server -> the client
	State = { kind = "RemoteEvent" }, -- the player data keys on change; a full snapshot at the entry
	Notice = { kind = "RemoteEvent" }, -- scenes, banners, the server feed
	-- the client -> the server (RemoteFunction: the reply { ok, reason?, ... })
	PickEgg = { kind = "RemoteFunction", args = { { name = "pointId", type = "string", max = 16 } } },
	PlaceEgg = { kind = "RemoteFunction", args = { { name = "slot", type = "integer", min = 1, max = 3 } } },
	HatchReady = { kind = "RemoteFunction", args = { { name = "slot", type = "integer", min = 1, max = 3 } } },
	Feed = { kind = "RemoteFunction", args = { { name = "uid", type = "string", max = 12 } } }, -- uid or "all"
	SetCompanion = { kind = "RemoteFunction", args = { { name = "uid", type = "string", max = 12 } } },
	MoveDragon = { kind = "RemoteFunction", args = { { name = "uid", type = "string", max = 12 }, { name = "to", type = "enum", values = { "nest", "sanctuary" } } } },
	Release = { kind = "RemoteFunction", args = { { name = "uid", type = "string", max = 12 }, { name = "confirm", type = "boolean" } } },
	NameDragon = { kind = "RemoteFunction", args = { { name = "uid", type = "string", max = 12 }, { name = "text", type = "string", max = 20 } } },
	Buy = { kind = "RemoteFunction", args = { { name = "key", type = "string", max = 32 } } }, -- for coins
	Claim = { kind = "RemoteFunction", args = { { name = "kind", type = "enum", values = { "daily", "timeGift", "calendar", "season", "freeGift", "index", "away", "keeper" } }, { name = "id", type = "string", max = 32, optional = true } } },
	Ascend = { kind = "RemoteFunction", args = {} },
	-- 1.9: a RemoteFunction instead of the RemoteEvent of 10 §4 - the client needs the reply (too_far / needs_juvenile), like Feed
	Mount = { kind = "RemoteFunction", args = { { name = "uid", type = "string", max = 12 } } },
	Dismount = { kind = "RemoteFunction", args = {} },
	Shore = { kind = "RemoteFunction", args = {} }, -- "Back to shore" from the water - a teleport to the nearest shore
	-- the companion is stuck (why: far - ran into something on the way, high - lay on the edge); the spot and the move are decided by the server (Movement.regroup)
	-- vx, vz - the camera gaze along the ground (the spot is placed to the side of it, not toward the camera)
	Regroup = { kind = "RemoteFunction", args = { { name = "why", type = "enum", values = { "far", "high" } }, { name = "vx", type = "number", min = -1, max = 1, optional = true }, { name = "vz", type = "number", min = -1, max = 1, optional = true } } },
	FlightInput = { kind = "UnreliableRemoteEvent", args = { { name = "x", type = "number", min = -1, max = 1 }, { name = "y", type = "number", min = -1, max = 1 }, { name = "z", type = "number", min = -1, max = 1 } } },
	-- 2.1: sku = the SKU key or the class "HatchNow"/"GrowNow" (the step is computed by the server by the target's remainder); giftTo = the recipient's UserId
	-- on this server (the item Gift_<sku>); pick = the target ("1".."3" a slot, a dragon uid) or the Starter Pack elements ("ember,frost")
	ShopIntent = { kind = "RemoteFunction", args = { { name = "sku", type = "string", max = 32 }, { name = "giftTo", type = "integer", min = 1, optional = true }, { name = "pick", type = "string", max = 32, optional = true } } },
	Treat = { kind = "RemoteFunction", args = { { name = "uid", type = "string", max = 12 } } }, -- 2.1: a treat from the stock (07 §2 no. 8)
	Analytics = { kind = "RemoteEvent", args = { { name = "name", type = "enum", values = { "device", "load", "shop_open", "offer_impression", "ui", "invite", "invite_shown", "rsvp_prompt", "rsvp_going", "fav_prompt", "fav_done" } }, { name = "fields", type = "table", optional = true } } },
	Admin = { kind = "RemoteFunction", args = { { name = "cmd", type = "string", max = 64 } } },
	-- warming the golden egg on the stand with coins - an hour off the timer for a price from the pen income (Services/GlowEgg.warm)
	GlowWarm = { kind = "RemoteFunction", args = {} },
	-- the admin client measurement (the mean and worst FPS over the window, memory MB, dragons in the world, the screen); the server accepts only from admins
	Perf = { kind = "RemoteEvent", args = { { name = "fps", type = "number", min = 0, max = 1000 }, { name = "low", type = "number", min = 0, max = 1000 }, { name = "mem", type = "number", min = 0, max = 100000 }, { name = "dragons", type = "integer", min = 0, max = 10000 }, { name = "screen", type = "string", max = 24 }, { name = "detail", type = "string", max = 160, optional = true } } },
	-- two visible buttons on top of each other longer than hold s -
	-- the pair names, the screen, the device (Controllers/Declutter -> Services/Analytics, the DataStore UiOverlap_v1)
	UiOverlap = { kind = "RemoteEvent", args = { { name = "a", type = "string", max = 60 }, { name = "b", type = "string", max = 60 }, { name = "screen", type = "string", max = 24 }, { name = "dev", type = "enum", values = { "touch", "pc", "console" } } } },
	-- P37: a player setting in the profile (settings); the keys - only from the list
	Setting = { kind = "RemoteFunction", args = { { name = "key", type = "enum", values = { "otherDragons" } }, { name = "on", type = "boolean" } } },
	-- 2.4: "there was input" (a touch, a key, a button) - the gifts for time run only without AFK; no arguments, not more often than activeEvery
	Active = { kind = "RemoteEvent", args = {} },
	-- the appearance (07 add. 2.6): kind = "preset" - a preset id or "none" (take off) for dragon uid; kind = "nestSkin" - a skin id,
	-- "auto" (by priority) or "classic" (the ordinary look). The ownership, the element and the existence of the id are checked by the server (Core/Looks)
	-- 2.9 (09 §1): the code of the week from Settings -> Code (the case and spaces do not matter; the window and "once" are checked by the server, Core/LiveOps)
	Code = { kind = "RemoteFunction", args = { { name = "code", type = "string", max = 20 } } },
	-- a breath hit on enemy id (the client -> the server; the checks and the damage - Services/Combat); CombatFx - flashes, damage numbers
	-- clearing, the guard pulse (the server -> the clients)
	Breath = { kind = "RemoteEvent", args = { { name = "id", type = "string", max = 16 } } },
	CombatFx = { kind = "RemoteEvent" },
	-- the client has a menu open or a scene running (the HUD is hidden) - the combat ambushes wait (faking only delays one's own ambush)
	UiBusy = { kind = "RemoteEvent", args = { { name = "busy", type = "boolean" } } },
	SetLook = { kind = "RemoteFunction", args = { { name = "kind", type = "enum", values = { "preset", "nestSkin" } }, { name = "id", type = "string", max = 16 }, { name = "uid", type = "string", max = 12, optional = true } } },
}

-- The refusal codes (shared by the server and the client; the texts - Strings.Errors)
Remotes.Reasons = {
	"loading", "bad_request", "too_fast", "not_enough", "nest_full", "sanctuary_full", "no_dragon", "no_egg", "too_far",
	"already", "already_fed", "elder", "companion", "not_in_nest", "not_ready", "bad_name", "locked", "no_slot", "needs_adult",
	"needs_elder", "needs_elements", "forbidden", "needs_juvenile", "not_companion", "riding", "over_water", "no_shore",
	"owned", "no_target", "no_player", "region", "no_treats", -- 2.1 the shop
	"not_owned", "wrong_element", -- the appearance
	"bad_code", "expired", -- 2.9 the codes of the week
	"name_cooldown", -- a dragon name not more often than once per Config.Names.renameCooldown s
}

return Remotes
