--!strict
-- The numbers of the game "Dragon Nest: Hatch & Fly" (spec 1.1): the balance (05 §12), the heroes (03), the world (04), the shop (07)
-- the limits (10). The balance mirror - balance_sim.py (kept with the design docs outside the repo); change together, tests/balance_spec.luau compares.
-- No Roblox API: the file is read by the luau CLI in tests. Colors - tables {r, g, b} 0-255. Lists and texts - in Content and Strings.

local Config = {}

Config.GameVersion = "dragon-nest-0.1"
Config.ProfileStoreName = "Profile_v2" -- change the name only with a migration (engine 0.5 lived in PlayerData_v1, another game)
Config.SchemaVersion = 2
Config.MaxPlayers = 6
Config.AdminUserIds = { 11774991821 } :: { number } -- the game belongs to the Lanternfox Studios group (CreatorType Group) - admins by this list (UserIds)
-- admin commands (Settings and the Admin chat line: bots N, time +N, give N, give egg [zone]); enabled =
-- false switches everything off in production except Studio. Bots - load for measuring FPS on a phone (6 nests x 3-5 dragons): free
-- nests with dragons and a rider on an adult circling above the island. perf - measures the admin client FPS every perf.every s (the journal
-- PerfLog_v1, read with cloud_test.py perflog_read)
Config.Admin = {
	enabled = true,
	resetHold = 3, -- Reset in Settings - only by holding this many seconds
	-- auto - on a quiet server (live players <= maxPlayers) count rider bots appear by themselves, so a newcomer does not join an empty place (they take the last plots,
	-- the dragons in the pen, the rider circles in the sky), one per check; it got crowded - they leave one at a time; the admin command "bots N"
	-- switches auto off on this server; in Studio auto is off (studio). names - names instead of "Bot N" (NPCs, not players:
	-- they are not in the player list, no chat). walkers - walkers on the plaza (Services/Crowd): R15 without an outfit, a name above the head, a route by
	-- the plaza points (the stall, the board, the circle at the Keeper, the ledge), pauses of pause s; the stock Roblox animations (anims)
	auto = { on = true, maxPlayers = 2, count = 3, checkEvery = 12, studio = false },
	names = { "Rowan", "Lark", "Wren", "Moss", "Pip", "Fen", "Juniper", "Sorrel" },
	-- the look of the walkers and
	-- the riders - real avatars by UserId (Players:GetHumanoidDescriptionFromUserId): the seed avatarSeed ("Roblox" 1 and
	-- "Games" 21557 - dressed R15) + optionally recent live players of this place (a session >= 2 min, the DataStore
	-- CrowdAvatars, up to 40). The names stay NPC (names), the players' nicknames are not taken.
	-- The game owner and the recent players are not in the pool (avatarRecent = false), only the official Roblox accounts + outfits from the catalog
	avatarSeed = { 1, 21557 },
	avatarRecent = false,
	-- a bot does not take an avatar already worn by another bot
	-- (the AvatarKey attribute on the models in workspace.Crowd / Bots); not enough real avatars - a random outfit from the free items
	-- of the Roblox catalog (catalog.roblox.com, seller Roblox, price 0):
	-- a shirt + pants + hair + a skin color + a height of 0.95-1.05; the combination does not repeat ones already worn
	avatarParts = { shirts = { 607785314, 398633584, 3670737444, 398635081, 398634295, 144076358, 382538059, 4047884939, 4047884046, 4047886060, 144076436, 382538295, 382537085, 382537702 }, pants = { 398633812, 398634487, 398635338, 144076760, 382537950, 382538503, 382537569, 382537806 }, hair = {  }, hats = { 607702162, 617605556, 417457461, 4819740796, 607700713, 2646473721, 1772336109, 48474313, 3403874988, 4047554959, 3033910400, 3438342658, 4391384843, 3033908130, 4094878701, 3409612660, 3992084515, 3822880197, 3940375351, 3656493304, 3662265036, 3398308134, 4381707497, 4489239608 }, -- the catalog gave free caps/hoods/visors (type 8), there is no free hair (41)
		skins = { { 234, 184, 146 }, { 196, 140, 100 }, { 120, 80, 60 }, { 245, 205, 170 }, { 160, 110, 80 }, { 90, 60, 45 } } },
	walkers = { on = true, count = 2, speed = 11, pause = { 2, 6 }, moveTimeout = 8, ring = { 30, 42 }, anims = { idle = 507766666, walk = 507777826 } }, -- stuck for 8 s (was 12) - a relocation
	-- the DEMO RAID, so the players see what to do: a copy of the Gloom nest (like ring 0, r as in Raid.rings[1].spots.r) in a free odd wedge nearest to the spawn
	-- point; a sleeping guard (a Combat pack, key "demo:1"); every every s, if a live player is closer than seeR: a walker comes up, sneaks (sneak
	-- studs/s), grabs the egg (the egg in the nest is shown eggBefore s before that), "!", after wake s the guard chases (share of the run speed run)
	-- to the nearest foreign gate, the bot runs in, the guard stops at the line for hold s and goes back to sleep; the egg disappears. Between scenes the nest is empty -
	-- nothing to take in it (the arrow does not lead there: not a RaidNest)
	demo = { on = true, every = 50, seeR = 120, eggBefore = 3, sneak = 7, run = 16, share = 0.9, wake = 0.9, hold = 0.8, gap = 25, near = 14, pick = 3 },
	bots = { max = 5, dragons = { 3, 5 }, stageWeights = { 0, 20, 50, 30 }, radius = { 90, 290 }, height = { 110, 190 }, speed = { 26, 40 },
		bob = 14, bobSeconds = 18, rider = true, tickHz = 10, pot = 1800 },
	perf = { on = true, every = 15, flush = 60, cap = 400,
		-- :
		-- a census of PlayerGui objects painting the left edge of the screen, the first seconds after the start and moveSeconds after the first move
		census = { seconds = 12, moveSeconds = 3, waitMove = 90, step = 0.2, minW = 0.25, minH = 0.6, maxX = 0.15 },
		-- the "Perf test" experiment (Controllers/Perf): seconds per mode, far - decor beyond this many studs is hidden
		-- base - the decor as before (LOD off), lod - normal, lod2 - strong, lodsh - normal without shadows
		test = { modes = { "base", "lod", "lod2", "lodsh" }, seconds = 61, far = 250 } },
}
Config.AutoSaveSeconds = 120 -- ProfileStore.SetConstant("AUTO_SAVE_PERIOD"), the vendor default is 300 (10 §5)

Config.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
Config.Elements = { "ember", "frost", "moss", "tide", "storm", "dusk" }
Config.Stages = { "Hatchling", "Juvenile", "Adult", "Elder" } -- the stage id 0..3 = the index - 1

-- ---------------------------------------------------------------------------------------------- the balance (05)
Config.Balance = {
	baseIncome = { Common = 1, Uncommon = 4, Rare = 16, Epic = 80, Legendary = 500, Mythic = 4000 }, -- coins/s of a hatchling
	stageMult = { 1, 6, 30, 100 }, -- the index = the stage + 1
	incubateMin = { Common = 3, Uncommon = 6, Rare = 15, Epic = 45, Legendary = 120, Mythic = 360 },
	growMin = { -- [H->J, J->A, A->E] in minutes
		Common = { 4, 10, 120 },
		Uncommon = { 8, 20, 180 },
		Rare = { 15, 40, 240 },
		Epic = { 30, 90, 360 },
		Legendary = { 60, 180, 480 },
		Mythic = { 120, 360, 480 },
	},
	variants = {
		shiny = { p = 0.04, mult = 2 }, -- a separate roll
		huge = { p = 0.01, mult = 5, scale = 1.7 }, -- the size: one roll, Huge is checked first
		big = { p = 0.05, mult = 3, scale = 1.35 },
		stormborn = { mult = 2 }, -- hatched in a storm
		ancient = { p = 0.000001, mult = 10, zones = { "Summit" } }, -- spec 1.2 (03 §4): a separate roll, Summit eggs only
		glacier = { mult = 1.5 }, -- 2.9 (09 §3): Frost from Summit, hatched in an Aurora (Content.Variants)
		pearl = { mult = 1.5 }, -- 2.9 (09 §3): Tide from Springs, hatched in a Starfall (update 3)
	},
	-- the rarity odds by zone, % (the order of Config.Rarities); the sums = 100
	zones = {
		Meadow = { 70, 22.5, 7, 0.45, 0.05, 0 },
		Cliffs = { 45, 33, 17, 4.5, 0.45, 0.05 },
		Springs = { 22, 35, 30, 11, 1.9, 0.1 },
		Summit = { 8, 27, 40, 20, 4.5, 0.5 },
	},
	zoneOrder = { "Meadow", "Cliffs", "Springs", "Summit" },
	summitRareNest = { 3, 27, 40, 20, 9, 1 }, -- a rare nest on Summit: Legendary and Mythic x2, Common squeezed
	rareNestP = 0.10,
	-- the elements: two "home" ones at 30%, the other four at 10%
	homeElements = { Meadow = { "moss", "ember" }, Cliffs = { "storm", "dusk" }, Springs = { "tide", "ember" }, Summit = { "frost", "storm" } },
	homeElementP = 30,
	otherElementP = 10,
	feed = { x = 2, seconds = 300, priceSeconds = 60, priceMin = 50 },
	-- the account's first dragon up to stage untilStage grows by the firstborn timers and
	-- is fed at the growAs price at any rarity; the rarity and the income are its own.
	-- growMin [H->J, J->A] in minutes: 1 / 1 - riding ~2:00 from the entry, flight ~2:15 without feeding.
	-- Flight is the game's hook: players who take off stay much longer, so the adult must come before most sessions end
	firstDragon = { growAs = "Common", untilStage = 2, growMin = { 1, 1 } },
	slots = { start = 3, coins = { 2500, 15000, 60000 }, maxPasses = 3, vipPlus = 1 }, -- slots 4-6 for coins, 7-9 passes, 10 VIP -- 60,000 / 1.5 M -> 15,000 / 60,000 - the raid ladder in the first session (the 4th slot by the 4th minute, the 5th - day 1)
	incubators = { start = 1, coins = { 5000, 60000 } }, -- the third bowl 250,000 -> 60,000
	shelf = { start = 3, plus2 = 10000, max = 5 },
	sanctuary = { start = 25, plus10 = { 20000, 400000, 8000000 } },
	decor = { 500, 2000, 8000, 30000, 100000, 400000, 1.5e6, 6e6, 25e6, 100e6 },
	ascension = { base = 5000, mult = { 50, 50, 20 }, maxSteps = 12, elderFrom = 4, twoElementsFrom = 7, threeElementsFrom = 10, sanctuaryPlus = 5 },
	offline = { share = 0.25, capHours = 8, oneStage = true, minAwaySeconds = 600 },
	potCapMinutes = 60,
	release = { seconds = 120 },
	egg = { warmSeconds = 90, coldMult = 1.5, firstHatchSeconds = 3 },
	fastIncubatorMult = 0.6,
	party = { div = 2, friendDiv = 3 },
	treatShare = 0.5,
	eggPoints = { total = 30, respawn = { 360, 600 } },
	weather = {
		interval = { 600, 1200 },
		duration = 180,
		firstAfterSeconds = 600,
		storm = { p = 60, coinsMult = 2 },
		starfall = { p = 40, respawn = { 60, 120 }, fastSeconds = 180 },
		aurora = { share = 0.3, update = 1 }, -- 2.9 (09 §3): from update 1 - 30% of all weather (the storm and the starfall split the rest 60:40)
	},
	stormDragon = { every = 1800, duration = 180, warnSeconds = 60, shards = 12, reward = { egg = "Cliffs", minutes = 10 },
		-- only players with at least one dragon of stage >= minStage see the event and collect the shards
		-- (an adult); for a newcomer it came at 6:33 before the first adult - the banner, the "Storm shards 0/12" scale, the shards
		minStage = 2,
		-- chapter 2 - from update update: more shards, the reward a Springs egg, a larger dragon (scale)
		chapters = { { update = 3, shards = 16, reward = { egg = "Springs", minutes = 10 }, scale = 1.3 } } },
	friends = { perFriend = 0.10, max = 0.40 },
	index = { total = 36, thresholds = { { 0.25, 0.05 }, { 0.50, 0.10 }, { 0.75, 0.15 }, { 1.00, 0.25 } } },
	vipMult = 1.1,
	x2Mult = 2,
	boostMult = 2,
	daily = { 3, 6, 12 }, -- minutes of income for Easy / Medium / Hard; all three = a Cliffs egg
}

-- ---------------------------------------------------------------------------------------------- the shop (07)
Config.Shop = {
	hatchNowEnabled = true,
	fromSeconds = 180, -- no Robux buttons before 3:00 of the first session
	hatchNow = { steps = { 60, 300, 1200, 3600 }, prices = { 5, 9, 19, 29, 49 }, minRemaining = 30 },
	growNow = { minRemaining = 60 },
	priceCacheSeconds = 300,
	purchasesKeepDays = 30,
	purchaseLogMax = 200,
	-- 2.1: the Core/Shop catalog is built from here (the SKU keys = the names in monetize.py); there are no Robux prices here - the number in the key is only a name
	treats = { packs = { { n = 1, price = 49 }, { n = 3, price = 129 }, { n = 10, price = 399 } } },
	boost = { packs = { { minutes = 30, price = 49 }, { minutes = 120, price = 149 } }, replicateEvery = 15 }, -- the boost seconds run only online
	income = { packs = { { hours = 1, price = 99 }, { hours = 4, price = 299 }, { hours = 24, price = 699 } } }, -- by the current income without the boost
	starter = { eggs = 2, zone = "Cliffs", minRarity = "Rare", fixedRarity = "Rare", incubators = 2, incubatorFallbackCoins = 5000, fromSession = 2, afterRide = true }, -- afterRide - the Starter card in the 1st session too after the first ride (otherwise it shows only after re-entries) -- fixedRarity - a pack without randomness (countries with the ban, ArePaidRandomItemsRestricted; and by default)
	receiptWaitSeconds = 60, -- ProcessReceipt waits for the profile (a session conflict up to 40 s) or the leave
	saveWaitSeconds = 15, -- Granted only after a real save (OnAfterSave)
	passRetrySeconds = 30, -- UserOwnsGamePassAsync failed - a retry
	giftLevelGap = 150, -- a gift is allowed at buyerLevel >= recipientLevel - gap (regional prices)
	anchors = false, -- the anchor price and the timer at the Starter Pack; false = no timers
}

-- ---------------------------------------------------------------------------------------------- the heroes (03)
Config.Dragon = {
	-- the height in studs, the speeds (04 §5)
	stages = {
		{ id = 0, name = "Hatchling", height = 2.5, shoulder = true, speed = 0 },
		{ id = 1, name = "Juvenile", height = 5, ride = true, speed = 28 },
		{ id = 2, name = "Adult", height = 10, ride = true, fly = true, speed = 45 },
		{ id = 3, name = "Elder", height = 14, ride = true, fly = true, speed = 55 },
	},
	shoulderOffset = { 0.9, 1.2, 0 },
	-- the hatchling hatches at the incubator ring, looks at the player for sitSeconds and jumps (an arc of height) onto the shoulder or
	-- onto its stand; you stand still for stillSeconds - it jumps off and fiddles nearby (steps of radius radius every stepEvery s),
	-- you walked faster than moveSpeed, went farther than leaveDistance, jumped or mounted - it jumps back on
	hatchHop = { sitSeconds = 2.4, hopSeconds = 0.5, height = 2.5 },
	play = { stillSeconds = 2.5, radius = 4.5, stepEvery = { 1.0, 2.0 }, stepSeconds = 0.7, stepHeight = 0.6, hopSeconds = 0.45, moveSpeed = 4, leaveDistance = 9 },
	glide = { forward = 40, down = 8, minHeight = 12, lookAhead = 0.35, updraftRise = 18 }, -- lookAhead - the height also where the character flies (at the edge); updraftRise - in the stream the glide rises
	flight = {
		dailyMinSpeed = 4, -- 2.4: the flight seconds for the daily "Fly for 2 minutes" count at a speed above (studs/s)
		ceiling = 220,
		cameraOffset = 8,
		maxZoom = 60,
		-- spec 1.2 (04 §5.1): a dive accelerates up to maxMult x the base; the server check = the base x maxMult x 1.15
		dive = { pitchDeg = 20, accel = 15, maxMult = 2, decaySeconds = 2 },
		maxSpeedCheck = 55 * 2 * 1.15, -- Elder 55 x2 x1.15 = 126.5 studs/s
		fov = { base = 70, max = 85 },
		shakeAbove = 70,
		shakeAmplitude = 0.15,
		landingDust = 20,
		-- 1.9: takeoff - hold Up (Jump) for takeoffHold s; the vertical = a share of the base speed; the nose pitch in flight up to pitchMax
		-- landing - the ground closer than landProbe studs under the belly while descending; acceleration/braking on the ground accel studs/s per s
		takeoffHold = 0.35,
		verticalMult = 0.6,
		pitchMax = 45,
		landProbe = 2.5,
		stuckSeconds = 0.5, -- we ask down, the body stands (ran into something) - landing
		accel = 60,
		turnResponsiveness = 8,
	},
	-- 1.9 (04 §5, 10 §4): mount - the companion within mountDistance; riding on the ground - hovering hoverClearance above the ground;
	-- the server check every checkTick s: a speed above the stage ceiling x checkSlack (flight: flight.maxSpeedCheck) or above
	-- the height ceiling + ceilingSlack - a return to the last honest point; glideSeconds - how much Freefall with a hatchling = "glided"
	ride = { mountDistance = 12, hoverClearance = 0.6, hoverGain = 6, groundSpeedMult = 1, checkTick = 0.25, checkSlack = 1.5, ceilingSlack = 25, glideSeconds = 0.8, flewHeight = 8,
		softMult = 1.5, softMax = 4, -- an excess up to x1.5 cap - braking without a rollback; a rollback at a gross one or 4 in a row
		logAirDismount = true, -- a dismount in the air - a warn with a trace + dismount_air
		-- the minimum: no braking or rollbacks for
		-- speed; a rollback only for an obvious hack: faster than grossMult x cap for grossStreak measurements in a row (0.5 s). softMult / softMax no longer
		-- apply. on = false - no speed check at all (the height ceiling stays the world boundary, a soft push-down)
		anticheat = { on = true, grossMult = 3, grossStreak = 2 },
		-- the camera when riding no closer than zoomMin (by the dragon size, but not less than zoomMinFloor), above the back by
		-- cameraUpOfHeight x the height; the rider's pose (degrees): legs apart and forward, the knees, the arms forward, the torso lean
		zoomMinFloor = 30, zoomMinOfSize = 1.4, cameraUpOfHeight = 0.7,
		-- enabled = false: the 2026 rig has AnimationConstraint joints, a Transform from a script is not visible in the frame (P8 probes cycles 5-7) -
		-- the standard "sitting" for now; the rider's pose - the next session (an animation in the Studio editor on P8 or a Transform analysis)
		pose = { enabled = true, hipSpread = 34, hipForward = 28, knee = 42, armForward = 48, armIn = 8, lean = 12, leanAir = 22, armAir = 14, flapLean = 4, gallopLean = 2.5, gallopMinSpeed = 4 } }, -- flapLean - the torso rocks in time with the flap (the DragonBones rig phase), gallopLean - in time with the step on the ground -- leanAir/armAir: in flight crouch to the neck (the HTTYD clip)
	-- the dragon is "alive" without a skeleton:
	-- breathing with the body (a bob sway of studs x the height / 15, the frequency in Hz), steam from the mouth (the server turns the emitter on for breathSeconds every
	-- breathEvery s), a bank in a turn bankDeg, a "flap" in flight - a vertical sway of flapBob studs at flapHz
	-- the bones (the UniRig rig; Controllers/DragonBones): roles by geometry, motion by code; the angles in degrees
	-- axisX 0.08 -> 0.04 - the front paw fingers of v4b (|x| 0.05-0.06) landed "on the axis" and pulled the head to the root (ember s2); offline 24/24 without losses
	bones = { minBones = 8, retryEvery = 0.5, retryMax = 12, axisX = 0.04, hubX = 0.06, hubDist = 0.25, wingX = 0.18, legY = 0.2, wingTipY = 0.2, flyAbove = 3, breathDeg = 1.5, breathShift = 0.006, lookDistance = 45, yawMax = 55, pitchMax = 28, lookSpeed = 4,
		idleYawDeg = 12, tailDeg = 9, tailHz = 0.45, tailFlyDeg = 10, wingIdleDeg = 3.5, wingIdleHz = 0.35, wingFlapDeg = 30, wingLag = 0.08, wingGain = 0.35, wingDown = 0.4, wingSweepDeg = 6, wingDepthMax = 4, legTuckDeg = 35, stepHz = 1.6, stepDeg = 18 },
	life = { bob = 0.14, bobHz = 0.42, pitchDeg = 1.4, breathSeconds = 0.7, breathEvery = { 5, 9 }, bankDeg = 38, bankGain = 1.2, flapBob = 2.2, flapHz = 0.8, viewDistance = 160,
		sprayAbove = 8, sprayRate = 70 }, -- spray under the dragon below sprayAbove studs above the water (HTTYD, craft/04 §7.10 series 17)
	-- 1.6 (03 §1.2, §7): the attachments as shares of the model extents after scaling: x - the share of the width from the center, y - the share of the height
	-- from the sole, z - the share of the length from the center (the snout at -Z). The index = the stage. Checked by eye in Studio, the numbers are tuned here.
	attach = {
		[0] = { EyeL = { -0.17, 0.62, -0.40 }, EyeR = { 0.17, 0.62, -0.40 }, Mouth = { 0, 0.48, -0.5 }, Shoulder = { 0, 0, 0 }, Crest = { 0, 0.98, -0.25 }, Back = { 0, 0.9, 0.1 }, TailTip = { 0, 0.25, 0.48 }, WingL = { -0.3, 0.75, 0.15 }, WingR = { 0.3, 0.75, 0.15 } },
		[1] = { EyeL = { -0.15, 0.70, -0.42 }, EyeR = { 0.15, 0.70, -0.42 }, Mouth = { 0, 0.74, -0.47 }, Saddle = { 0, 0.66, -0.06 }, Crest = { 0, 0.98, -0.28 }, Back = { 0, 0.9, 0.08 }, TailTip = { 0, 0.3, 0.48 }, WingL = { -0.35, 0.75, 0.1 }, WingR = { 0.35, 0.75, 0.1 } },
		[2] = { EyeL = { -0.08, 0.78, -0.40 }, EyeR = { 0.08, 0.78, -0.40 }, Mouth = { 0, 0.84, -0.46 }, Saddle = { 0, 0.64, -0.08 }, Crest = { 0, 0.99, -0.3 }, Back = { 0, 0.92, 0.05 }, TailTip = { 0, 0.3, 0.47 }, WingL = { -0.36, 0.72, 0.05 }, WingR = { 0.36, 0.72, 0.05 } },
		[3] = { EyeL = { -0.08, 0.78, -0.40 }, EyeR = { 0.08, 0.78, -0.40 }, Mouth = { 0, 0.84, -0.46 }, Saddle = { 0, 0.64, -0.08 }, Crest = { 0, 0.99, -0.3 }, Back = { 0, 0.92, 0.05 }, TailTip = { 0, 0.3, 0.47 }, WingL = { -0.36, 0.72, 0.05 }, WingR = { 0.36, 0.72, 0.05 } },
	},
	eyes = { enabled = false, sizeOfLength = 0.05 }, -- Neon balls in EyeL/EyeR; the eyes are in the model texture - off
	overlays = false, -- overlay element signs (spec 1.2 P3) from parts until own meshes; the signs are in the model itself
	flatColorStages = {} :: { [number]: boolean }, -- all elements have their own textures; the flat body color is no longer needed (kept in case of a rollback)
	labelDistance = 45, -- the labels of neighboring nests overlapped; was 70
	walkSpeed = 16,
	-- footClearance - the gap of the companion's body bottom above the ground at rest (the leash target
	-- is computed for the center of mass, Controllers/Companion.follow; the Movement.spawnCFrame construction - the extents bottom at the same height);
	-- footSpread - the share of the body size for the four side rays to the ground (the paws do not sink into the plaza slabs and the steps); footStep - how much
	-- the side rays may raise the support above the center ray (the slab step ~0.45; a rock or a trunk at the side does not lift the dragon by 5 studs)
	leash = { distance = 7, flyUp = 6, responsiveness = 10, maxVelocity = 45, turn = 6, labelHideDistance = 12, footClearance = 0.2, footSpread = 0.35, footStep = 1.0 }, -- the companion on foot - AlignPosition/AlignOrientation, the target is set by the owner client
	lod = { effectsOff = 120, hideBeyond = 300, othersKeep = 40, othersEvery = 0.5 }, -- P37: "Show other riders' dragons" off - others' dragons farther than othersKeep studs hide on their own client
	maxOnServer = 66, -- 60 in the nests + 6 companions
	trianglesMax = 3500,
	nameMaxLength = 20,
}
-- standing on a solid dragon is not allowed - the client pushes
-- its own character away from the dragon center (push studs/s sideways, lift upward, a check every every s); no passing through, as before
Config.Dragon.noStand = { push = 26, lift = 10, every = 0.2 }
-- the spot for a new companion
-- (a teen and older) - a free one. The candidates: the previous spot, then the rings reach (studs to leash.distance + 0.4 of the length), in each
-- of the directions dirs (degrees from the character's gaze, 90 - to the right; in front of the face - last, not to block Old Ash): the nearest
-- free one wins - the elder stays within the Fly button radius (a simulation: step 6 at the left edge of the slab took it 24 studs away, there was
-- no button). The first ray from above must hit the ground not higher or lower than the feet by more than step (the sign board is not ground), the model extents
-- (the width and the length * shrink, the bottom raised by lift) - without solid parts and without visible ones taller than tallPart
-- level - a free spot is also flat: four rays at leash.footSpread
-- of the size (solid only, like the leash support) hit the ground no farther than level from the center ray
Config.Dragon.spawnSpot = { dirs = { 90, -90, 120, -120, 150, -150, 180, 60, -60 }, reach = { 0, 2, 4, 6, 8, 10, 12 }, step = 4, shrink = 0.85, lift = 1.5, tallPart = 1.5, level = 1.0 }
-- the companion's solid body cannot always reach the leash target - it runs into
-- an obstacle on the way (the leash does not go around them; the center of mass stopped at 26.6 instead of 20.5) or lies belly-down on the terrace edge (the bottom at 4-5.7
-- above the support). The client (Controllers/Companion) considers it "stuck": beyond the leash farther than margin and over seconds advanced toward the target less than move,
-- or stands (within the leash) and hangs above the target higher than lift for all seconds; then a Regroup call not more often than cooldown. The server (Movement.regroup) takes
-- a free flat spot as at the entry (spawnSpot, to the side of the player - not in the camera) and carries it in an arc of hopSeconds with height hopHeight of
-- the body height (not lower than hopMin); no spot - the dragon stays, the client retries after cooldown
-- dirs - the sides of the new spot in degrees from the CAMERA gaze (the client sends it with the call; 90 - to the right, 0 - ahead beyond the player); toward
-- the camera (120-180) we do not place: a spot to the right of the character with the camera on the right put the camera inside the dragon
Config.Dragon.regroup = { margin = 4, seconds = 1.5, move = 1.5, lift = 1.5, cooldown = 4.5, serverCooldown = 4, hopSeconds = 0.8, hopHeight = 0.5, hopMin = 3, dirs = { 90, -90, 60, -60, 30, -30, 0 } }

-- ---------------------------------------------------------------------------------------------- the Keeper's errands (06 §1; 1.10)
-- the Old Ash bubble = bubblePx pixels + bubbleStuds studs (readable from afar, grows up close, but not 250x76 px
-- at any distance as before), visible up to bubbleDistance; the name - inside the bubble. P8: studs only 12x4.2 - unreadable at 15-25 studs
-- the veterans' spare eggs are KEPT for now (complaints cost more than invisible inequality) - spareEggsToCoins = false; the exchange by rarity
-- (spareEggCoins) is enabled by the flag, the code in PlayerData.convertSpareEggs
Config.Quests = { bubbleStuds = { 6, 2 }, bubblePx = { 120, 38 }, minMinutesReward = 100, eggFallbackCoins = 300, spareEggsToCoins = false, spareEggCoins = { Common = 300, Uncommon = 600, Rare = 1500, Epic = 3000, Legendary = 5000, Mythic = 10000 }, chainDelay = 1.4, bubbleDistance = 60, panelY = 0.28 } -- minMinutesReward: the floor of the "minutes of income" reward; eggFallbackCoins: the shelf is full - coins instead of an egg; panelY: P33 - in place of Settings (it went into the Roblox row); at 0.41 on a phone 812x375 the plate touched the timer at the jump (P35)
-- the Keeper's line - a callout on the screen in px: the width, the font of the line and the name, the background transparency
Config.Quests.says = { width = 230, text = 13, name = 15, back = 0.15 }

-- ---------------------------------------------------------------------------------------------- rewards 2.4 (06 §2-4, §6, §8)
-- Daily (§2): one task each from easy/medium/hard per UTC date (Core/Rewards.dailyPicks), the reward - minutes of income (Balance.daily) +
-- a season point, all three - the egg bonusEgg + a point; off = the event is not built yet (the shards - 2.7, Hatch Party - 2.6), not in the pool.
-- The events: the day counters from Quest.event (eggFound, feed, hatch, eggInc_<Zone>) and own ones (visit, playSec, flySec, grow, ring, hatchRare).
-- 2.9 (09 §3): pool B - tasks with from = a UTC date (the day after update 1 Aurora, Content.Updates[1].dailyFrom), they enter the pool from this date;
-- hatchWeather - a hatch in any weather (Incubation)
Config.Rewards = {
	daily = {
		bonusEgg = "Cliffs",
		points = 1, -- season points for every task and for all three
		showAfter = 480, -- 02 §3 8:00: the first session - a toast about the dailies after the 8th minute
		visitEvery = 2, -- s: the "visited a foreign nest" check
		pool = {
			easy = { { id = "eggs3", event = "eggFound", count = 3 }, { id = "feed3", event = "feed", count = 3 }, { id = "visit2", event = "visit", count = 2 }, { id = "play10", event = "playSec", count = 600 },
				{ id = "eggs5", event = "eggFound", count = 5, from = "2026-11-09" }, { id = "feed5", event = "feed", count = 5, from = "2026-11-09" } },
			medium = { { id = "hatch2", event = "hatch", count = 2 }, { id = "fly2", event = "flySec", count = 120 }, { id = "cliffsEgg", event = "eggInc_Cliffs", count = 1 }, { id = "grow1", event = "grow", count = 1 }, { id = "rings5", event = "ring", count = 5 },
				{ id = "springsEgg", event = "eggInc_Springs", count = 1, from = "2026-11-09" }, { id = "shards3", event = "shard", count = 3, from = "2026-11-09" }, { id = "weatherHatch", event = "hatchWeather", count = 1, from = "2026-11-09" } },
			hard = { { id = "hatchRare", event = "hatchRare", count = 1 }, { id = "summitEgg", event = "eggInc_Summit", count = 1 }, { id = "shards6", event = "shard", count = 6 }, { id = "party1", event = "party", count = 1 },
				{ id = "hatch4", event = "hatch", count = 4, from = "2026-11-09" }, { id = "rings15", event = "ring", count = 15, from = "2026-11-09" } }, -- the shards (2.7) and Hatch Party (2.6) are built
		},
	},
	-- the gifts for time (§3): a session minute without AFK (afkSeconds without input - the time stands) -> a reward; claim by a button, per session
	timeGifts = {
		afkSeconds = 300,
		activeEvery = 20, -- s: the client sends "there was input" not more often
		moveStuds = 3, -- a character shift per tick also counts as input
		list = {
			{ min = 5, minutes = 3 }, { min = 10, minutes = 5 }, { min = 15, berries = 2 }, { min = 20, minutes = 8 },
			{ min = 30, egg = "Cliffs" }, { min = 45, minutes = 10 }, { min = 60, egg = "Springs" }, { min = 90, rareNest = true },
		},
	},
	-- the calendar (§4): the day counts at the first entry in a UTC day, a skip does not take away; 8-13 like 1-6, 14 - day14, then the cycle 1-7
	-- a Cliffs egg on the 2nd day (a reason to come back
	-- tomorrow), berries on the 3rd
	calendar = {
		days = { { minutes = 10 }, { egg = "Cliffs" }, { berries = 3 }, { minutes = 20 }, { decor = "Lantern" }, { egg = "Springs" }, { hatchling = "Rare" } },
		day14 = { egg = "Summit", minRarity = "Epic" },
		choices = 3, -- elements to choose from for the Rare hatchling of day 7
		-- the 2nd day - a Rare dragon of the element from the UserId instead of a Cliffs egg. In the evening
		-- "no experiments, a valuable reward on the second day right away" - force = "B" (a dragon to everyone); remove force - the split again
		-- by the third bit of the UserId, on = false - an egg to everyone. The Analytics slice: d2=A/B
		d2ab = { on = true, rarity = "Rare", force = "B" },
	},
	-- the tasks of the week x2 from Content.Updates[live].weekly - the week
	-- Sun 19:00 - Sun 19:00 UTC (anchor = 1970-01-04 19:00 UTC), they switch on by themselves with update 1, on = false - off entirely;
	-- points - season points for each (while the track is open), the egg of the set's zone - onto the shelf
	weekly = { on = true, points = 5, anchor = 327600, toastDelay = 10 },
	-- "tomorrow" in the first minutes: after the first dismount
	-- from the dragon (not earlier than minSession s) or at afterSeconds of the session - whichever is earlier; waits until nothing is open and the "favorite" window
	-- with the goal banner have played out (quietFor s); first claims the calendar day without a choice (otherwise many newcomers never claim day 1, and
	-- day 2 never comes), after claimGap s - the banner "Tomorrow, Day n" (via the reward queue), then the Roblox "notifications" window.
	-- maxWait - s of waiting for quiet, then the chain gives up (tomorrow/stuck); claimWait - s beyond which the day claim does not wait for quiet;
	-- promptHold - s after which the consent window is considered closed if Roblox did not send OptInPromptClosed (UiBusy is lifted).
	-- afterSeconds 120 - the chain without a flight ends before the Free Gift card (showAt 165); the hatch scene,
	-- the Free Gift card (quietFor s after it appears) and the consent window are "noisy" too. returnAfter - s after the entry when the chain starts
	-- for a returning player (sessions > 1): the day gift at the entry, after the "while you were away" card
	tomorrowBanner = { afterSeconds = 120, returnAfter = 6, minSession = 40, quietFor = 7, claimWait = 60, claimGap = 3.2, seconds = 5, promptGap = 1.5, maxWait = 600, promptHold = 20 },
	-- Free Gift (§6): joining the group -> an egg of element element by the zone table not lower than minRarity, once; groupId = 0 - off
	-- ; showAt - the card at this second of the first session (02 §3 2:45)
	freeGift = { groupId = 76414869, zone = "Cliffs", element = "moss", minRarity = "Uncommon", showAt = 165 },
	berryFallbackMinutes = 2, -- nobody to feed - minutes of income for a berry
	-- 06 §8 Season 1: a free track, points only for the dailies (1-4 per day), claim of every step by a button; banner - a nest decoration
	-- (the Decor2 support), preset - a color preset (only on Dusk, applied by the appearance system), dragon - a fixed hatchling with a name
	season = {
		endsAt = 1796410800, -- 09 §5: 2026-12-04 19:00 UTC - the track closes, unclaimed steps are not granted, points do not accumulate
		steps = { 4, 8, 14, 22, 32, 44, 56, 68, 80, 92 },
		rewards = {
			{ minutes = 15 }, { berries = 3 }, { egg = "Cliffs" }, { decor = "Banner" }, { minutes = 30 },
			{ egg = "Springs" }, { preset = "solstice" }, { minutes = 60 }, { egg = "Summit" },
			{ hatchling = "Legendary", element = "dusk", name = "Solstice" },
		},
		banner = { color = { 70, 60, 150 }, trim = { 242, 201, 76 }, height = 7 },
	},
	-- the gift chest at the nest (the nest's local coordinates, like nestLayout); for the owner a timer above it, a touch - the Gifts tab
	chest = { pos = { 24, 0, -50 }, yaw = -90, size = { 3.2, 2.2, 2.2 }, promptDistance = 10, labelDistance = 16 }, -- labelDistance: at 45 a second 🎁 timer on the screen next to the bar pill
}

-- ---------------------------------------------------------------------------------------------- the social layer 2.6 (08)
-- partyRadius/partyHold: a foreign player at a warming egg (studs, seconds); partyMinLeft: do not hold one if less is left to readiness;
-- board: the Top nests board at Old Ash (the world position, width x height, the lift above the ground); inviteAt: the invite card in the first session
Config.Social = { partyRadius = 4, partyHold = 1, partyMinLeft = 5, partyTick = 0.25, partyParticles = 30, partySeconds = 3, rareParticles = 12,
	boardEvery = 30, boardRows = 6, inviteAt = 450, inviteCardSeconds = 25,
	board = { pos = { -16, 18, -22 }, size = { 8, 5 }, lift = 2.5, maxDistance = 90 } }
-- a friend came by an invite (LaunchData party:<UserId> or ReferredByPlayerId), the Roblox account not younger than minAccountDays
-- and minActiveSec in the game without AFK (GiftSec, accumulated over sessions) -> an egg base to both; the friend has a Roblox subscription (Premium), IsVerified() or
-- passed the age check (AgeChecked) -> top to both. To the friend - once for all time (once per pair and no farming with one account through
-- many inviters); to the inviter - not more than perDay per UTC day, the counter and the queue (not more than pendingCap) in the DataStore store: he
-- could have left the server - the egg waits for his entry. The egg - onto the shelf bypassing the "one-dragon day", the hatch like the raid eggs (Raid.hatchSeconds)
Config.Social.invite = { on = true, minAccountDays = 60, minActiveSec = 600, perDay = 5, base = "Epic", top = "Legendary", zone = "Cliffs",
	tick = 5, store = "InviteGift_v1", pendingCap = 10, ownerTest = 0 }

-- ---------------------------------------------------------------------------------------------- the weather and the Storm dragon 2.7 (04 §7-8)
-- the look (the balance - Balance.weather / stormDragon): rain at the camera, the storm darkening, flashes (the interval, s), the starfall stars (s),
-- the dragon silhouette (the height, the circle, the flight height, circles, the color), the shards (the size, the color, the pickup radius), the shard drop ring
Config.Weather = {
	rain = { rate = 220, area = 70, height = 28 },
	storm = { brightness = -0.08, saturation = -0.25, tint = { 205, 215, 235 }, flashEvery = { 6, 12 } },
	starfall = { every = 0.35 },
	dragon = { height = 28, radius = 200, altitude = 90, laps = 3, color = { 30, 28, 44 } },
	shard = { size = 3, color = { 150, 120, 255 }, pickRadius = 6 },
	shardRing = { 120, 260 },
	-- 2.9 (09 §3): Aurora - curtains of glow in an arc across the north of the sky (-Z, beyond Cliffs): panels panels of stripes rays, a SurfaceGui with
	-- a gradient (green at the bottom, violet at the top), the radius from the center, the arc (degrees), the bottom height, the panel size (studs), the brightness,
	-- the pixel density, the screen tint and darkening, the fade in/out (s)
	aurora = { panels = 9, stripes = 12, radius = 520, arc = { -75, 75 }, altitude = { 140, 190 }, size = { 190, 130 }, brightness = 3, pps = 2,
		tint = { 215, 232, 255 }, dim = -0.05, fade = 3, tick = 0.05,
		top = { 170, 100, 255 }, mid = { 80, 220, 255 }, low = { 90, 255, 150 }, edge = { 170, 255, 200 } },
}

-- ---------------------------------------------------------------------------------------------- the Index (03 §5, 06 §7; 1.11)
Config.Index = { store = "DN_Global", ancientKey = "ancient", readEvery = 120, minSetReward = 300 } -- store/ancientKey: the DataStore of the "Ancient worldwide" counter; minSetReward: the floor of the set reward (minutes of income)

-- ---------------------------------------------------------------------------------------------- analytics (11 §1-2; 1.12)
Config.Analytics = { enabled = true, warn = false, d0 = os.time({ year = 2026, month = 10, day = 23, hour = 0 }), deviceEvery = 30 } -- d0 = the launch D0 (the cohorts w1, w2...; before D0 - w0); deviceEvery: the device slice from the client not more than once per N s -- the launch 30.10 in Experience Beta, was 06.11; 23.10
-- for all players every every s the visible buttons of the screen and
-- the world; a pair intersects (the share of the smaller area >= minShare) longer than hold s - to the server (not more than perSession pairs per session; buttons
-- larger than bigShare of the screen - window backdrops - do not count); the server accumulates the pair counts per UTC day and every flush s writes to the DataStore store
-- (the key d_YYYYMMDD, not more than cap pairs). Read: cloud_test.py uioverlap_read
Config.Analytics.uiOverlap = { on = true, every = 1, hold = 2, minShare = 0.3, bigShare = 0.4, perSession = 20, flush = 120, store = "UiOverlap_v1", cap = 300 }
-- the visit map - every every s the player's zone (Core/Zones) into the profile
-- analytics.zones (seconds, the first visit, the last zone); on foot higher than highAbove studs above the ground - "glide" (gliding, falling),
-- riding higher than flyAbove - "sky" (a rider on an adult walks on the ground at a height of ~11, on an elder ~15 - that is not flight yet)
-- boredAfter: seconds without progress (Core/Zones.progressKey) - the mark goes into the zone's "boredom" (b)
Config.Analytics.zones = { on = true, every = 10, highAbove = 10, flyAbove = 22, boredAfter = 20 }
-- on the test since D0 two groups of newcomers - the firstborn growth 2/6 min (A, Balance.firstDragon.growMin,
-- the default) and 3/9 (B, growMinB). The group - the second bit of the UserId (floor(UserId / 2) % 2 = 1 - B, Core/Experiments.growGroup), independent
-- of the egg label experiment (the UserId parity): four equal cells. The mark is set on the firstborn at the hatch (growGroup = "B"), in Analytics -
-- "grow=A|B" in the cohort slice. The decision by the numbers on the 7th day of the test: the share who reached the first flight, leaves before the flight, the session length, D1.
-- force - Studio debugging only (LoopDebug "abgrow")
-- the test is OFF - no difference between 2/6 and 3/9 (flight 30% / 34%), all firstborns grow by growMin 1 / 3;
-- at on = false the B mark is not set and growMinB does not apply (Core/Growth, Core/Dragons). Switch on again only with a new wave of traffic.
Config.Balance.firstDragon.ab = { on = false, from = Config.Analytics.d0, growMinB = { 3, 9 }, force = nil :: string? }

-- the shop showcase shows 12 main items out of
-- 57 - Starter 49, the anchor 2,999, x2 Coins 299, Auto Collect 149, slots 99/199/399, Fast Incubator 249, Hatch now (while an egg warms),
-- the dragon of the week (in its window), appearances 99 and 299. The rest is hidden in the showcase, NOT removed: purchases by buttons in the world (Hatch now at the stand,
-- Grow now, the pass chips) and the bought items work as before; the prices did not change. To bring an item back - the key or the class into listed
Config.Shop.listed = {
	classes = { starter = true, bundle = true, hatchNow = true, dragonWeek = true },
	keys = { X2Coins_299 = true, AutoCollect_149 = true, NestSlot1_99 = true, NestSlot2_199 = true, NestSlot3_399 = true, FastIncubator_249 = true,
		Preset_Sunset_99 = true, NestSkin_Lagoon_299 = true },
}

-- ---------------------------------------------------------------------------------------------- live operations (09 §1, spec 1.2)
Config.LiveOps = { updateWeekdayUtc = 1, updateHourUtc = 19, updatePartyMinutes = 30, partyCoinsMult = 2 } -- 1 = Sunday (os.date wday)
-- 2.9: the update date poll (s); the errand scrolls 16-20 (Content.Notes): at the egg spot at (or at the stall), off - the desired offset
-- they hang lift above the ground, a light pillar of beam studs (visible only to the one who needs this scroll), pickup - a ProximityPrompt
Config.LiveOps.pollSeconds = 10
Config.LiveOps.scrolls = {
	points = { { at = "meadow_3", off = { 4, 0, 0 } }, { at = "cliffs_4", off = { 5, 0, 0 } }, { at = "springs_2", off = { 3, 0, 3 } }, { at = "summit_2", off = { 4, 0, 0 } }, { at = "stall", off = { 0, 0, -9 } },
		-- chapter 2 (update 2) and chapter 4 (update 4) - their own spots, placed from the date of their update
		{ at = "meadow_8", off = { 4, 0, 0 }, update = 2 }, { at = "cliffs_1", off = { 5, 0, 0 }, update = 2 }, { at = "springs_5", off = { 3, 0, 3 }, update = 2 }, { at = "summit_5", off = { 4, 0, 0 }, update = 2 }, { at = "stall", off = { 9, 0, 0 }, update = 2 },
		{ at = "meadow_5", off = { 4, 0, 0 }, update = 4 }, { at = "cliffs_7", off = { 5, 0, 0 }, update = 4 }, { at = "springs_4", off = { 3, 0, 3 }, update = 4 }, { at = "summit_4", off = { 4, 0, 0 }, update = 4 }, { at = "stall", off = { -9, 0, 0 }, update = 4 } },
	lift = 2.5, beam = 60, promptDistance = 10, maxDrop = 8, color = { 236, 214, 160 }, glow = { 255, 220, 140 },
	rings = { 6, 8, 10 }, eggGap = 5, clearWant = 4, noteDelay = 3, -- noteDelay: the note N s after the Done! banner
	 -- the spot - the one freest of parts on the rings around the point
}
Config.LiveOps.codeMax = 20 -- the length of the Code field in Settings
-- the community goal step by likes - the number in the toast after the "favorite" window; the step code "<N>LIKES" in
-- Content.Codes. The goal is reached - the code onto the page, the next step here (50 -> 100 -> 250 -> 500), a release
Config.LiveOps.likeGoal = 50

-- ---------------------------------------------------------------------------------------------- the world (04)
Config.World = {
	islandSize = 800,
	waterSize = 6000, -- 6,000, the silhouettes at 1,900-2,700 -- the sea is wider (Frost Isle at 1,500, the backdrop silhouettes up to 1,850); was 3,200 -- C2: the land up to ~720 by radius, Frost Isle at 1300, the backdrop at 1420; the world boundaries at waterSize/2 - 60 (was 1800)
	terrace = { radius = 170, y = 18 },
	-- the terrain is drawn ~2 studs above the computed height (the voxel
	-- occupancy is taken at its center), wallTop 16.5 gave grass at 18.5 on top of the floor 18.0 - the plaza and the flat nest parts flush with
	-- the grass flickered. 16.0 = the top voxel is empty, the grass exactly at 18.0 (the floor of the petals and the plaza)
	-- plazaSink - the terrain under the plaza lower by depth (except the inset strip at the edge),
	-- so that the grass top does not lie 0.5 under the plaza stone
	terraceTerrain = { enabled = true, wallTop = 16.0, plazaSink = { inset = 6, depth = 4 }, capHeight = 2.4, outset = 3, rimInner = 0.5 }, -- the grass rim from R+0.5 to R+3.5 (beyond the petal ledges) -- the terrace wall as terrain (Limestone + a grass rim)
	-- bottom - the bottom of the plaza rings (the thickness down to the terrain lowered by plazaSink)
	plaza = { radius = 50, bottom = 13 },
	-- the Old Ash plaza - an own mesh (tools/plaza_glb.py, the shape in Core/PlazaShape): a clay glade
	-- with an uneven outline, an ancient circle of slabs, paths to the stairs, 6 rune stones at the nests. A load failure - the old rings (plaza above).
	-- grassIn: the terrain grass (stalks through the clay rim) from this distance to the outline; the runes by day - dark carving, at night they glow
	-- importYaw: the extra turn of the nodes (a Roblox GLB import rotates every node by 180 degrees around Y)
	-- on the client
	-- only the max lights nearest to the camera within radius radius glow (Controllers/LightLod)
	nightLights = { max = 10, radius = 160, every = 0.5 },
	-- clayTint - the tint of the clay and the paths over the mesh texture (MeshPart.Color + SurfaceAppearance.Color), warm gray-sand instead of pink
	-- (a pink plaza blends with the characters)
	plazaMesh = { enabled = true, assetId = 111526844671795, importYaw = 180, grassIn = 2, runeDay = { 58, 66, 72 }, runeNight = { 110, 235, 255 },
		clayTint = { 196, 186, 168 } },
	-- Springs - "a cascade of turquoise baths", an own mesh tools/springs_glb.py (the shape in Core/SpringsShape):
	-- the hill as terrain, 4 travertine bowls and a lagoon (the rim in pieces, a white bottom, the water - a part of its own color), Beam spillways, steam above the upper ones.
	-- water: the color of the upper bowls (top) and the lagoon (low), the transparency, the reflectance; steam - steam above the bowls; sandNear - pebbles at the lagoon (studs)
	springsMesh = { enabled = true, assetId = 122801100393805, importYaw = 180, sandNear = 10,
		water = { top = { 150, 226, 222 }, low = { 84, 182, 194 }, transparency = 0.28, reflectance = 0.08 },
		steam = { pools = { "Pool4", "Pool3", "Pool2" }, rate = 5 }, cascade = { foamRate = 8, sound = "Lagoon" },
		-- apron: Salt terrain (travertine) around the bowls for around studs beyond the rim and a spillway strip of flow x the width; the color salt
		apron = { around = 3.5, flow = 1.6, salt = { 198, 186, 160 } }, -- 214,204,182 under the sun read as snow
		-- the gate (add. 2.9): a "water curtain" in the arch SpringsShape.gate; passage only riding a teen or older (a barrier in the collision
		-- group Curtain: not on foot, Rider/Dragon pass); the guard: a hatchling (CompanionStage < needsStage) inside Springs
		-- (west of the brook) every checkSeconds is returned to the crossing back with a hint; strips - jets in the curtain; rocks - the rocks at the arch
		night = { glow = { 90, 220, 232 }, range = 18, brightness = 1.2, fireflies = 6, firefliesLength = 150 }, -- 5 PointLights without shadows + an emitter, only at night
		gate = { needsStage = 1, checkSeconds = 0.5, back = { -192, 8, 22 }, toastEvery = 6, strips = 3, partNear = 32,
			rocks = { { "ph_rock1_4", -243, 7, 11, 20 }, { "ph_rock2_6", -246, 41, 12, 140 }, { "ph_rock1_0", -236, 0, 8, 70 }, { "ph_rock1_3", -239, 49, 9, 200 } } } },
	keeper = { x = 0, y = 18, z = 0 },
	stall = { x = 0, y = 18, z = -40 },
	-- an updraft (tag Updraft
	-- Controllers/Updraft) - inside the pillar a rise at speed rise; nest - a pillar right past the ledge of every nest (locally: from
	-- below under the edge to above above it, width width, depth depth, gap gap from the edge): the slope past the ledge is gentle, without the stream one cannot
	-- glide from the ledge; a rise of ~12 above the edge -> a glide of ~110 studs, landing on the meadow (the eggs at r 200-260)
	-- width 52 = the whole ledge (the plot 56 without the railing posts): there is no arrow to the ledge at errand 2, they can step off anywhere
	updraft = { rise = 30, center = 2, nest = { width = 52, depth = 8, gap = 1, below = 16, above = 12, labelDistance = 45, wisps = 6 } }, -- center: without input the speed toward the pillar axis = the distance x center
	-- the Dragon of the Week stand on the plaza - to the side of the stall, off the path to the northern stairs (90 deg.)
	-- ~10 studs from the stall lantern and the rune stone of nest 2; the snout toward the plaza center (face). The height - by a raycast onto the plaza
	dragonStand = { x = 14, z = -32, faceX = 0, faceZ = -12, radius = 6, height = 1.6, labelAbove = 2, labelMaxDistance = 90, promptDistance = 9 }, -- 14 reached the spawn slab (0,-30) - a View button at the entry
	nests = { count = 6, angleStep = 60, lotWidth = 56, lotDepth = 110, rInner = 60, rOuter = 170, wallHeight = 3.4 }, -- the wall of 9 caught the dragon at takeoff - the previous 3.4; the first egg is two pens away anyway (section 25)
	-- the nest's local coordinates: the origin at the petal center, +Z from the plaza to the ledge, X - the width
	nestLayout = {
		sign = { 0, 10, -54 },
		spawn = { 0, 0, -50 },
		eggTable = { -12, 0, -44 }, -- the newcomer's table with 3 eggs, 6 studs from Incubator1
		incubators = { { -18, 0, -46 }, { -18, 0, -38 }, { -18, 0, -30 } },
		shelf = { { 18, 0, -46 }, { 18, 0, -42 }, { 18, 0, -38 }, { 18, 0, -34 }, { 18, 0, -30 } },
		coinPile = { 0, 0, -34 },
		-- the nest fills from the middle of the pen, the row at the incubators and the shelf
		-- (z = -18, 12 studs from Incubator3) - last; the elder's span is more than 12 studs
		slots = {
			{ -20, 0, 14 }, { 20, 0, 14 }, { -20, 0, 30 }, { 20, 0, 30 }, { -20, 0, -2 },
			{ 20, 0, -2 }, { -20, 0, 46 }, { 20, 0, 46 }, { -20, 0, -18 }, { 20, 0, -18 },
		},
		slotYaw = 45, -- the turn toward the passage and the entrance (the sign by the side)
		slotPadRadius = 6,
		showcase = { 0, 0, 50 },
		decor = { { -27, 0, -40 }, { 27, 0, -40 }, { -27, 0, 0 }, { 27, 0, 0 }, { -27, 0, 40 }, { 27, 0, 40 } },
		ledgeZ = 55,
	},
	stairs = { width = 8, slopeDeg = 30 },
	zones = {
		Meadow = { y = 0, ring = { angles = 36, radii = { 200, 260 } }, points = 10, move = { [6] = { -174, 193 } } }, -- meadow_6 (-260, 0) stood inside Springs (closed to a hatchling) - south across the brook
		Cliffs = { y = { 40, 50, 60 }, xFrom = -140, xStep = 40, z = -330, points = 8, wind = { size = 10, x = 0, dz = 30, clear = 6 } }, -- the stream at the foot (x, z + dz), clear - the margin from the facade boulders (DecorLayout)
		Springs = { y = 4, xs = { -340, -300, -260 }, zs = { -40, 80 }, points = 6, bridge = { x = -212, z = 20 }, bridgeModel = true }, -- shifted west, the bridge off the terrace
		Summit = { center = { 0, 120, 310 }, ring = 30, points = 6 },
	},
	frostIsle = { x = 1500, wallX = 1100, open = false }, -- open: false - east of wallX not on foot (AntiCheat "zone"), when the island opens - true -- farther; was 1,300 / 1,000 -- C2: across the strait from the noisy shore (the land up to 720); C3: the island itself - island2.extra[1]
	mountain = { baseRadius = 90, topRadius = 40, topDisc = false }, -- the disc on the top is removed; the top - Ground terrain -- spec 1.2 (04 §2): the truncated Summit cone, the height = zones.Summit.center[2]
	-- spec 1.2 (04 §5.1): wind rings from the southern ledge around the western slope of Summit to the top
	windRings = {
		-- a radius of 7 is smaller than an adult dragon (15) - flying past is borderline; in HTTYD the ring is larger than the dragon. Radius 14, 12 segments
		radius = 14,
		segments = 12,
		color = { 255, 230, 120 },
		rewardSeconds = 10,
		rewardMin = 5,
		rearmSeconds = 60,
		positions = {
			{ 0, 38, 185 }, { -60, 52, 230 }, { -100, 68, 275 }, { -105, 84, 325 },
			{ -80, 100, 365 }, { -35, 114, 385 }, { 20, 128, 370 }, { 0, 142, 325 },
		},
	},
	backdropIslands = 0, -- the terrain balls are removed; the silhouettes - decor.c7.backdrop
	backdropRadius = 1420, -- C2 (was 950 with the sea at 1800)
	clouds = { count = 18, yMin = 150, yMax = 250, balls = false, volumetric = { cover = 0.55, density = 0.3 } }, -- "white balls in the sky" - the balls are off, the clouds volumetric (Terrain.Clouds)
	colors = { -- 0-255 (04 §10)
		grass = { 84, 206, 62 }, -- more saturated ("brighter, richer")
		sand = { 245, 220, 150 },
		water = { 16, 48, 100 }, -- dark ultramarine with a strong sun glint (lighter values glow neon turquoise above the sandy bottom)
		stone = { 148, 132, 112 }, -- C1 pass 2: 178,160,138 under Future in the sun - white; the plaza/step parts go into the terrain in C2
		rock = { 165, 150, 138 }, -- 120,110,105 read as black under Soft
	},
	waterTransparency = 0.2, -- denser (HTTYD); C1 pass 2: the references 0.3
	waterWave = 0.45, -- frequent ripples with glints (HTTYD); C1 was 0.3
	waterWaveSpeed = 13,
	waterReflectance = 0.95, -- a sun path as in HTTYD; C1 was 0.3
	pickDistance = 8, -- the distance checks from the character (10 §4)
	placeDistance = 10,
	mountDistance = 12,
	partyRadius = 4,
	streamingEnabled = true, -- C3 (spec 04 addendum 2.1 item 2): the world grew (the land 1,200, Frost Isle at 1,300) - streaming in the place file (build.py)
	streaming = { minRadius = 400, targetRadius = 1400, behavior = "Improved" }, -- the whole main island and the pillars within the target radius from the spawn
	bounds = { margin = 60, height = 400, returnBelowY = -30, checkSeconds = 2, warnAt = 0.9, holdAt = 0.985, warnEvery = 8 }, -- a soft boundary in flight (Fly): from warnAt x the limit the turnBack hint every warnEvery s, from holdAt it does not let outward (the outward speed is damped), the server teleport stays a fallback
	-- the color was picked on P8 by an experiment of 6 variants (v3: the brightness step at the seam with the terrain water 11 against 20 for the previous
	-- dark 9,32,76 - a "seam" there is in fact a streaming void); built by the client (Ocean)
	seaPlane = { size = 24000, color = { 60, 120, 170 }, reflectance = 0, below = 0.6, client = true }, -- the "sea" plane to the horizon beyond the terrain water (4 strips around the waterSize square), slightly below the sea level, darker and without a glint so the seam does not show
	-- a soft swimming ban (craft/04 §7.10 series 11, HTTYD): after showAfter s in the water a caption + a Back to shore button
	-- (if there is no teen/adult nearby - then the Ride button from the HUD); the shore is found by rays over rings of shoreRings studs, shoreRays
	-- directions, land = a hit above seaLevel + shoreAbove without water; Dismount above water refuses (over_water)
	swim = { showAfter = 1.5, pollSeconds = 0.25, shoreRings = { 12, 24, 40, 60, 90, 130, 180, 250, 350, 450, 600 }, shoreRays = 16, shoreAbove = 0.5, shoreCooldown = 3, shoreLift = 3.5, shoreMaxY = 14 },
	-- polish 1.5 (craft/04 §7.4-7.8, richer nature): hills, paths, slab rocks at the edge
	-- floating islets, coins on the paths, visible zone gates, stair steps, the plaza pattern
	hills = { count = 44, radius = { 22, 40 }, height = { 4, 10 }, seed = 5, rMin = 215, rMax = 350, coastShare = 0.88, keepFromPoints = 24, keepFromStairs = 34, keepFromSigns = 24, keepFromPaths = 14 }, -- C2: hills over the whole land up to 0.88 of the shore radius (rMax is not used)
	paths = { width = 9, step = 6, parts = 4, curve = 14, widthVar = 0.25, routes = { { stairs = 90, to = "Cliffs" }, { stairs = 150, to = "Springs" }, { stairs = 30, to = "meadow_2" }, { stairs = 270, to = "meadow_8" } } }, -- the Summit/Meadow signs stand at the foot of the stairs, no paths to them needed
	edgeRocks = { count = 40, rMin = 394, rMax = 412, coastFrom = 0.955, coastTo = 0.985, size = { 16, 32 }, height = { 8, 16 }, seed = 9, skipAngles = { { 60, 120 }, { 150, 215 }, { 255, 285 } } }, -- C2: the radius = a share of the shore radius (rMin/rMax are not used) -- the gaps: the Cliffs rock (north), Springs with the channel (west), the Summit mountain (south)
	-- the waterfall ribbon textures (waterfall.textures) - the client's built-in files rbxasset://textures/particles (Open Cloud images do not always load on phones); the order: Fall, Core, Veil
	islets = { yMin = 120, yMax = 160, radius = { 12, 17 }, terrain = true, ballScale = 0.4, ring = { count = 11, seed = 31, rMin = 160, rMax = 300, yMin = 95, yMax = 215, skipToPlaza = 40, minGap = 40, tiers = { { r = { 7, 10 }, n = 4 }, { r = { 13, 18 }, n = 4 }, { r = { 22, 30 }, n = 3 } } }, waterfall = { count = 3, length = 80, out = 4, width = { 6, 11 }, curve = 6, mistRate = 22, dropsRate = 30, textureLength = 22, speed = { 1.4, 2.6, 0.9 }, lightInfluence = 0.7, foamRate = 16, textures = { "rbxasset://textures/particles/smoke_main.dds", "rbxasset://textures/particles/forcefield_vortex_main.dds", "rbxasset://textures/particles/smoke_main.dds" } }, rocks = { outcrops = 2, bodyH = { 1.1, 1.5 }, bodyKinds = { "ph_rock1_4", "ph_rock2_6", "ph_rock1_0" }, bodyScale = 1.25, taper = 0.72, kinds = { "ph_rock1_4", "ph_rock1_0", "ph_rock2_6", "ph_rock1_1", "ph_rock_moss_set_01", "ph_rock_moss_set_02" }, vinesBase = 6, vinesPerTier = 3, vinesMax = 45, greenPerR = 0.45, green = { "under_fern", "cs_bush", "under_shrub", "cs_grass" }, trees = { { n = { 0, 1 }, h = { 10, 16 }, kinds = { "cs_firs", "cs_pine_gabe" } }, { n = { 1, 2 }, h = { 16, 24 }, kinds = { "cs_firs", "cs_birch", "cs_oak", "cs_ponderosa" } }, { n = { 2, 3 }, h = { 22, 32 }, kinds = { "cs_bigoak", "cs_oak", "cs_birch2", "cs_firs" } } } }, positions = { { 150, 128, -120 }, { -160, 150, 170 }, { 240, 140, 230 }, { -90, 158, -230 } } }, -- 10 living islands in a ring around Summit (ring), the body of rocks, vines, greenery, trees, waterfalls at the 3 big ones; positions - the old 4 (a reserve)
	coins = { value = 10, perRoute = 3, respawnSeconds = 180, size = 2.4, touchSlack = 8 }, -- touchSlack: studs from the coin edge to the root's honest position
	gates = { springs = { transparency = 0, height = 14, width = 12 }, frost = { transparency = 0.7, height = 60, band = false, -- the sign on a rock in front of the wall, the island - for a later update
		sign = { back = 6, postBottom = -4, postTop = 16, boardY = 16, boardSize = { 18, 7.5 }, rockY = -8, rocks = { { 0, 0, 14, "ph_rock1_4", 20 }, { -3, 5, 9, "ph_rock2_6", 140 }, { 2, -5, 8, "ph_rock1_0", 260 } } } } }, -- ForceField is semi-transparent by itself; at 0.5 the barrier is not visible
	stairsSteps = 12,
	-- the yellow arrows on the nest floors and at the stairs (they get buried or flicker; the way is shown by the Hints chevrons)
	groundArrows = false,
	plazaRings = { 36, 22, 8 }, -- the radii of the pattern rings on the plaza (alternating stone tone)
	incubatorLight = { range = 14, brightness = 1.6, color = { 255, 200, 120 } }, -- spec 1.3 (04 addendum): occupied incubators only
	-- the incubator - a stone bowl with straw, an own mesh tools/incubator_glb.py
	-- (the frames in Core/IncubatorShape). The runes and the rim ring by day - dark carving runeIdle, at an occupied incubator they glow runeWarm (Neon);
	-- sparks - warm sparks above an occupied one (per second). An invisible stop along the rim of height wallHeight: the player does not walk into the bowl and does not
	-- stand on it (Loop.placeRadius 3.8 - the egg jumps into the bowl when the player runs into the rim). A load failure - the old discs
	incubatorMesh = { enabled = true, assetId = 101382942503872, importYaw = 180, runeIdle = { 72, 64, 58 }, runeWarm = { 255, 168, 74 },
		sparks = 3, sparkZone = 2.4, wallHeight = 12, lockSize = { 5.2, 3.0, 5.2 } }, -- the stop 8 -> 12 (they jumped onto the top from the table)
	-- mesh decor .
	-- The meshes - Kenney Nature Kit 2.1 (CC0), split by materials (tools/kenney_split.py), recolored with the palette below.
	-- The heights in studs (the model is normalized by height to 1 in ModelLibrary).
	decor = {
		enabled = true,
		placeholders = false, -- the old placeholders of balls and slabs
		seed = 21,
		groves = { count = 25, trees = { 6, 10 }, radius = { 18, 34 }, spacing = 8 }, -- C2: x1.8 to the area (was 14)
		singles = 144, -- C2 (was 80)
		treeKinds = { "cs_ponderosa", "cs_ponderosa", "cs_firs", "cs_firs", "cs_pine_gabe" }, -- only Creator Store conifers (no cartoonish ones); the Letaij broadleaves (cs_birch, cs_oak) are added after Get
		coniferKinds = { "cs_ponderosa", "cs_firs", "cs_pine_gabe" }, -- the ridges, the ridge top, the pillars, the islets
		undergrowth = { ferns = 160, shrubs = 140, heather = 110, fernKinds = { "under_fern" }, shrubKinds = { "under_shrub" }, heatherKinds = { "cs_bush", "cs_wildflower" }, nearTrees = 0.6 }, -- the heather -> a realistic bush and flowers -- C4: the undergrowth (spec 04 addendum 2.0 item 3: 4-5 kinds per frame)
		accents = { { kind = "cs_redcedar", share = 0.025 }, { kind = "cs_fall", share = 0.006 } }, -- the painted autumn/blossom ones are removed; the Letaij cedar rarely (42 parts); C7: the Sebul6 autumn tree rarely (25 parts + a leaf-fall emitter)
		-- C7: the Letaij broadleaves in the lowlands at the water (a share of the shore radius from from), on the ridges and pillars only conifers. The choice by
		-- coordinate (a hash), the layout generator does not shift
		lowland = { from = 0.62, share = 0.6, kinds = { "cs_birch", "cs_birch2", "cs_oak", "cs_oak" } },
		height = {
			tree_default = { 14, 20 }, tree_detailed = { 16, 22 }, tree_fat = { 12, 16 }, tree_oak = { 16, 22 }, tree_default_fall = { 14, 18 },
			ptree_green_round = { 18, 26 }, ptree_green_tall = { 22, 30 }, ptree_green_wide = { 16, 22 }, ptree_dark_round = { 18, 26 }, ptree_dark_tall = { 22, 30 },
			ptree_autumn_round = { 17, 24 }, ptree_blossom_round = { 16, 22 },
			ctree_pine_a = { 30, 46 }, ctree_pine_b = { 26, 40 }, ctree_spruce_a = { 28, 44 }, ctree_spruce_b = { 24, 38 }, -- C4: conifers 40-80 studs in HTTYD, ours 24-46 for a start
			cs_ponderosa = { 28, 42 }, cs_firs = { 26, 38 }, cs_redcedar = { 32, 44 }, cs_pine_gabe = { 28, 40 }, -- Creator Store (the height by the world frame, Decor.placeWorld)
			under_fern = { 2.6, 4.2 }, under_shrub = { 2.4, 4.4 }, under_heather = { 1.6, 2.8 },
			-- C7: broadleaves and giants, PBR undergrowth, buildings. For D.byLength - the length, not the height
			cs_birch = { 26, 36 }, cs_birch2 = { 26, 36 }, cs_oak = { 24, 34 }, cs_fall = { 22, 30 }, cs_bigoak = { 28, 38 }, cs_oldtree = { 26, 36 },
			cs_jungleoak = { 36, 44 }, cs_baobab = { 48, 60 }, cs_snowfir = { 24, 38 },
			cs_bush = { 2.4, 4 }, cs_grass = { 1.6, 2.6 }, cs_mushrooms = { 1, 1.8 }, cs_log = { 1.4, 2.2 }, cs_stump = { 1.6, 2.6 }, cs_stump2 = { 1.6, 2.6 },
			cs_flower = { 1, 1.6 }, cs_wildflower = { 1.2, 2 }, cs_cattail = { 3, 4.5 }, cs_rocks = { 2, 4.5 },
			cs_campfire = { 2.6, 2.6 }, cs_logstack = { 3, 3.4 }, cs_streetlight = { 12, 12 }, cs_crystal_amber = { 4, 7 }, cs_crystal_pb = { 4, 6 }, cs_vines = { 14, 22 },
			cs_pier = { 18, 18 }, cs_boat = { 9, 9 }, cs_stonepath = { 3.2, 4.4 }, cs_bridge = { 28, 28 },
			-- Poly Haven CC0 (PBR, 6-16k triangles per rock; LOD RenderFidelity Automatic): the rocks of the sets rock_moss_set_01/02 one by one
			ph_rock1_0 = { 6, 12 }, ph_rock1_1 = { 6, 12 }, ph_rock1_2 = { 4, 8 }, ph_rock1_3 = { 6, 12 }, ph_rock1_4 = { 8, 16 }, ph_rock1_5 = { 5, 10 },
			ph_rock2_0 = { 5, 10 }, ph_rock2_1 = { 5, 10 }, ph_rock2_2 = { 5, 10 }, ph_rock2_3 = { 5, 10 }, ph_rock2_4 = { 5, 10 }, ph_rock2_5 = { 5, 10 }, ph_rock2_6 = { 6, 12 },
			ph_rock_moss_set_01 = { 6, 10 }, ph_rock_moss_set_02 = { 5, 8 }, ph_fern_02 = { 3, 5 }, ph_rock_09 = { 1, 2 },
			tree_pineRoundA = { 18, 26 }, tree_pineTallB = { 22, 30 }, tree_palmDetailedTall = { 16, 22 }, tree_palmBend = { 12, 16 },
			plant_bush = { 2.5, 4.5 }, plant_bushDetailed = { 2.5, 4.5 }, plant_bushLarge = { 3, 5 },
			grass = { 2.2, 3.2 }, grass_large = { 2.4, 3.6 }, grass_leafs = { 2.2, 3.2 },
			flower_redA = { 1.2, 1.9 }, flower_yellowB = { 1.2, 1.9 }, flower_purpleC = { 1.2, 1.9 },
			mushroom_redGroup = { 1.4, 2.4 }, mushroom_tanTall = { 1.6, 2.6 },
			rock_largeA = { 2.5, 5 }, rock_largeC = { 2.5, 5 }, rock_smallA = { 1, 2 }, rock_smallFlatA = { 0.6, 1.2 }, rock_tallB = { 4, 8 }, rock_tallF = { 4, 8 },
			stone_largeB = { 3, 6 }, stone_tallC = { 5, 9 }, stone_smallFlatB = { 0.5, 1 },
			cliff_block_stone = { 14, 22 }, cliff_blockSlope_stone = { 14, 22 }, cliff_corner_stone = { 14, 22 }, cliff_top_stone = { 12, 18 }, cliff_steps_stone = { 14, 20 }, cliff_large_stone = { 14, 22 },
			log = { 1.2, 1.8 }, log_stackLarge = { 2, 3 }, stump_roundDetailed = { 2, 3 },
			lily_large = { 0.35, 0.5 }, campfire_stones = { 0.8, 0.8 }, sign = { 6, 6 }, path_stone = { 0.3, 0.4 }, fence_simple = { 2.5, 2.5 },
		},
		bushes = { perGrove = { 3, 6 }, scattered = 144, kinds = { "under_shrub", "cs_bush", "under_fern", "cs_bush" } }, -- the heather under_heather (a violet lump on the phone) -> cs_bush; the same pick call - the layout does not shift -- C7: a PBR bush instead of half of the own cards -- C4: own cards instead of Kenney bushes
		grass = { count = 50, kinds = { "cs_grass" }, nearPaths = 0.5, nearPoints = 0.3 }, -- C7: PBR tufts instead of Kenney -- -- pass 2: Terrain.Decoration gives the grass, tufts only at the paths and spots -- the tufts looked like clippings; the main grass - Terrain.Decoration
		flowers = { patches = 14, perPatch = { 5, 9 }, radius = { 4, 8 }, kinds = { "cs_flower", "cs_wildflower" } }, -- C7: realistic flowers in patches -- -- the cartoonish Kenney flowers are removed; the color comes from the heather and the spruce
		mushrooms = { count = 4, kinds = { "cs_mushrooms" } }, -- C7: PBR mushrooms at the trees, rarely (a pack of 22 parts as a whole: 30 pcs = 660 parts) -- -- the cartoonish mushrooms are removed
		rocks = { count = 80, kinds = { "ph_rock1_0", "ph_rock1_1", "ph_rock1_3", "ph_rock2_0", "ph_rock2_2", "ph_rock2_4", "ph_rock_moss_set_02" } }, -- cs_rocks are removed -- -- Poly Haven instead of Kenney
		stones = { summit = 8, cliffsFoot = 10, kinds = { "ph_rock1_4", "ph_rock2_6", "ph_rock1_0" } },
		logs = { count = 22, kinds = { "cs_log", "cs_stump", "cs_stump2" } }, -- C7: a PBR log and stumps instead of Kenney
		shore = { palms = 0, palmKinds = { "tree_palmDetailedTall", "tree_palmBend" }, driftwood = 18, driftKind = "cs_log", flatStones = 40, rMin = 396, rMax = 414, coastFrom = 0.93, coastTo = 0.962 }, -- C2: a share of the shore radius (the dry beach 0.92-0.964)
		cliffTop = { pines = 22, y = nil, kinds = { "cs_ponderosa", "cs_firs", "cs_pine_gabe" } }, -- Creator Store conifers by the ridge terrain (y nil = on the ground)
		edge = { kinds = { "ph_rock1_4", "ph_rock1_0", "ph_rock2_6" }, perSpot = { 2, 4 }, spread = 14, height = { 7, 14 }, sink = 1.5 },
		fence = { kind = "fence_simple", height = 2.8, tint = { 150, 100, 70 }, tintDark = { 95, 60, 40 } }, -- P18: the nest fence as a mesh (Kenney), the posts in the mesh
		forestBelt = { count = 260, rMin = 330, rMax = 388, coastFrom = 0.80, coastTo = 0.93, spacing = 8, skipAngles = { { 60, 120 }, { 150, 215 }, { 255, 285 } } }, -- C2: the forest belt by a share of the shore radius -- a forest wall along the perimeter (Ride A Pet): the world edge is not visible
		terraceFoot = { boulders = 22, bushes = 36, rMin = 174, rMax = 184, kinds = { "ph_rock1_0", "ph_rock2_2", "ph_rock2_4" } }, -- the terrace foot: boulders and bushes hide the flat wall
		barkTint = { { 255, 245, 235 }, { 240, 228, 215 } }, -- the bark texture tone of the painted trees
		leafTint = { { 255, 255, 255 }, { 236, 250, 226 }, { 250, 242, 222 }, { 228, 244, 236 } }, -- P17: a light foliage tone over the texture (Color multiplies the texture) -- pass 2: rock_* (ground+grass) at the water read as sand heaps; only gray stone -- modular cliff_* one by one = gray boxes; now boulder clusters
		springs = { stones = 12, bushes = 8, palms = 0, flowers = 10, y = 4 }, -- C4: no palms (the north) -- the decor of the Springs area (the pond water at y 4)
		terraceGardens = { trees = 2, bushes = 5, flowers = 0, rocks = 1, treeHeight = { 9, 12 } }, -- the Kenney flowers are removed -- the terrace wedges between the petals (6 of them)
		pathStones = { step = 9, kind = "cs_stonepath" }, -- C7: a PBR stone slab (h = the length)
		lilies = { count = 7, kind = "lily_large" },
		islets = { tree = "cs_firs", bush = "under_shrub" }, -- C4; the Letaij spruce
		collideHeight = 3, -- rocks and stumps taller than this are solid; tree trunks and cliffs are always solid
		-- C7: how to treat Creator Store models. byLength: h = the length along the long axis, yaw = the direction of this axis;
		-- onePart: a pack of separate parts -> one by tint; nightKinds: their Lights switch on only at night (tag NightLight)
		byLength = { cs_pier = true, cs_boat = true, cs_stonepath = true, cs_bridge = true },
		onePart = { cs_rocks = true, cs_mushrooms = true },
		nightKinds = { cs_campfire = true, cs_streetlight = true, cs_crystal_pb = true },
		lightMax = { range = 14, brightness = 0.9 }, -- a small range so campfires and lanterns do not paint the grass yellow
		trunk = { size = 2.4, height = 10 }, -- the cs_ trees without collisions, only the invisible trunk is solid
		-- Creator Store buildings and large objects are solid as a whole, big
		-- trees - only the trunk (the trunk rule); the own conifers ctree_ - also an invisible trunk
		solidKinds = { "cs_stall", "cs_bridge", "cs_pier", "cs_logstack", "cs_boat", "cs_log", "cs_stump", "cs_stump2", "cs_rocks", "cs_fence", "cs_streetlight", "cs_oldtree", "cs_bigoak", "cs_baobab", "cs_jungleoak", "cs_oak", "cs_ponderosa", "cs_redcedar", "cs_crystal_amber", "cs_crystal_pb" }, -- the Cliffs crystals (4-7 studs) could be walked through
		-- on the client, models lower than maxH beyond dist are not
		-- drawn (Controllers/DecorLod); above the last row - always visible (trees, rocks, islands). level - the default level
		lod = { on = true, level = "normal", every = 0.5, rescanEvery = 5,
			levels = { normal = { { 6, 160 }, { 12, 300 } }, strong = { { 6, 110 }, { 12, 220 }, { 30, 500 } } } },
		lightsPerModel = 1, -- 1.14 (a Studio measurement: 35 PointLights at night with a limit of 12, campfires 2 at one point): the extra light of a model is removed
		emittersPerModel = 2, -- C7: not more fire/smoke effects per model (Studio: 50 emitters with a limit of 30)
		-- C7: the layout of the new models by an own generator (seed), the layout before C7 does not shift. Spec 04 addenda 2.0 item 4, 2.2
		c7 = {
			seed = 77,
			bigTrees = { -- the glade giants; the baobabs - a landmark at the terrace (spec 04 2.2 item 3)
				{ kind = "cs_baobab", count = 2, margin = 18, spacing = 30, rMin = 222, rMax = 262 },
				{ kind = "cs_bigoak", count = 8, margin = 12, spacing = 16 },
				{ kind = "cs_oldtree", count = 8, margin = 12, spacing = 16 },
			},
			fixed = {}, -- the old oak at the lagoon is removed -- the old oak with vines at the Springs lagoon (102 parts - a single one)
			snowFirs = { kind = "cs_snowfir", count = 70, spacing = 12, peakClear = 70 }, -- Frost Isle only
			cattails = { kinds = { "cs_cattail" }, perR = 0.7, inset = 1, band = 4 }, -- cattails along the rim of the lagoon circles
			crystals = { count = 10, glowShare = 0.3, kinds = { "cs_crystal_amber", "cs_crystal_pb" } }, -- in the shadow of the Cliffs ridge
			vines = { perIslet = 2, cliffs = 8 }, -- a curtain of vines from the floating islets and from the ridge edge
			camp = { r = 128, across = 13, clear = 9 }, -- a campfire + a woodpile + 2 stumps on every terrace wedge (6)
			lights = { step = 64, max = 8, offset = 2.5 }, -- lamp posts along the paths (the Light only at night)
			bridge = { length = 28, top = 1.4 }, -- a Creator Store rope bridge across the Springs brook (the WorldBuilder plank is invisible, they walk on it)
			summitTop = { rocks = 9, rockR = { 33, 40 }, bushes = 7, bushR = { 6, 18 } }, -- the top - grass, rocks along the edge, bushes in the center (past the egg spots on the ring 30)
			summitGreen = { plants = 40, trees = 10, rFrom = 50, rTo = 108, plantKinds = { "under_fern", "cs_bush", "under_shrub" }, treeKinds = { "cs_firs", "cs_ponderosa", "cs_pine_gabe" }, treeH = { 18, 28 } }, -- the mountain slopes are not bare (spec 04 2.6 item 1)
			creekBanks = { step = 8 }, -- the banks of the Springs brook (spec 04 2.6 item 4)
			backdrop = { count = 10, rMin = 1900, rMax = 2500, skipDeg = 40, kinds = { "ph_rock1_4", "ph_rock2_6", "ph_rock1_0" }, base = { 85, 120 }, pines = { "cs_ponderosa", "cs_firs" },
				isles = { count = 2, angles = { 75, 285 }, rMin = 2300, rMax = 2700, base = { 240, 320 }, pieces = 5, pines = 6 } }, -- 10 pillars at 1,900-2,500 and 2 silhouette islands (a ridge of 5 rocks with pines) at 2,300-2,700, the sea 6,000 -- distant rock pillars with pines instead of terrain balls; past Frost Isle (angle 0)
			pier = { from = { -261, 36 }, to = { -281, 37 }, deck = 2.0 }, -- into the lagoon bowl (add. 2.7); was -268,22 -> -286,22 -- a pier into the Springs lagoon (the water 3), the deck top
			boat = { x = -292, z = 44, sink = 0.7 }, -- was -291, 34
		},
		batch = 60, -- models per frame during construction
	},
	-- the recolor palette by the Kenney material name (several variants = a random shade per copy)
	palette = {
		leafsGreen = { { 96, 186, 78 }, { 78, 168, 92 }, { 118, 198, 72 }, { 150, 205, 80 } },
		leafsDark = { { 56, 140, 96 }, { 70, 150, 80 } },
		leafsFall = { { 242, 150, 60 }, { 235, 120, 70 } },
		woodBark = { { 125, 85, 55 } }, woodBarkDark = { { 95, 65, 45 } }, woodBirch = { { 225, 215, 195 } }, woodInner = { { 230, 200, 160 } },
		woodDark = { { 80, 55, 40 } }, wood = { { 150, 100, 70 } },
		grass = { { 104, 196, 76 }, { 122, 206, 84 }, { 96, 190, 70 } },
		dirt = { { 178, 140, 95 } }, stone = { { 170, 160, 148 }, { 148, 146, 140 }, { 160, 152, 142 } }, stoneDark = { { 120, 110, 105 } }, -- not a warm beige: by the water it reads as sand
		colorRed = { { 235, 80, 80 } }, colorYellow = { { 250, 210, 60 } }, colorPurple = { { 170, 100, 220 } }, colorWhite = { { 255, 255, 255 } },
		colorTan = { { 225, 195, 150 } }, _defaultMat = { { 172, 166, 158 } }, -- the Kenney rock highlights: not white; C1: even darker, under Future 205 glowed white
	},
	leafyPatches = { count = 0, radius = { 14, 30 }, seed = 23 }, -- the patches are removed - there is no tall grass on LeafyGrass (Terrain.Decoration only on Grass), the phone draws them as a flat square; was 40 (12% of the meadow) -- C2: x1.8 -- LeafyGrass patches on the glade: 3-4 materials per frame, like the leaders
	-- P16: a day cycle like Ride A Pet.
	-- The phases: ClockTime from..to, the light (Ambient / OutdoorAmbient / Brightness / the atmosphere color), lanterns on/off. The ground at night is readable:
	-- the night Ambient ~118,120,146, Brightness 0.85 (a moonlit night).
	dayCycle = {
		enabled = true,
		phases = { -- C1: the values for Realistic/Future (Ambient = the shadow, OutdoorAmbient = the sky); the night readable, not black
			{ id = "dawn", seconds = 60, clock = { 5.5, 9.5 }, lights = true, ambient = { 80, 66, 78 }, outdoor = { 150, 120, 130 }, brightness = 1.4, atmoColor = { 240, 200, 190 }, atmoDecay = { 150, 110, 150 }, haze = 1.4, glare = 0.4 },
			{ id = "day", seconds = 240, clock = { 9.5, 15.5 }, lights = false, ambient = { 70, 72, 80 }, outdoor = { 128, 146, 176 }, brightness = 1.7, atmoColor = { 205, 218, 235 }, atmoDecay = { 92, 112, 150 }, haze = 1.1, glare = 0.1 }, -- the haze 0.9 -> 1.1 (the distant silhouettes sink into the perspective)
			{ id = "dusk", seconds = 45, clock = { 15.5, 18.6 }, lights = true, ambient = { 84, 64, 62 }, outdoor = { 170, 120, 110 }, brightness = 1.4, atmoColor = { 245, 185, 160 }, atmoDecay = { 160, 100, 130 }, haze = 1.4, glare = 0.6 },
			{ id = "night", seconds = 75, clock = { 18.6, 29.5 }, lights = true, ambient = { 134, 136, 162 }, outdoor = { 136, 152, 204 }, brightness = 1.15, atmoColor = { 110, 130, 190 }, atmoDecay = { 50, 60, 120 }, haze = 0.9, glare = 0 }, -- was 118,120,146 / 118,132,182 / 0.85
		},
		-- the shares 240 / 45 / 75 / 60 = 420 s, the bright day 57%, with the dawn 71%;
		-- worldClock - the phase from the world time os.time() % the cycle: one for all servers, the entries are spread evenly over the cycle (otherwise
		-- a new server is at night a few minutes after start). Studio - startPhase
		worldClock = true,
		startPhase = "day", -- the server starts by day (the newcomer's first minutes - in daylight, 02 §1)
		starCount = 3500,
		lantern = { torch = true, flame = 2.6, range = 14, brightness = 1, color = { 255, 214, 170 } }, -- torches instead of lantern models; a small range and a warm color so the grass is not painted yellow -- the lanterns at the nest entrance, the stall, the Keeper, the Springs gate
	},
	terrainDecoration = true, -- the animated terrain grass; written by build.py
	grassLength = 0.6, -- the grass full height; higher values put the character waist-deep and sink the camera
	cliffMaterial = "Rock", -- was Limestone (smooth gray in stripes on the phone) -- the Cliffs rock and the Summit mountain; C1: the "granite with moss" variant lies on top
	-- C2 (spec 04 addenda 1.8/2.0/2.1): Island 2.0 - the land by a noisy outline, the height from Core/Island, the terrain in chunks
	-- by WriteVoxels. The phone draws the terrain in flat color, parts with a texture (devforum 4246362), so all visible stone is
	-- Kenney meshes with the granite variant (rocks.*), the terrain only under the ground, grass, sand and water.
	island2 = {
		enabled = true,
		R0 = 600, -- the mean land radius (a diameter of ~1,200), the outline r = R0 * (1 + noiseAmp * noise(angle))
		noiseAmp = 0.2,
		noiseSeed = 31,
		harmonics = { 2, 3, 5, 7, 11 }, -- the outline noise harmonics, amplitude 1/k
		margin = 40, -- the margin of WriteVoxels chunks beyond the maximum radius
		chunk = 96, -- the terrain chunk size (studs)
		seaLevel = -2, -- the sea level: the land at 0 stands 2 studs above the water (the beach is dry up to the shoreline)
		beach = { start = 0.95, depth = -5, seabedAt = 1.12, seabed = -20, sandFrom = 0.945 }, -- C3: the beach is narrower (frames: a wide gray strip) -- shares of the shore radius: from start the beach slopes gently down, the shoreline is where the height = seaLevel (~0.964); the bottom matches the FillBlock (-20)
		rockSlope = 1.0, steepMaterial = "Grass", -- the slope (the drop per stud) from which the top layer is stone; not Limestone; Rock on the phone - gray facets, so grass + mesh rocks on top
		terrace = { slopeWidth = 24, noise = 6, stairsMargin = 2, stairsSink = 1.2 }, -- a plateau slope instead of a wall (ends before r 203: the egg spots at 200, the Springs sign at 198, the bridge at 206); the stairs in cutouts
		cliffs = { zFace = -334, faceNoise = 6, faceWidth = 10, height = 70, topNoise = 6, halfWidth = 215, edgeSoft = 45, depth = 66, backSlope = 40 },
		-- under the plaza also without tall grass (the stalks grew through the plaza stone); a radius margin of one voxel step 4
		plazaGroundMargin = 3,
		nestGround = "LeafyGrass", -- the nest area without tall grass (knee-high grass hides the eggs and the pile)
		summit = { top = 120, topMaterial = "Grass", topRadius = 38, baseRadius = 104, concave = 1.4, noise = 13, noiseFullAt = 45, ledge = 4, ledgePeriod = 26, ledgePhase = 14, shoulders = { { dx = -100, dz = 40, r = 84, h = 76 }, { dx = 82, dz = 38, r = 78, h = 64 }, { dx = -20, dz = 92, r = 72, h = 52 } } }, -- pass 1 C2: an even cone - now noise 13, ledges every 22 studs, the shoulders larger; the shoulders past the spot meadow_8 (-80, 247) and the path to it
		springs = { y = 4, edgeSoft = 14, sandNear = 26, box = { x1 = -372, x2 = -232, z1 = -130, z2 = 124 }, lagoon = { { x = -298, z = 38, r = 22 } }, lagoonOld = { { x = -300, z = 20, r = 36 }, { x = -338, z = 44, r = 24 }, { x = -296, z = 58, r = 14 } }, lagoonDepth = -4, lagoonRim = 8, waterLevel = 3, edgeNoise = 16, channel = { x = -212, half = 6, rim = 6, z1 = -130, z2 = 170, depth = -4, waterLevel = 0, meander = { amp = 13, period = 130, straight = 16, fadeLen = 30, widthVar = 0.3 } } }, -- the brook with bends, the area edge with noise (spec 04 2.6 items 4-5) -- the lagoon between the rows of spots (z -40 and 80) and past meadow_6 (-260, 0)
		-- C3: zone islands (spec 04 addendum 2.1 item 2): an own noisy outline, hills, a peak; the top and slope material its own. Frost Isle -
		-- snow and ice, opens to an adult Frost (the wall wallX stays). The second island (the elder) and the third - later.
		extra = {
			{ id = "frost", x = 1500, z = 0, R0 = 300, noiseAmp = 0.22, noiseSeed = 41, top = "Snow", steep = "Glacier", beach = "Snow",
				hills = { count = 14, seed = 43, radius = { 20, 40 }, height = { 5, 12 } },
				peak = { dx = -20, dz = 30, top = 110, topRadius = 16, baseRadius = 120, concave = 1.3, noise = 10 } },
		},
		-- C3: stone arches in the sea (spec 04 addendum 2.0 item 2, craft/04 §7.10 series 6): two pillars + a lintel of parts with granite
		-- (parts with a MaterialVariant are visible with a texture on the phone too); they stand across the radius - the glide route along the shore
		arches = {}, -- two arches of parts read as man-made - removed, later an arc of mesh rocks
		-- stone as meshes (DecorLayout.rocks2): the shore, the Cliffs ridge facade, the terrace slope, the sea pillars
		rocks = {
			seed = 37,
			coast = { count = 44, from = 0.955, to = 0.995, height = { 8, 18 }, kinds = { "ph_rock1_4", "ph_rock1_0", "ph_rock1_1", "ph_rock2_6", "ph_rock2_3" } }, -- Poly Haven PBR
			cliffs = { count = 48, rows = 3, rowStep = 20, rowJitter = 12, height = { 16, 34 }, back = 60, ends = 20, backHeight = { 12, 26 }, kinds = { "ph_rock1_4", "ph_rock1_0", "ph_rock1_3", "ph_rock2_6", "ph_rock2_1" },
				-- the facade cladding - a grid of step along x, rows rows (the boulder bottom), height height, protrude of the height outward (DecorLayout)
				clad = { seed = 2210, step = 30, jitter = 10, rows = { 0, 22, 44 }, rowJitter = 8, height = { 30, 44 }, protrude = 0.15, kinds = { "ph_rock1_0", "ph_rock1_1", "ph_rock1_3", "ph_rock1_4", "ph_rock1_5", "ph_rock2_6" } } }, -- pass 1 C2: the cliff_* cubes are removed, rows with jitter; C3: boulders also on the back slope toward the sea (frame X4: a flat gray wall) -- the back 34 -> 60, the ridge ends 20 each
			summit = { count = 90, rFrom = 40, rTo = 112, height = { 12, 28 }, kinds = { "ph_rock1_4", "ph_rock1_1", "ph_rock2_6", "ph_rock2_0" } }, -- ledges on the peak slopes -- 26 -> 90 overlapping rocks (the nature pass, spec 04 2.6 item 1)
			terrace = { count = 30, rFrom = 182, rTo = 204, height = { 6, 13 }, stairsClear = 9, kinds = { "ph_rock1_0", "ph_rock1_3", "ph_rock2_2", "ph_rock2_5" } },
			stacks = { count = 36, chain = { 3, 6 }, chainStep = { 20, 30 }, chainJitter = 12, from = 1.05, to = 1.3, total = { 40, 140 }, pieces = { 3, 4 }, overlap = 0.78, kinds = { "ph_rock1_4", "ph_rock1_1", "ph_rock2_6" }, baseKinds = { "ph_rock1_4", "ph_rock1_0", "ph_rock2_3" }, baseScale = 1.3, taper = 0.2, jitter = 10, skipAngles = { { 150, 215 } }, pines = { "cs_pine_gabe", "cs_ponderosa" }, pineHeight = { 18, 26 } }, -- 36 pillars in chains of chain pieces with a step of chainStep studs along the shore, height 40-140, closer to the shore -- Creator Store pines -- the base wider, the pieces narrow toward the top
		},
	},
	-- C1: own terrain MaterialVariants. The textures - assets_src/terrain_textures (gpt-image-2, a 1,024 tile,
	-- seamlessness/normal/roughness - tools/terrain_textures_post.py), the image ids - assets_textures.json (tools/upload_image.py).
	-- build.py writes the variants into the place file's MaterialService and the <Base>Name overrides; WorldBuilder repeats SetBaseMaterialOverride under pcall.
	-- tint - the terrain material color under the variant. Weak phones draw the terrain WITHOUT textures (a light tint makes the whole
	-- world white), so tint = the real mean color of the texture x 1.2 (tools/terrain_tint_normalize.py, tints.json), and the _v2 color maps
	-- are divided by tint: on strong devices the map x tint = the original texture, on weak ones - a flat plausible color.
	materials = {
		enabled = true,
		variants = {
			{ name = "DN_GraniteMoss", base = "Limestone", texture = "granite_moss_v2", studsPerTile = 44, tint = { 141, 137, 118 } }, -- pass 1: 28 - grain, the cracks were not readable -- the Cliffs rock, the terrace wall, the mountain, the islets
			{ name = "DN_GraniteMossRock", base = "Rock", texture = "granite_moss_v2", studsPerTile = 60, tint = { 141, 137, 118 } }, -- the backdrop
			{ name = "DN_DarkEarth", base = "Ground", texture = "dark_earth_v2", studsPerTile = 14, tint = { 76, 63, 56 } }, -- the paths, the top
			{ name = "DN_Pebbles", base = "Sand", texture = "pebbles_v2", studsPerTile = 9, tint = { 170, 152, 122 } }, -- pass 1 C2: the beach as a gray slab - warmer and lighter (sand with pebbles) -- the beach, the Springs area, the bottom
			{ name = "DN_DryGrass", base = "Grass", texture = "dry_grass_v2", studsPerTile = 16, tint = { 106, 120, 53 } }, -- the glade; the Decoration grass takes the material color: olive, like HTTYD
		},
	},
}

-- the ocean as tiles on the client (Controllers/Ocean; with streaming the terrain water reaches only ~1,400-2,000 studs and
-- the server seaPlane strips do not reach the client) - inside the water square a grid of
-- inner studs (a tile hides while terrain is loaded under it, a check every check s), outside up to outerTo in pieces <= piece;
-- the fog at the edge: the Atmosphere density from the share from to to of the flight limit grows to mist.density
Config.World.ocean = { inner = 600, outerTo = 12000, piece = 2048, check = 2, mist = { from = 0.7, to = 0.985, density = 0.78 } }
-- the "<Zone> Egg" caption only for the zones from labelDistance (studs to the caption); abByUserId - A/B: an even
-- UserId without the caption (Core/Experiments, the Analytics slice "eggLabels"); the shimmer - sparks on every island egg, without text
Config.World.eggMarks = { labelDistance = { Meadow = 28 }, abByUserId = true,
	sparkle = { rate = 4, lifetime = { 0.7, 1.3 }, size = 1.1, speed = { 0.4, 1.2 }, color = { 255, 246, 210 }, lightEmission = 1 } }

-- ---------------------------------------------------------------------------------------------- the light (craft/02 §8)
Config.Lighting = { -- C1: realistic light modeled on HTTYD (spec 04 addendum 2.0 item 1; craft/02 §1: Island Jump, Lighting Outdoors)
	style = "Realistic", -- was Soft (the cartoon look)
	technology = "Future", -- the place file only (build.py); the server tries to repeat it under pcall
	prioritizeQuality = true,
	brightness = 1.7, -- higher values turn any part lighter than ~50% gray white in the sun (the plaza, the steps)
	ambient = { 70, 72, 80 }, -- the shadow: dark, but the ground in the shadow is readable (Island Jump 16 - too dark for a phone)
	outdoorAmbient = { 128, 146, 176 }, -- the sky light, cold
	colorShiftTop = { 255, 236, 205 }, -- warm sun on the lit faces
	envDiffuse = 1, -- sky reflections on PBR materials (the references 1/1)
	envSpecular = 0.2, -- passes 1-3: light plastic reflected the sky into white (0.5 was not enough; the parts were also moved to Slate)
	exposure = -0.15, -- pass 2: minus against the clipping of light parts, the sun/shadow contrast is kept
	globalShadows = true,
	shadowSoftness = 0.2,
	geographicLatitude = 55, -- the sun is low all day: long shadows (Island Jump 78; in HTTYD the sun is low)
	clockTime = 10.5, -- the starting one; then DayCycle drives it (the day 9.5-15.5)
	goldenHourClock = 17.5, -- the golden hour time; by default the day
	sunAngularSize = 12, -- a realistic sun (was 18 cartoonish)
	atmosphere = { density = 0.33, offset = 0.25, color = { 205, 218, 235 }, decay = { 92, 112, 150 }, glare = 0.1, haze = 1.1 }, -- a blue haze in the depth, the water edge is hidden; pass 1: 0.4/1.7 - milk already at 200 studs
	bloom = { intensity = 1, size = 24, threshold = 2 },
	sunRays = { intensity = 0.02, spread = 0.18 },
	colorCorrection = { saturation = 0.1, contrast = 0.08, brightness = 0 }, -- realism, not acid (was 0.24)
	blurMenu = 12,
}

-- ---------------------------------------------------------------------------------------------- budgets (04 §9)
Config.Perf = { partsMax = 8200, -- the part budget: ~8,100 visible (decor x1.8 + stone as meshes, Creator Store models: campfires, lanterns, the pier; the exact number - the World.DecorParts attribute); mesh decor and fences without collisions and shadows
	partsMaxOld = 1500, dragonsMax = 66, emittersMax = 30, pointLightsMax = 26, highlightsMax = 3, memoryMb = 400 } -- C7: the light + campfires 6, lanterns 8, crystals ~3 (only at night, without shadows)

-- ---------------------------------------------------------------------------------------------- the network and protection (10 §4)
-- 1.7-1.8: the loop - "just walk up" (02 §1), the Pick up button only at the island eggs (P23), toasts via Notice
-- the table and incubator radii horizontal and smaller (the table 2.6, the ring 3.0; 6.3 between them): standing on the ring,
-- the player took eggs from the table and they went into the incubator by themselves
-- placeRadius 3.0 -> 3.8 - the incubator bowl has an invisible stop along the rim (r 2.45), the character center no closer than 2.95 (straight on) -
-- 3.57 (sideways on the diagonal); the neighboring zones 7.6 < 8; with the table an intersection - a strip at the table corner (TableEgg1 -> Incubator1)
-- hatchDistance 14, feedDistance 40
-- feedDistance 40 -> 55 - the table with eggs (45.6) and the incubators (~49) are "at the nest" too
-- (Feed / Feed All only at the own dragon or nest, 02 §4)
Config.Loop = { holdSeconds = 0.25, promptDistance = 11, toastSeconds = 2.6, tickSeconds = 1, respawnSeconds = 4,
-- stallFeedDistance - the berries at the Keeper's stall (errand 4 "Buy berries at my stall", Nest.feed + a WorldUI hint)
-- pickRadius 2.6 -> 3.2 - 1 stud from the table the eggs were at 2.84-4.08, taken only point-blank; after
-- the first pickup the other two table eggs disappear (EggSpawner), the "took - placed - took the second" chains in the strip at the bowl are gone
-- tableFade - the two untaken ones fade over 0.5 s, not in the same frame
	collectRadius = 6, placeRadius = 3.8, placeDistance = 10, pickRadius = 3.2, pickDistance = 8, collectEvery = 2.5, hatchDistance = 14, feedDistance = 55, stallFeedDistance = 14, tableFade = 0.5 } -- 02 §1 "just walk up": the radii of collecting the pile, placing an egg, picking up from the table; the call check distances (10 §4: PickEgg <= 8, PlaceEgg <= 10)
-- an egg from the shelf goes into a free incubator by itself when the owner is in his nest (the Base plot), the hands
-- are empty and the bowl has been free for at least freeFor s (for a newcomer after the hatch it does not take the bowl meant for a found egg); on = false - as before
Config.Loop.shelfAuto = { on = true, freeFor = 20 }
-- THE FIRST EGG WITHOUT EXTRA STEPS (newcomers wandered with the egg and did not understand the incubator or Hatch) -
-- while there has been no first hatch, the egg from the hands goes into a free bowl by itself placeAfter s after the pickup, and the ready first egg
-- hatches by itself if the owner is closer than hatchWithin studs to the bowl. on = false - as before (bring it, press Hatch).
-- By itself - only at home (on the own nest plot) and not earlier than afterJoin s after the entry (a returning player with a ready egg
-- does not hatch under the splash screen and the "while you were away" card); fly - s of the egg's arc from the hands into the bowl (the client WorldUI), then the placement
Config.Loop.spawnHome = true -- the player appears in his pen (at the gap, facing the plaza), not at the Keeper; and after Reset
Config.Loop.firstEgg = { on = true, placeAfter = 1, hatchWithin = 60, afterJoin = 10, fly = 0.45 }

Config.RateLimit = { -- calls per second
	PickEgg = 2, PlaceEgg = 2, HatchReady = 2, Feed = 4, SetCompanion = 1, MoveDragon = 2, Release = 1,
	NameDragon = 0.2, Buy = 4, Claim = 2, Ascend = 1, Mount = 2, Dismount = 2, FlightInput = 20, ShopIntent = 1, Treat = 2,
	Analytics = 5, Admin = 1, Perf = 0.2, -- Perf 1.14: a measurement every 15 s
	Setting = 2, -- P37
	Regroup = 0.25, -- the relocation of a stuck companion (the client itself not more often than Config.Dragon.regroup.cooldown)
}
Config.KickAfterTooFastPerMinute = 50

-- ---------------------------------------------------------------------------------------------- analytics (02, 11)
Config.FunnelSteps = { -- the number = the order of the newcomer funnel step
	"spawn", "egg_first_pick", "hatch_first", "coins_first_collect", "glide_first", "egg_second", "feed_first",
	"juvenile_first", "ride_first", "hatch_second", "adult_first", "fly_first", "ascension_first",
	"attack_first", "gloom_guardian_first", "storm_guardian_first", -- combat; the numbers after the old steps (we do not break the funnel order)
}

-- ---------------------------------------------------------------------------------------------- the tutorial (02, 10 §6)
Config.OnboardingStages = { "spawn", "egg_picked", "hatched", "coins", "glided", "egg2", "fed", "rode", "flew", "done" }
Config.HintDelaySeconds = 1 -- the arrows lead constantly (was 10 s and once per step)
-- 1.8 part 2: the newcomer hints (02 §1, P11): a beam from the feet to the target, chevrons of the same arrow, a Highlight only for the time
-- of the hint, a 3D arrow above the target; the timer HintDelaySeconds, once per step
Config.Hints = { pileMin = 5, dayPileMin = 1500, eggRadius = 520, beam = { width0 = 2.0, width1 = 0.3, textureLength = 7, speed = 1, transparency = 0.25, noTextureWidth = 0.9, noTextureTransparency = 0.4 }, -- narrower, more transparent, without a texture - a thin line
	arrow = { size = 4, bob = 1.2, above = 3.5 }, highlight = { fill = { 255, 214, 92 }, fillTransparency = 0.65, outlineTransparency = 0 }, tick = 0.5,
	-- tracer arrows one after another, not a line: a chain of large chevrons along the ground with a dark outline, self-lit,
	-- made of parts (images do not always load on phones), a running shimmer from the player to the target
	trail = { spacing = 5.5, max = 14, width = 3.2, length = 2.0, thickness = 0.3, lift = 1.35, tiltDeg = 38, bob = 0.25, outline = 0.4, pulseSpeed = 5, pulseStep = 0.8, minT = 0.05, maxT = 0.75, refresh = 0.35, moveThreshold = 1.5 } }
	-- the trail floats 1.35 studs above the ground - above the grass tips (in the grass the chevrons sink), the chevrons larger and thicker, tilted toward the camera by 38 degrees, swaying slightly; the grass is not touched.
	-- coinFlight - the coin flight into the counter, 6 icons of 26 px; the menu; the dragon card.
	-- The dragon names (the TextService filter) are visible to others; if moderation asks - false: others see
	-- the element name, the owner - his own (the card from the Store).
	-- renameCooldown - other players see the dragon name, and the Roblox rule (creator-docs chat/guidelines "editable text that can be
	-- used and seen between users must add rate limits of at least 1 minute") requires not more often than once a minute; games without
	-- such a limit are taken down. The name window after a hatch does not pop up during this time
Config.Names = { publicNames = true, renameCooldown = 60 }

Config.UI = { plainText = true, plainStroke = 2.6, -- the Keeper, the step, NextUp, the stage bar - text with an outline without plates
	-- the start in waves - until the first dragon, and in the first session until stage 1 is cleared (but not longer than newbieSeconds of play)
	-- the menu on the left, the Keeper, the pass buttons and the offer cards are hidden; the coins, the egg and one step are visible
	newbie = { on = true, seconds = 480 }, -- until the golden egg is at home or 8 min of play
	coinFlight = { maxIcons = 6, seconds = 0.9, stagger = 0.07, iconPx = 26 }, menu = { blur = 12, buttonHeight = 0.07, squareHeight = 0.09 },
	nameDialog = { autoCloseSeconds = 5, firstHatches = 1, minRarity = "Rare" }, touch = { thumbstickZoneFade = false }, -- the Roblox thumbstick zone highlight at the entry is suppressed
	card = { viewportFov = 40, releaseConfirm = 3 },
	-- the caption above the incubator ring is visible from a camera closer than maxDistance; the round Hatch - only at the
	-- incubator itself (Loop.hatchDistance, like the HUD button and the server); the "hatch" hint arrow hides while the caption is visible
	incubatorGui = { maxDistance = 45 },
	pileGui = { maxDistance = 90 }, -- the same at the coin pile - the arrow does not lie on the coin number
	-- above the ring and the dragon in the world - signs (Ready!, 🍖), the actions - by the bottom
	-- button; true - bring back the round Hatch and Feed buttons in the world
	worldActionButtons = false,
	stepBanner = { y = 0.108, width = 0.46, height = 0.085, doneSeconds = 1, distEvery = 0.3 }, -- P10: the step banner under the coin counter; P34: the distance to the target every distEvery s
	-- the "NEXT" line in place of the step banner when there is no step for quietAfter s (no blinking between steps
	-- for a newcomer); in rotation: the nearest timer timerSeconds, tomorrow's calendar day and the next update (not farther than updateWithin; 21 days - Aurora is visible since 18.10) for
	-- otherSeconds; a tap on the update line - the Roblox event RSVP window
	nextUp = { quietAfter = 3, quietUrgent = 1, timerSeconds = 8, otherSeconds = 4, updateWithin = 21 * 86400, every = 0.5, alpha = 0.25 }, -- quietUrgent - the quiet for the firstborn's urgent growth
	-- one serif "book" font for the interface and the world captions (the choice by the sampler on
	-- P8), the panels dark charcoal with a thin light frame, one book window with colored tabs, the icons - emoji (Open Cloud images
	-- do not reach the phone), the splash screen at the start 3 s
	font = "Fantasy", -- the Enum.Font name (a font sampler: Fantasy is closest to HTTYD and readable small; Antique is narrower, Merriweather heavier); the fallback FredokaOne
	panel = { color = { 42, 42, 46 }, light = { 58, 58, 64 }, border = { 118, 108, 92 }, text = { 240, 232, 214 } },
	tabs = { dragons = { 196, 140, 40 }, settings = { 92, 98, 120 }, shop = { 40, 130, 80 }, quests = { 200, 100, 30 }, index = { 110, 70, 160 } },
	-- on a low screen (< smallBelow px) the book is wider and taller - otherwise the shop card row did not fit
	book = { width = 0.76, height = 0.84, tabHeight = 0.15, smallBelow = 450, smallWidth = 0.88, smallHeight = 0.95 },
	-- minSeconds - not earlier, and "Tap to skip" at the same time; holdSeconds - without a tap the screen holds until
	-- this many s since the show pass (two tips of tipSeconds each); not longer than 3 s in total, "Tap to skip" from skipAfter
	splash = { minSeconds = 3, holdSeconds = 3, skipAfter = 1.5, tipSeconds = 3, fade = 0.8, stars = 36, clouds = 6 },
	-- a 3D hatchling from the game instead of a drawing from frames; the server puts a copy
	-- into ReplicatedStorage.LoadingDragon; size - how many times larger than the drawing frame, wait - how many seconds the splash waits for the model
	splashDragon = { element = "ember", stage = 0, size = 2.8, wait = 12 },
	-- the plate in the Roblox button row at the top center, px: top from the screen top, slide - the slide-in from above, rim - the rim
	phaseBanner = { seconds = 2.5, at = 0.45, top = 7, width = 150, height = 44, slide = 18, rim = 2, transparency = 0.22, rimTransparency = 0.55 },
	-- the world captions fade while they lie on the HUD or the Keeper's bubble; margin - the margin before fading, clear - before the return
	declutter = { tick = 0.2, fade = 0.25, margin = 4, clear = 12 },
	-- P16/P32 (HTTYD): the day phase change announcement on a cloud; at - the share of the phase before the show
	plaque = { color = { 52, 88, 160 }, height = 0.11, aspect = 1 }, -- HUD plates of one style: an icon + a word (02 §6)
	-- 1.9 (02 §4, 09 §4): the movement buttons to the right of the jump - 70 px when the smaller screen side < 500, otherwise 120; Up/Down in flight, Dismount when riding
	-- P35: the world timers above the jump button (above the Up button's place, so that riding does not run over the flight buttons); the sizes -
	-- shares of the flight button (mobile.small/large); the place for the storm timer (2.7) is reserved
	-- the day timer is off - our night does not change the player's actions; switch on together with
	-- the storm 2.7 / the night mechanics
	worldTimers = { tick = 0.25, height = 0.42, width = 1.75, gap = 6, dayNight = false },
	-- P33: own buttons in the Roblox button row at the top left (dark round ones, like the system ones)
	topbar = { size = 44, gap = 12, left = 9, bottom = 2, color = { 18, 18, 21 }, transparency = 0.3 }, -- left/bottom - next to the Roblox top bar buttons (the circles 12-56 of 58, a gap of ~9)
	mobile = { small = 70, large = 120, threshold = 500, gap = 10 } }

-- ---------------------------------------------------------------------------------------------- appearance: the appearance showcase (07 add. 2.6)
-- A color preset for one dragon (07 §2 no. 11, 06 §8): tint - the color, element - this element only. The dragon meshes have the texture
-- in TextureID (the part color does not change it), so the color is drawn by the client (Controllers/Looks) with a Highlight: a fill with transparency
-- fill, no outline, not more than max nearest to the camera within distance studs (the Highlight budget 04 §9), a recount every every s; in the card
-- frame - the frame's ImageColor3 (a share of the viewport color). If the mesh has a SurfaceAppearance - the server paints its Color, no highlight needed.
Config.Looks = {
	presetOrder = { "sunset", "solstice", "cinder" },
	presets = {
		sunset = { tint = { 255, 140, 70 } },
		solstice = { tint = { 255, 206, 96 }, element = "dusk" },
		cinder = { tint = { 150, 62, 44 }, element = "ember" }, -- the embers preset of the Dragon of the Week Cinder
	},
	highlight = { max = 2, distance = 90, every = 0.5, fill = 0.62, viewport = 0.45 },
	-- the flight trail (Trail_Comet_149): a ribbon from the tail tip while a rider on an adult or an elder is in the air (no ground or
	-- water under the belly closer than minAir studs); the width - a share of the dragon height, narrows toward the end to a share widthEnd; the color - from the ribbon start (head) to the end
	trailOrder = { "tidal", "comet" }, -- whoever has both - the new Tidal (no trail choice: we save it for Monday)
	trailEvery = 0.25,
	trails = {
		comet = { head = { 255, 246, 210 }, tail = { 110, 180, 255 }, transparency = { 0.1, 1 }, widthOfHeight = 0.14, widthEnd = 0.1, lifetime = 0.8, lightEmission = 1, minAir = 6 },
		tidal = { head = { 214, 252, 255 }, tail = { 30, 168, 186 }, transparency = { 0.15, 1 }, widthOfHeight = 0.16, widthEnd = 0.12, lifetime = 0.9, lightEmission = 0.8, minAir = 6 }, -- (09 §3 update 3)
	},
	-- the nest skins (07 §2 no. 3, no. 11, no. 13): the color and material by part roles (Core/Looks.nestRole); flag - the skin is given by a pass, not a flag
	-- nestSkins (Gilded - VIP). The priority if the player did not choose himself: royal > gilded > lagoon (the most expensive first). The materials - without
	-- MaterialService overrides (Limestone, Rock, Ground, Sand, Grass are taken by the terrain variants)
	nestRoles = { "fence", "fenceDark", "post", "sign", "stone", "wood", "woodDark", "bowl" }, -- + bowl - the incubator bowls
	nestSkinOrder = { "royal", "night", "gilded", "lagoon" },
	nestSkins = {
		lagoon = {
			colors = { fence = { 62, 158, 168 }, fenceDark = { 30, 88, 104 }, post = { 196, 188, 168 }, sign = { 48, 128, 146 }, stone = { 150, 206, 200 }, wood = { 80, 150, 160 }, woodDark = { 36, 92, 108 }, bowl = { 110, 220, 210 } },
			materials = { fence = "Wood", fenceDark = "Wood", post = "Marble", sign = "WoodPlanks", stone = "Marble", wood = "WoodPlanks", woodDark = "Wood" },
		},
		gilded = {
			flag = "vip",
			-- gold as Metal/Foil/Marble reads dark olive in the game light; only SmoothPlastic with orange gold is readable (255,176,36 ->
			-- 193,176,12). The posts and the sign - light gold, the crossbars darker, the table - honey boards, the bowl - a golden tint of the texture
			colors = { fence = { 255, 164, 40 }, fenceDark = { 226, 126, 26 }, post = { 255, 164, 40 }, sign = { 255, 164, 40 }, stone = { 250, 224, 156 }, wood = { 222, 150, 52 }, woodDark = { 160, 100, 36 }, bowl = { 255, 184, 70 } },
			materials = { fence = "SmoothPlastic", fenceDark = "SmoothPlastic", post = "SmoothPlastic", sign = "SmoothPlastic", stone = "SmoothPlastic", wood = "WoodPlanks", woodDark = "Wood" },
		},
		night = { -- Night Sky - dark blue with silver
			colors = { fence = { 44, 54, 104 }, fenceDark = { 24, 28, 62 }, post = { 214, 222, 242 }, sign = { 56, 66, 128 }, stone = { 150, 160, 204 }, wood = { 50, 60, 112 }, woodDark = { 28, 32, 70 }, bowl = { 110, 126, 200 } },
			materials = { fence = "Wood", fenceDark = "Wood", post = "SmoothPlastic", sign = "WoodPlanks", stone = "Marble", wood = "WoodPlanks", woodDark = "Wood" }, -- the silver of the posts SmoothPlastic (Metal darkens)
		},
		royal = {
			colors = { fence = { 92, 54, 138 }, fenceDark = { 255, 164, 40 }, post = { 255, 164, 40 }, sign = { 92, 54, 138 }, stone = { 204, 196, 216 }, wood = { 112, 66, 150 }, woodDark = { 64, 38, 92 }, bowl = { 196, 160, 230 } },
			materials = { fence = "Wood", fenceDark = "SmoothPlastic", post = "SmoothPlastic", sign = "Fabric", stone = "Marble", wood = "WoodPlanks", woodDark = "Wood" }, -- the gold of the posts as in Gilded
		},
	},
	-- the nest aura (Bundle): one spark emitter above the owner's nest (the emitter budget 04 §9: not more than 6 per server); area - a share of the lot,
	-- height - studs above the floor, rise - the upward acceleration
	auraOrder = { "royal" },
	auras = {
		royal = { colors = { { 255, 214, 110 }, { 186, 128, 255 } }, rate = 5, lifetime = { 3, 5 }, size = 0.5, speed = { 0.4, 1 }, rise = 0.4, height = 2.5, area = 0.7, lightEmission = 1 },
	},
	-- above the head (a server BillboardGui, visible to all, to oneself - if showToSelf): the VIP tag (the pass) and the title (Bundle); above - studs above
	-- the head (above the Roblox name); width and rowHeight - px; declutterRank - below the world captions (Controllers/Declutter)
	-- the nest tint for Ascension - 6 around the element circle (step 1 -> [1], 7 -> [1] again): the fence and the sign by roles
	-- as in nestSkins, the material as before; only without a bought skin (the skin takes priority)
	ascTints = {
		{ fence = { 192, 58, 46 }, fenceDark = { 112, 32, 28 }, sign = { 166, 52, 42 } }, -- ember (crimson, so it differs from the classic 150,100,70)
		{ fence = { 120, 176, 216 }, fenceDark = { 62, 104, 140 }, sign = { 104, 156, 196 } }, -- frost
		{ fence = { 112, 168, 84 }, fenceDark = { 60, 104, 48 }, sign = { 96, 146, 72 } }, -- moss
		{ fence = { 72, 172, 172 }, fenceDark = { 36, 104, 112 }, sign = { 60, 150, 154 } }, -- tide
		{ fence = { 150, 120, 214 }, fenceDark = { 88, 66, 144 }, sign = { 128, 100, 190 } }, -- storm
		{ fence = { 128, 84, 160 }, fenceDark = { 70, 44, 96 }, sign = { 110, 72, 140 } }, -- dusk
	},
	tag = { maxDistance = 60, above = 3.4, width = 120, rowHeight = 18, vip = { 255, 204, 64 }, title = { 214, 196, 255 }, ascended = { 255, 178, 96 }, declutterRank = 0.5, showToSelf = false, titleOrder = { "nestLord" } },
	-- the rider's scarf (Starter Pack): a cylinder collar on the neck (the height and diameter - shares of the torso height and width) and a tail on the chest
	-- (tail: the width - a share of the torso width, the length - a share of the torso height, the thickness in studs; tailX - a sideways shift, a share of the width), fringe at the bottom
	scarf = { color = { 196, 58, 48 }, fringe = { 240, 200, 90 }, collarHeight = 0.26, collarWidth = 0.64, collarLift = 0.02, tail = { 0.17, 0.62, 0.12 }, tailX = 0.17, tailTiltDeg = 10, fringeHeight = 0.12 },
}
-- appearance: the Remote SetLook - calls per second
Config.RateLimit.SetLook = 2
Config.RateLimit.Code = 1 -- 2.9: the code of the week
Config.Shop.impressionEvery = 120 -- an impression of one item into the Shop funnel not more than once per N s (the client)
-- drawn reward icons instead of emoji - an egg of the zone color (rgb) and a lantern (the glass, the caps)
Config.UI.eggIcon = { Meadow = { 132, 204, 108 }, Cliffs = { 168, 150, 214 }, Springs = { 84, 200, 204 }, Summit = { 196, 228, 255 }, Rare = { 247, 204, 70 }, Epic = { 176, 104, 236 } }
Config.UI.lanternIcon = { glow = { 255, 196, 92 }, cap = { 92, 62, 40 } }
-- the pass buttons to the right of the coin pill in a row (Core/PassChips
-- Controllers/PassChips): x2 Coins, Auto Collect; a tap - the pass card. minPx - the height not less (the pill on a phone 812x375 ~29 px, a finger 40+),
-- aspect - the width = the height * aspect, gap - the gap in px; playerListW - the width of the Roblox player list zone at the top right on PC,
-- no buttons are placed there. on = false - no buttons at all
Config.UI.passChips = {
	on = true,
	list = { { key = "X2Coins_299", word = "x2" }, { key = "AutoCollect_149", word = "auto" } },
	minPx = 40,
	aspect = 1.9,
	gap = 8,
	playerListW = 260,
}
-- the hatch scene, seconds from the hatch event on the client (Core/HatchFx picks the kind).
-- full - the first hatches and Rare+: the camera, Blur, the HUD hidden until camOutAt; the egg rocks with a growing amplitude, the core flares up,
-- at crackAt a flash, element sparks, the shell flies apart; the hatchling from a point at popAt. short - Common/Uncommon from the 3rd hatch and
-- Common at the 2nd (03 §2 "1.5 s", 02 §2 line 3:30): without the camera and Blur. legend - Legendary+ also seconds of the sky and the element light with
-- confetti WITHOUT taking the control away (02 §2: not longer than 5 s); Mythic - the same to the whole server, the egg rises by mythicLift.
-- The server keeps the egg in the bowl for holdSeconds (the client removes the copy) and does not put a new one into this bowl while the scene runs
Config.UI.hatchScene = {
	full = { camIn = 0.5, shakeFrom = 0.3, crackAt = 1.1, popAt = 1.2, bannerAt = 1.4, camOutAt = 2.6, total = 2.9 },
	short = { shakeFrom = 0, crackAt = 0.45, popAt = 0.5, bannerAt = 0.6, total = 1.5 },
	shake = { degFrom = 1, degTo = 18, hz = 9 },
	mythicLift = 3,
	core = { transparency = 0, grow = 1.25, light = 4, range = 14 },
	shards = { count = 12, speed = { 7, 13 }, up = 7, gravity = 50, seconds = 0.9, size = { 0.35, 0.8 } },
	sparks = { full = 40, short = 16 },
	-- the pillar from above studs above the bowl (a solid one from the ground covered the hatchling), the confetti smaller and lower (it reached the camera)
	-- fade - the fading of the sky and the pillar at the end; the name window for Legendary+ opens with the start of the fading (P8 frame: its darkening
	-- covered the celebration for 2.9 s)
	legend = { seconds = 6.5, fade = 1.2, tint = 0.3, brightness = 0.05, saturation = 0.25, pillar = { height = 90, width = 2, transparency = 0.7, above = 5 },
		confetti = { count = 48, seconds = 3, speed = { 11, 18 }, spread = 0.35, fall = 5, size = { 0.34, 0.05, 0.22 } } },
	holdSeconds = 1.5,
	-- the full scene camera - to the side of the line player -> bowl (angles, degrees from it; the first angle without an obstruction on the ray
	-- from the egg - the character, the table), depth of field instead of Blur 12 (Blur blurred the egg itself too): the background blurred, the egg in focus
	-- angles: first "the egg ahead, the player behind it" (150..180), then from the side; an angle is good if the ray from the egg is clear and the character is no closer than
	-- clear studs to the line camera -> egg and to the camera itself
	camera = { distance = 8, height = 3.5, lookUp = 1.2, clear = 2.2, angles = { 150, -150, 180, 120, -120, 90, -90, 40, -40, 0 } },
	dof = { far = 0.7, near = 0.1, radius = 4 },
	flash = { full = 5, short = 3.5, seconds = 0.4, transparency = 0.25 },
	-- foreign banners (an errand, the Index) wait for the hatch outcome: the banners until bannerAt + bannerHold, the toasts until the end of the scene
	bannerHold = 3,
}

-- protection against teleport and speed on foot
-- (Services/AntiCheat). The character position is sent by the client; the server remembers the last honest point and lets through only what
-- an honest player could walk: running 16, gliding 40, the noStand push 26, the updraft 30, a jump ~53 studs/s - with a margin. The margin
-- slack - a "piggy bank" of studs: a dash spends it, slow walking refills it, so a long distance faster than maxH is impossible.
-- Dishonest - for the distance checks (Nest.rootPos) the honest point stays, the character is returned to it, the event anticheat_teleport.
-- Studio: by default only counts the violations (P8 probes move the character themselves); the probe cheat_check enables enforce via
-- ServerStorage.AntiCheatDebug. Riding (any Seat) is not checked: the flight is checked by Movement (flight.maxSpeedCheck)
Config.AntiCheat = {
	on = true,
	studioEnforce = false,
	tick = 0.25, -- s between checks of all players (plus a check at every Nest.rootPos)
	maxH = 60, -- studs/s horizontally (gliding 40 x 1.5)
	maxUp = 70, -- studs/s upward (a jump ~53, the updraft 30); downward - no limit (falling)
	slack = 24, -- studs of the "piggy bank" above the speed: network jerks, pushes, leaving the updraft
	grace = 1.5, -- s after a relocation by the server (AntiCheat.moved): the client's return to the old point does not count as a violation
	bounceRadius = 10, -- studs: the "old point" for grace
	spawnSettle = 0.6, -- s after the character appears: the position is not trusted (the engine places it on the SpawnLocation)
	spawnRadius = 40, -- studs from the SpawnLocation: where the character honestly appears; farther - a relocation to the spawn and a violation
	seatSlack = 40, -- studs above the path when mounting (an adult dragon's saddle is higher and farther than the character root)
	recheck = 0.05, -- s: within a frame pos returns the previous computation (several services call it)
	maxSpin = 40, -- rad/s of the character root: above - a spin-up (fling); honest - single digits
	groundProbe = 9, -- studs down from the root (the feet ~3 below the root, a jump ~7 above the ground)
	groundBox = { 3.5, 1, 3.5 }, -- the box (X, Y, Z studs) we search the ground with (the character ~2 studs: a cliff edge under one foot - ground)
	colliderEvery = 20, -- s: the index of colliders without CanQuery (steps, rocks) refreshes not more often
	updraftMargin = 12, -- studs around the updraft pillar (and twice above its top): the rise there is honest
	airMax = 2.5, -- s in the air after which a descent is required
	minSink = 4, -- studs/s of descent in the air (gliding 8, falling more; hovering and flight - around 0)
	jumpGrace = 1.0, -- s: a jump (~0.6 s in the air) does not reset the run window and does not require a descent
	groundWindow = 2, -- s: the window of the mean running speed on the ground
	groundAvgMax = 30, -- studs/s of the mean speed on the ground (running 16, a push off a dragon 26 for fractions of a second); was 22 - rollbacks at landing after a glide
	landGrace = 2.5, -- s after touching the ground after a long flight - the run window does not start
	promptSlack = 4, -- studs above the hint's MaxActivationDistance / the touch radius
	companionMaxSpin = 30, -- rad/s of the companion on the leash: above - a spin-up
	companionMaxSpeed = 120, -- studs/s of the companion on the leash horizontally (the leash 45): above - a teleport/speed-up
	companionHold = 5, -- s of the server owning the companion after a violation
	scriptGuard = true, -- foreign scripts in Workspace outside characters are removed
	rates = { egg = 40, coin = 60 }, -- pickups of eggs / path coins per rateWindow: more - the mark anticheat_rate (not a punishment)
	dropEvents = { "State", "Notice", "FlightInput", "CombatFx" }, -- client -> server events without a handler: what is sent is discarded
	rateWindow = 600,
	logEvery = 10, -- an analytics event on the player's 1st, 11th, 21st... violation per session
}
-- new content does not devalue the old dragons ("a small inflation, not x2-x3").
-- The check - tests/inflation_spec.luau. Raise the threshold only together with the balance spec
Config.Balance.inflation = {
	maxEventVariantMult = 1.5, -- the multiplier of an update variant (glacier, pearl...) not higher; and always not higher than shiny
	ceilingGrowthMax = 1.25, -- the income ceiling of one dragon (a Mythic Elder, all traits) grows per update not more than x1.25
	rarities = 6, -- no rarities above Mythic are introduced
}
-- the Remote Analytics events from the client - the server repeats the client's limits (beyond them it silently discards)
Config.Analytics.clientEvery = { ui = 0.5, shop_open = 1, invite = 5, invite_shown = 5, rsvp_prompt = 5, rsvp_going = 5, fav_prompt = 30, fav_done = 30, notify_prompt = 30, notify_closed = 30, tomorrow = 1 } -- s between events of one kind; offer_impression - per SKU; RSVP
-- the Roblox "favorite" window once per account lifetime - after the first flight, delay s after
-- the player got off the dragon; without a reward (Core/Favorite, Controllers/Favorite)
-- the "calendar day is ready" notification (Core/Notify). On leave the game writes the queue store[userId] = {due, day, gift,
-- dragon}, on entry removes it; the VPS sends once an hour (tools/notify_send.py, Open Cloud, the text - a Creator Hub string). on = false -
-- the queue is not written and the consent window is not shown. afterHours - not earlier than this many hours after the leave (and not before midnight UTC).
Config.Notify = { on = true, store = "NotifyQueue_v1", afterHours = 20, prompt = true, closeWait = 15, rejoinRemove = 30 } -- closeWait: s of BindToClose on the queue write; rejoinRemove: s until the repeated removal after the entry
-- the asking and promotional windows (notifications, "tomorrow", "favorite", the invite) -
-- only when idle (Controllers/Quiet): idleFor - s standing still for strict quiet, speed - studs/s "stands", strictFor - s of strict
-- waiting, then soft (not busy: no egg in the hands, no raid, saddle, flight, combat, hatch, banner for bannerGap s, window).
-- strictAlways - a request only standing still for idleFor s (no soft mode); askGap - between any two requests not less than N s (one at a time)
Config.Quiet = { idleFor = 3, speed = 2, strictFor = 60, bannerGap = 1, strictAlways = true, askGap = 45 }
Config.FavPrompt = { on = true, delay = 12, goalSeconds = 5, moment = "glow" } -- the favorite window and the like banner - when the golden egg has landed on the stand (day 1, the peak), after delay s, standing still; goalSeconds - the like goal banner after the window (Config.LiveOps.likeGoal)
Config.Analytics.impressionServerEvery = 60 -- s: one SKU per player not more often (the client - Config.Shop.impressionEvery 120)


-- ---------------------------------------------------------------------------------------------- combat (spec 19)
-- the companion dragon hits the Gloom with the breath of its element. The power = the dragon's income
-- (Economy.dragonIncome) x (1 + ascension) x fedMult while fed, + nestShare of the income of the other nest dragons (Core/Combat.power).
-- Every player has his own arenas: the meadow under the ledge of his nest (stages 1-5) and the sky above it at the islet height (6-10, flight only).
-- stages: n enemies x hp; guardian - one guard with a timer of seconds; sky - the sky arena. Ordinary stages cannot be lost.
Config.Combat = {
	-- the hunt in the sky only from this profile day (day 1 = the creation day), so a newcomer can simply fly around first; on the ground the ambushes and the hunt as they were
	skyFromDay = 3,
	-- the Gloom light x3 in brightness and range + a Highlight outline (otherwise it blends with the dusk);
	-- a neon violet shell over the mesh (shell: a copy of the parts x1.06, Neon, transparency 0.45) and glowing smoke (smokeLight)
	visibility = { lightMult = 3, rangeMult = 3, highlight = true, fillTransparency = 0.75, outlineTransparency = 0.1,
		shell = true, shellColor = { 165, 85, 255 }, shellTransparency = 0.45, shellScale = 1.06, smokeLight = 0.9 },
	on = true,
	breath = {
		cooldown = 0.5, -- s between hits on the client (the button and the auto attack)
		serverCooldown = 0.42, -- the server accepts not more often (a margin for the network)
		range = 45, -- studs: the client's auto aim
		showRange = 55, -- the BREATH/AUTO buttons are visible only if the Gloom is closer (was
		-- arena.activeDistance 160 - the button lit with a wave far below under the ledge, the hit went nowhere)
		serverRange = 60, -- the server: from the character root to the enemy (a margin for latency)
		coneDeg = 70, -- the auto aim: first the nearest in the cone in front of the camera, otherwise the nearest within the radius
		flySeconds = 0.24, -- the flight of the breath projectile to the target (the client); 0.18 -> 0.24 - the blob with a trail has time to be seen
		-- :
		-- an own animated flame flipbook 4x4 (assets_fx.json, runs/roblox_breath_fx_2026-10-26/gen_flame.py), tinted with the element
		-- color; 0 - the old Roblox particle puffs. The stream: streamRate particles/s for streamSeconds on top of the first puff
		flameTex = 79050449058949,
		streamRate = 80,
		streamSeconds = 0.28,
	},
	power = { fedMult = 2, nestShare = 0.10 },
	-- the breath color = the element glow tone (spec 20 "Living Light" §1, agreed with the glow session: light is the weapon against the Gloom)
	glow = { ember = { 255, 150, 60 }, frost = { 170, 230, 255 }, moss = { 160, 255, 120 }, tide = { 80, 240, 230 }, storm = { 255, 230, 109 }, dusk = { 150, 140, 255 } },
	arena = {
		meadowR = 205, -- studs from the island center along the axis of the own nest (the meadow under the terrace ledge, r 170)
		skyR = 230, skyY = 110, -- the sky above the meadow, at the islet height (Config.World.islets yMin 95)
		spread = 22, -- the enemy spread from the arena center
		hover = { 4, 7 }, -- the enemy height above the ground (the meadow)
		activeDistance = 160, -- the wave lives while the player is closer (studs, horizontally for the meadow, in 3D for the sky)
		idleDespawn = 30, -- s away - the wave is removed (it reappears fresh)
		nextDelay = 2.5, -- s between waves
		-- the meadow of nest 4 (axis 180) - the brook bed at Springs (x -212): the arena is shifted 30 degrees toward the stairs 4-5 and closer (a gap of 63)
		shift = { [4] = { angle = 30, r = 185 } },
	},
	stages = {
		{ n = 3, hp = 2, kind = "shardling" },
		{ n = 4, hp = 4, kind = "shardling" },
		{ n = 5, hp = 15, kind = "hound" },
		{ n = 6, hp = 30, kind = "hound" },
		{ guardian = true, hp = 700, seconds = 150, name = "Gloom Warden", kind = "warden" }, -- a teen without feeding did not beat 1000 (stuns in the circle) - softer for the first "wow"
		{ n = 6, hp = 150, sky = true, kind = "shardling" },
		{ n = 7, hp = 300, sky = true, kind = "hound" },
		{ n = 8, hp = 600, sky = true, kind = "shardling" },
		{ n = 9, hp = 1200, sky = true, kind = "hound" },
		{ guardian = true, hp = 40000, seconds = 120, sky = true, name = "Storm Gloom", kind = "warden" },
	},
	rewards = {
		coins = { 20, 40, 80, 150 }, -- stages 1-4
		minutes = { [6] = 3, [7] = 4, [8] = 5, [9] = 6 }, -- stages 6-9: minutes of income (the floor Config.Quests.minMinutesReward)
		guardian = { [5] = { minutes = 5, egg = "Cliffs" }, [10] = { minutes = 10, egg = "Summit", minRarity = "Rare" } },
		replayShare = 0.5, -- a replay of a cleared stage (after the 4th on the meadow, after the 9th in the sky) - a share of the reward
		-- :
		-- a replay not more than replayCapSeconds of the nest income (but not less than replayMinCoins)
		replayCapSeconds = 45,
		replayMinCoins = 10,
		helperShare = 0.25, -- a foreign wave: coins to the helper if his damage >= helperMinShare of the wave health
		helperMinShare = 0.1,
	},
	enemy = {
		speed = 3, -- studs/s: the drift toward the nearest player
		tick = 0.2, -- s: the movement step on the server
		touch = 5, -- studs: a Gloom touch
		touchMute = 1, -- s: the Gloom touched - the breath goes out (a hit is not accepted)
		standoff = 10, -- studs: the Gloom circles at this distance from the player instead of sticking
		touchEvery = 4, -- s: not more than one touch of the player (by any Gloom)
		maxPerServer = 60,
		color = { 70, 40, 104 }, eyes = { 255, 214, 92 }, smoke = { 92, 58, 130 },
		size = { 3.4, 4.2 }, -- the diameter of a small Gloom (stages 1-2 / further)
	},
	guardianFx = {
		size = 15, -- the guard diameter
		pulseEvery = 8, warn = 1.5, radius = 18, stun = 2, -- the pulse: a circle on the ground for warn s, whoever is inside - the breath goes out for stun s
		retry = 60, -- s after a loss (the timer ran out) until a new attempt; 30 -> 60, the guard comes only to the strong (hunt.guardianMaxSec)
	},
	-- the enemies - 3D models of one family with the stone guard (concepts
	-- runs/roblox_gloom_concepts_2026-10-25: minion_C_shardling, minion_B_hound, warden_A_stone_beast -> TRELLIS -> GLB -> Model).
	-- id = 0 - no model yet: a fallback figure of parts. height - the model height in studs (ModelLibrary normalizes to 1 stud)
	models = {
		-- the same models, simplified 10-12 k -> 4,500 triangles with the same texture (*_v4_lp
		-- runs/roblox_gloom_lowpoly_2026-10-26/lowpoly.py); up to 9 enemies per player - a phone
		shardling = { id = 99819876318987, height = 4.6, glow = { 150, 80, 230 } }, -- minion_C_shardling_v4_lp (assets_gloom.json)
		hound = { id = 109761560514715, height = 5.2, glow = { 150, 80, 230 } }, -- minion_B_hound_v4_lp
		warden = { id = 123508509837902, height = 17, glow = { 170, 90, 255 } }, -- warden_A_stone_beast_v4_lp
	},
	-- the attacks (visible combat): the hound jumps at the player, the shardling shoots a slow blob; the hit spot is visible in advance (warn s)
	attack = {
		hound = { every = { 3.5, 5.5 }, range = 24, warn = 0.7, dash = 0.35, hitRadius = 5, mute = 1 },
		shardling = { every = { 4, 6.5 }, range = 32, warn = 0.4, speed = 22, hitRadius = 3.5, mute = 1 },
		knockback = 1.6, -- studs: the enemy's knockback from a hit
		calmStages = 2, -- stages 1..calmStages without attacks and touches - the hatchling learns to hit without punishment
	},
	-- a stage 1 Gloom comes to the newcomer by itself afterHatch s after the companion hatches
	-- (the hatch ~4 s + the hatchling sits 2.4 s + the jump onto the shoulder), not earlier than afterJoin s after the entry (a returning player does not meet it on
	-- the plaza in the first second); ahead - studs in front of the player
	-- near - studs: a distant untouched stage 1 wave (the arena under the ledge) moves to the player, a near one stays
	ambush = { afterHatch = 40, afterJoin = 12, ahead = 14, near = 40 }, -- "the first attack with the hatchling is a bit early, push it a little later": 10 -> 40 s after the hatch (after the coins and the ledge, before the teen)
	-- THE HUNT - a wave comes to the player gap s after the previous one
	-- (cleared or gone), not earlier than firstAfterJoin s after the entry; warn s ahead - "The Gloom is coming!" and tense music; the enemies
	-- appear in a ring of ring studs around and run to the player at speed rush (studs/s), having run up - the usual drift;
	-- rush 8 (the server tick is 0.2 s - bigger steps jerk on a phone).
	-- The hunt comes in a PAUSE, not into a task (Core/Combat.huntReady). new - a newcomer (the first session, has not flown yet), old - the rest:
	-- gapMin s of quiet after the previous wave (or the entry); it is time - idle s without progress OR gapMax s since the previous (the fight finds you itself, even
	-- if the player is busy with a hold task); hold - a task in hand: carrying an egg, the companion's growth in < grow s, the "mount / take off" step and ride /
	-- fly s after the first ride / the first flight, the incubator ready in < hatch s; afterBusy s after closing a menu / scene;
	-- the stage by power (Core/Combat.huntStage): the expected wave seconds = health / (damage x hitsPerSec) not more than maxFightSec, the guard
	-- not more than guardianMaxSec, otherwise a replay of the last cleared one (not more often than gapMax, only in a pause) and the line "grow / feed";
	-- after the guard on the ground a replay not more often than replayGap; a replay is short - not longer than replayMaxSec; a task in hand holds the replay not longer than
	-- 2 x its interval; cap - not more waves per window s; share - the share of combat seconds per window > max -> gapMin x2. The sky 100:
	-- a fed adult Common takes st. 9 in 90 s, a hungry one - the line "feed"; after st. 9 - "Storm Gloom tomorrow"
	hunt = {
		on = true, firstAfterJoin = 20, ring = { 36, 46 }, rush = 8, warn = 2,
		gapMin = { new = 30, old = 20 }, gapMax = { new = 60, old = 45 }, idle = { new = 12, old = 8 }, afterBusy = 8,
		hold = { grow = 12, ride = 30, fly = 40, hatch = 10 },
		growHint = 60, -- s: the companion grows up sooner - after a win the hint "grow", not "feed" (the firstborn - a teen in 1 min)
		hitsPerSec = 2, maxFightSec = { new = 25, old = 40, sky = 100 }, guardianMaxSec = 40, replayGap = 90, replayMaxSec = 30,
		cap = { new = 6, old = 8, window = 300 }, share = { max = 0.5, window = 180 },
	},
	preloadTimeout = 20, -- s after the server start - combat switches on even if the Gloom model did not load
	busyMax = 180, -- s - a "menu open" (UiBusy) older than this does not hold the ambushes (the client did not send "closed")
	-- after s without progress (Combat.progressKey: dragons
	-- stages, eggs, onboarding, the Keeper, combat; coins do not count) and no own wave - the Gloom comes to the player; not more often than every s.
	-- The newcomers' leaves (from the profiles): waiting for the teen - ~the 96th s, waiting for the adult - by 4:00-7:00, after the first flight there is no goal.
	-- flyHeight - studs above the ground when riding = "flies" (a sky wave around if guardian I is done); spawnClear - not at the spawn plaza
	bored = { after = 20, every = 90, afterJoin = 15, ahead = 16, flyHeight = 15, spawnClear = 45 },
	autoForGroup = true, -- Auto Breath free for the group members (Config.Rewards.freeGift.groupId)
	-- focusRange / focusHold: the Gloom closer than focusRange studs - the combat focus (HUD.setFocus hides the Keeper, the step banner,
	-- the cards, the captions and "Pick up"), after the Gloom leaves - focusHold s more
	-- autoFromStage: the AUTO button - after this many cleared stages
	-- musicHold: s after the fight the combat music still plays (it does not jump between hunt waves);
	-- after a cleared wave it does not hold - the fight is closed by the win phrase (Sounds.fightWin)
	-- pointAfter: the own Gloom within breath reach, and the player does not breathe for pointAfter s (not stunned) and AUTO is off - a yellow arrow above BREATH;
	-- pointAfterOld - after autoFromStage cleared stages (an experienced player presses anyway - less often)
	ui = { buttonPx = 76, minPx = 56, gap = 10, numberRise = 3.5, numberSeconds = 0.9, barWidth = 280, focusRange = 90, focusHold = 4, autoFromStage = 2, musicHold = 15, pointAfter = 2, pointAfterOld = 4 },
}
Config.RateLimit.Breath = 5 -- a breath hit; the client not more than 2/s, the server cuts by Combat.breath.serverCooldown

-- "Living Light": masks A by stage, the SurfaceAppearance templates are baked in Studio - ReplicatedStorage.GlowTemplates;
-- Controllers/Glow lights only dragons with the Glow attribute (Services/GlowEgg). dayFloor - the share of glow by day for the special dragon.
-- egg - the glowing egg: after the first flight on the islet nearest to the nest (tier 1), the element, the rarity, the incubation (s), the light beam.
-- ---------------------------------------------------------------------------------------------- the egg raid
-- The egg raid = the verb of the whole game. The shared Gloom nests (Services/Raid):
-- ring 0 - three spots on the plaza rim in the odd wedges between the plots (on foot from 0:30), ring 1 - all the meadow egg spots (riding from
-- the first ride), ring 2 - the cliff and bath spots (by flight from the first flight); the summit and the islets - later. At a nest sleeps
-- ONE guard (Combat.placePackAt), approaching does not wake it, taking - "!", after wake s it chases along the trail at speed share[attempt] of the thief's
-- run; it catches closer than catch - the egg flies back in an arc, take it again when the guard lay down and the thief moved away to rearm. SAFE: ring 0 - the gap of the own
-- plot (the egg goes into the bowl by itself, Incubation.flyHome); rings 1-2 - the own dragon waits within approachR of the nest on the home side (point D):
-- reached it closer than mountR - mounted by itself, the guard stops at dragonStop from the dragon and goes to sleep, home riding, at the plot the egg into the bowl.
-- Raid eggs hatch fast (hatchSeconds by rarity) - the next raid without waiting. The hunt and the combat waves are off when on.
Config.Raid = {
	on = true,
	-- the first egg and the first dragon are stolen from the guards (no dragons before that), fairly easy, on the 2nd-4th
	-- attempt: there is no newcomer table, ring 0 is open from the spawn, the guard of the first egg (0 dragons)
	-- is slower with every catch (first.share), wakes after first.wake
	firstEggByRaid = true,
	-- the one-dragon day: the Gloom nests give the egg only to a player without dragons (the first egg); whoever has a dragon -
	-- the egg in the nest is not visible to him (the client), the arrow does not lead to the nests and the free eggs. Rings 1-2 are off (open "off") -
	-- they will return glowing and harder
	firstEggOnly = true,
	-- a newcomer (0 dragons) gets the egg only from
	-- the ring 0 nest FARTHEST from his gate (a wedge of +-150 deg, ~100 studs of running across the plaza past two plots); the eggs of the near
	-- nests are not visible to him (the client) and cannot be taken (Raid.firstNestFor, the FirstNest attribute)
	firstFar = true,
	first = { share = { 0.85, 0.75, 0.65, 0.55 }, wake = 1.2 },
	grab = 9, -- studs to the nest egg: in the hands (like Glow.egg.pick)
	approachR = 35, -- closer to the nest with the egg - only on foot; the dragon waits here (rings 1-2)
	raidR = 90, -- the sortie zone: the dragon waits (GlowWait), the hunt does not come
	rearm = 15, -- after a catch take again when moved farther from the nest
	mountR = 12, -- with the egg closer to the own dragon - mounted by itself (Movement.mount); rings 1-2
	dragonStop = 8, -- the guard stops N studs from the dragon (the chase finish on rings 1-2)
	gateHold = 0.8, -- s: the guard stands at the line / at the dragon facing the thief, then to the lair
	returnSpeed = 11, -- studs/s to the lair
	minSpeed = 11, -- not slower (the thief on foot 16)
	arc = 1.1, -- s: the egg flies back into the nest in an arc after a catch
	-- the eggs
	-- of the daily raids hatch in 3-15 min - the hatch runs while the next raid runs (the first egg - 3 s, Incubation firstHatchSeconds)
	hatchSeconds = { Common = 180, Uncommon = 300, Rare = 480, Epic = 720, Legendary = 900, Mythic = 900 }, -- the hatch of raid eggs
	-- :
	-- the one-dragon day -> the egg raid all day. With a dragon the Gloom nest (the same far one, Raid.firstNestFor) gives eggs eggs per UTC
	-- day beyond the first; the guard of every next egg of the day is faster (share[k] - the share of the thief's speed on the first attempt at the k-th egg),
	-- after a catch softer by relief down to floor; wakes after wake[k]. The day is over - "Come back tomorrow", the limit is eggs again
	-- dismountR - with a dragon it dismounts only right at the nest (the plaza rim: riding past does not unseat)
	-- a P8 measurement (dailyraid_check): the gap at the chase start ~11.7 studs at wake 1.2 and it melts ~1.5 studs per every 0.1 s of a smaller wake
	-- (at wake 0.7 the fourth egg would never be carried away); so the anger is by speed, wake almost the same. A straight run ~100 studs
	-- 16 studs/s, catch 6: eggs 1-3 - on the first attempt with an ever smaller gap, the 4th - on the second (after a catch share - relief)
	daily = { eggs = 4, share = { 0.9, 0.97, 1.03, 1.08 }, relief = 0.06, floor = 0.85, wake = { 1.2, 1.15, 1.1, 1.05 }, dismountR = 15 },
	labelDistance = 110, -- the "<rarity> egg" caption above the nest is visible from this distance
	eggGlow = { range = 26, brightness = 3 }, -- a light of the rarity color at the nest egg
	springsFlatMax = 2.5, -- the bath rims are uneven: the nest is placed if the drop over 6 studs is not more
	waitFlatMax = 2.5, -- the dragon's waiting point (D): flat and empty, otherwise closer / at an angle (section waitPoint)
	rings = { -- ring - the ring number; open - what must be passed (hatch - has a dragon, rode - the first ride, flew - the first flight)
		{ ring = 0, open = "always", safe = "lot", respawn = 20, zone = "Meadow", rarity = { Common = 65, Uncommon = 27, Rare = 8 }, -- the daily raids - more varied (was 85/15) -- open from the spawn (the first egg - by a raid), the egg again after 20 s
			spots = { angles = { 30, 150, 270 }, r = 47, side = 7 }, -- the plaza rim: the odd wedges, to the side of the path to the stairs
			guard = { kind = "hound", scale = 1.0, name = "Gloom Hound", share = { 0.85, 0.80, 0.75, 0.70 }, wake = 1.0, catch = 6, lose = 100, maxSec = 60, lair = 5 } },
		{ ring = 1, open = "off", safe = "dragon", respawn = 90, zones = { "Meadow" }, -- off (was rode) - day 1 = one dragon; the nests are not built
			guard = { kind = "hound", scale = 1.3, name = "Gloom Hound", share = { 0.95, 0.90, 0.85, 0.80 }, wake = 0.8, catch = 6, lose = 100, maxSec = 60, lair = 5 } },
		-- the cliff egg spots hang on the wall among boulders - unreachable on foot
		-- the cliff nests - at the foot (foot: z in front of the foot boulders z -318..-290, along x every 40), the spot by measurement (flat, empty);
		-- the spots on the wall themselves remain free eggs for flyers
		{ ring = 2, open = "off", safe = "dragon", respawn = 180, zones = { "Springs" }, -- off (was flew)
			foot = { zone = "Cliffs", z = -276, xs = { -140, -100, -60, -20, 20, 60, 100, 140 }, flatMax = 2.0,
				offsets = { { 0, 0 }, { 6, 0 }, { -6, 0 }, { 0, 6 }, { 0, -6 }, { 12, 0 }, { -12, 0 }, { 12, 6 }, { -12, 6 }, { 0, 12 }, { 18, 0 }, { -18, 0 }, { 18, 8 }, { -18, 8 } } },
			guard = { kind = "hound", scale = 1.6, name = "Gloom Stalker", share = { 1.05, 1.00, 0.95, 0.90 }, wake = 0.6, catch = 7, lose = 100, maxSec = 60, lair = 5 } },
	},
}

Config.Glow = {
	masks = { ember = 112926808469068, frost = 88686058150315, moss = 84981625188204, tide = 72307346188506, storm = 107740421025097, dusk = 121830210570040 },
	masksJuvenile = { ember = 93773650836684, frost = 86771888880877, moss = 106524505411049, tide = 126702664026353, storm = 124499265135395, dusk = 77142655458912 },
	masksHatchling = { ember = 112800335424601, frost = 76405093421757, moss = 128699717963772, tide = 73662169428766, storm = 120819948741136, dusk = 77507240226771 },
	masksElder = { ember = 106217967810520, frost = 98548259573654, moss = 81698244456728, tide = 98410514005998, storm = 107633287537099, dusk = 85290940637696 }, -- Elder Ember/Frost/Moss -> 9B; tide/storm/dusk 9B are still being drawn
	tint = { ember = { 255, 150, 60 }, frost = { 170, 230, 255 }, moss = { 90, 255, 130 }, tide = { 80, 240, 230 }, storm = { 255, 230, 109 }, dusk = { 150, 140, 255 } },
	strength = { default = 6, tide = 4 },
	phases = { night = 1, dusk = 0.5, dawn = 0.3 },
	scanEvery = 2,
	dayFloor = 0, -- the special dragon glows only at night, like everyone
	-- "meet, fight, then find and STEAL the coveted egg; it hatches THE NEXT DAY": the egg is guarded by guards
	-- Gloom (Combat.guardEgg, flying closer than guardRange; farther than dropRange - the guard leaves); at home - onto the stand, the hatch after hatchHours h
	-- (into a bowl with hatchSeconds when there is a free one)
	egg = { on = true, element = "ember", rarity = "Legendary", hatchSeconds = 3, hatchHours = 20, pick = 9, beam = 70, color = { 255, 170, 70 },
		-- golden eggs one per element
		-- in this order (Core/GlowSeries; data.glowEgg.n); the next nest - when the previous one hatched; element - an egg without a series
		series = { "ember", "frost", "moss", "storm", "dusk", "tide" },
		-- the golden nest after the FIRST raid egg carried home (= the first
		-- dragon; for old profiles - has a dragon) and the first ride (raid.needRide: to the slope riding), ~1:30-2:00; the second dragon is harder
		afterRaids = 1,
		-- the button on the stand takes stepHours h off the timer for a price = the pen income for secondsPerHour s (20 h x 360 s =
		-- 2 h of income), not less than floor, a multiple of 100; not closer than minLeft s to the end; the player not farther than reach from the stand. Robux - the shop's
		-- HatchNow ladder with the target "glow" (Core/Shop.hatchRemaining)
		warm = { on = true, secondsPerHour = 360, floor = 1000, stepHours = 1, minLeft = 60, reach = 26 },
		guards = 3, guardRange = 45, dropRange = 220, distance = { 110, 200 }, -- distance: studs from the own nest to the golden one (the meadow, a trek)
		-- the spot by measurement - rings of rings studs around the meadow spots,
		-- the terrain drop within radius flatR not more than flatMax, within clearR no rock or decor, not closer than eggGap to the egg spots.
		-- plaza: a spot on the plaza opposite the own plot - the angles
		-- plazaArc from the opposite side, the radii plazaR from the center, not closer than spawnGap to the spawn point; none found - the meadow (rings);
		-- plazaArc - degrees from the own plot (the plaza
		-- edge to the side, the way home along the edge ~90 studs), plazaR from the center, not closer than hubGap to Old Ash / the stall / the Top nests board.
		-- slope - the foot of the terrace slope on the meadow in front of the own
		-- plot (riding there, steal only on foot): the radii radii from the world center (the terrace wall r 170, the slope rocks 182-204), the angles arcs from the own plot's angle, the zone "meadow",
		-- flat (flatMax), empty (clearR), not closer than nestGap to the ring 1 Gloom nests (their dismount zone 35 - so two nests do not fight over
		-- the dragon), not closer than otherGap to another's golden one; the best - closer to r radii[1] and to the own plot's axis. plaza = false: the plaza rim
		-- is off, the code is kept; none found on the slope - the plaza (if plaza), then the meadow (rings)
		spot = { rings = { 30, 42 }, flatR = 6, flatMax = 1.5, clearR = 9, eggGap = 28, plaza = false, plazaArc = { 90, -90, 150, -150 }, -- the wedges +-90, then +-150 (the run home ~103 studs); not closer than 25 to the shared nests (spotFor)
			plazaR = { 46, 44 }, spawnGap = 20, hubGap = 22, -- the gap between neighboring plots, 90 +-15 deg, r 46
			-- nestGap 72 = 2 x approachR + 2: point D (up to 35 from the golden one toward home) does not fall into the dismount zone of a ring 1 nest (35) - otherwise Raid
			-- would unseat the rider with the egg; the meadow spots stand at r 200 / 260 every 36 deg, the strict pass leaves the angles ~+-45 at r 196; relax -
			-- the second pass if there is no flat spot (Raid does not touch the player with a golden egg in hand)
			-- :
			-- the radii beyond the fir belt (256-280; a DecorLayout measurement: at all 6 plots spots with a margin of 17-38 studs, at 196-232 - 9-15);
			-- decorGap - not closer to a decor crown/rock (trees have CanQuery off - the clearR part check did not see them); the choice - where
			-- the margin from the decor is larger
			slope = { on = true, radii = { 244, 256, 268, 280 }, arcs = { 0, 15, -15, 30, -30, 45, -45, 60, -60 }, flatMax = 2.0, nestGap = 72, otherGap = 30,
				decorGap = 8, relax = { nestGap = 54, flatMax = 3.0, decorGap = 5 } } },
		-- the chase ("!" + RUN, the threat - it catches, the end is visible, the loss is soft): stole the egg -
		-- a large Gloom (kind, scale x the model height) rises from the golden nest and after wake s chases smoothly, every frame (Combat.chaseEgg):
		-- the speed share of the player's highest speed (on foot WalkSpeed, riding - the dragon stage speed, faster - its speed), not less than
		-- minSpeed; you can get away, you stopped - it catches up. Closer than catch studs - CAUGHT: the egg in an arc of arc s back into the nest (take again without a guard).
		-- At home (the own plot) - the chase is lifted; farther than lose studs or longer than maxSec s - it fell behind ("You got away!").
		-- A PACK of count Gloom Hounds (kind x scale) sleeps at the nest on the lairs spots
		-- ({ back from the nest, sideways } from the line nest -> the plot gate); the body center at sleepK of the height (lying), running at standK. Took the egg -
		-- "!", after wake s in a column: the leader at share[attempt] of the thief's highest speed (the first is passable, every catch slower down to the last),
		-- not less than minSpeed; the others along the leader's trail at gaps studs;
		-- the leader catches closer than catch. The thief is in the plot - the leader stops at the line for gateHold s, the pack to the nest and melts over retreat s; caught / farther than
		-- lose studs / longer than maxSec s - the pack back to the lairs (returnSpeed) and sleeps again; the egg in an arc of arc s back into the nest.
		-- count 1 (one pursuer, the player's height), the golden guard x1.5, the first attempt at equal speed, wake 0.8, catches at 7
		chase = { on = true, kind = "hound", scale = 1.5, count = 1, name = "Gloom Warden", spots = { { 6, 0 }, { 6, 5 }, { 6, -5 } },
			sleepK = 0.4, standK = 0.5, wake = 0.8, share = { 1.0, 0.9, 0.8, 0.7 }, minSpeed = 11, gaps = { 6, 12 }, catch = 7, lose = 100,
			maxSec = 60, arc = 1.1, gateHold = 0.8, retreat = 2.5, returnSpeed = 11 }, -- gateHold 0.6 -> 0.8 (P8: the stop at the line is readable)
		-- a sortie on foot - the player outside his plot closer than raidR to the golden nest (or carries the egg outside the plot):
		-- riding - jump off, the own dragon waits at the gate (gateSide studs along the edge from the path entry point, gateIn - into the plot);
		-- the gate - the gap in the plot fence (gapW as in WorldBuilder), outD - the path point outside; clearR - empty around the stand and
		-- the dragon's spot (the fence and its wall, the bowls, the table, the shelf).
		-- safe = "dragon" - a raid like on rings 1-2 (Services/Raid): within approachR the dragon stops BY ITSELF and
		-- dismounts, waits at point D (Raid.waitPointFor, 35 toward home), with the egg run to it - mounted (closer than mountR, the dragon not closer than approachR - 10 from
		-- the nest) = SAFE!, home riding, at the plot the egg onto the stand; "lot" - the run to the gap, the dragon at gate W. needRide - the nest
		-- appears after the first ride (on foot to the slope and back with a Warden x1.5 one cannot make it)
		raid = { raidR = 90, approachR = 35, gapW = 12, outD = 5, clearR = 3.5, safe = "dragon", needRide = true, mountR = 12 } }, -- approachR: closer to the nest - only on foot (jump off, no saddle) -- retreat: s - after the end of the chase the Gloom floats to the nest and melts
}

-- on the TEST place the sky hunt
-- from a fresh profile from the first day, otherwise it cannot be seen until the third day of playing; the live one (85991537614055) stays at skyFromDay = 3
if typeof(game) == "Instance" and game.PlaceId == 113442730664291 then -- outside Roblox (the luau CLI, the core tests) there is no game
	Config.Combat.skyFromDay = 1
	-- the invite reward test: the game owner on the test place is his own "invitee" after ownerTest s in the game (both roles, without the
	-- "already received" mark, with his real AccountAge / Premium / IsVerified / AgeChecked - Studio does not give them); the check line - as a toast.
	-- Off by default (otherwise every entry of his as a newcomer gets 2 eggs per 60 s)
	Config.Social.invite.ownerTest = 0
end

return Config
