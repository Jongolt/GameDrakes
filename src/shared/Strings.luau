--!strict
-- All the game texts in one module, English only (02, 06, 07). The stop list for the shop (07 §9). The substitutions: {name}, {n}.

local Strings = {}

Strings.GameName = "Find, Feed & Fly Dragons"

Strings.Loading = {
	title = "Find, Feed & Fly Dragons",
	waitNetwork = "Waiting for network...",
	findData = "Finding your dragons...",
	buildNest = "Building your nest...",
	spawn = "Spawning...",
	dataError = "We couldn't load your progress. It is safe. Please rejoin.",
	saveError = "Saving failed. If you leave now, recent changes may be lost.",
	sessionElsewhere = "Your dragons are open on another server. Please rejoin.",
	subtitle = "Hatch & Fly",
	welcomeBack = "Welcome back, {name}",
	welcomeNew = "Welcome, rider",
	nestSummary = "Your nest: {d} {dw}", -- the eggs - as separate parts, zeros are not written
	eggsHatching = "{e} {ew} hatching",
	eggsReady = "{e} {ew} ready",
	dragonWord = { "dragon", "dragons" },
	eggWord = { "egg", "eggs" },
	nestNew = "A new nest is waiting for you",
	-- P38 (Ride A Pet): tips in rotation under the loading bar and "Tap to skip"; only what is already in the game
	-- (the wind rings give 10 s of the nest income - "bonus coins", not minutes; the friends bonus +10% is in Config, not wired into the income -
	-- no tip about friends)
	tips = {
		"Eggs are free - find them in all 4 zones",
		"Feed your dragon to make it grow 2x faster",
		"A baby dragon rides on your shoulder",
		"Jump off a ledge - your baby dragon glides you down",
		"Teen dragons carry you - tap Ride",
		"Adult dragons fly - hold Jump to take off",
		"Fly through wind rings for bonus coins",
		"Old Ash at the Berry Stall has tasks for you",
		"The Index has 36 dragons to discover",
		"Your nest makes coins - walk over the pile",
	},
	skip = "Tap to skip",
}

Strings.Keeper = {
	name = "Old Ash",
	welcome = "Welcome, rider. Pick an egg - any of the three.",
	firstQuest = "A nest grows with eggs. Find one in the meadow - jump off the ledge, your hatchling will glide you down.",
	berries = "Here are 50 coins. Berries at my stall make a dragon grow twice as fast.",
	talk = "Talk",
	moreTales = "More tales next week.",
}

Strings.Hints = {
	warmEgg = "Warm egg! Put it in the nest",
	coinsFly = "Coins fly to you when you walk over them",
	gliding = "Gliding! Steer with the camera",
	glideHint = "Step off the ledge into the wind", -- the GLIDE step plate (the updraft at the nest ledge)
	keepWarm = "Keep it warm! {time}",
	eggCold = "The egg is cold - it will hatch slower",
	grewUp = "Your dragon grew up!",
	grewUpSub = "Ride it!", -- 1.9: the second line of the teen banner (02 §2, 2:00-2:30)
	grewInNest = "Take it out and ride", -- the second line if it grew up in the nest, not on the shoulder
	companionHint = "Open Dragons - make it your companion", -- the TAKE step plate
	ride = "Ride",
	fly = "Fly",
	riding = "Riding! Tap Dismount to get off",
	canFly = "Your dragon can fly!",
	canFlySub = "Hop on and hold Jump to take off",
	flyControls = "Hold Jump to climb. Down to dive.",
	takeOff = "Hold Jump while riding to take off",
	rideHint = "Hop on your dragon - tap Ride", -- 1.9: the RIDE step (02 §2, 2:30)
	takeOffHint = "Hold Jump to take off", -- the FLY step (on the phone the jump button = Up)
	windRings = "Fly through the wind rings", -- the FLY step in the air (04 §5.1)
	landed = "Landed",
	nestUpstairs = "Your nest is up the stairs",
	ready = "Ready!",
	hatch = "Hatch",
	feed = "Feed",
	feedAll = "Feed All",
	dismount = "Dismount",
	-- a soft swimming ban (HTTYD: "Swimming is cool, but... We recommend Dragon!")
	swimming = "Swimming is slow... ride your dragon!",
	swimNoDragon = "Swimming is slow... head back to shore",
	backToShore = "Back to shore",
	overWater = "Reach land before you dismount",
	turnBack = "Open sea ahead - turn back!", -- the soft world boundary (HTTYD), instead of a teleport
	up = "Up",
	down = "Down",
	nestFull = "Nest full",
	-- 1.8 part 2: one line per hint (02 §1), a toast when the arrow appears
	goTable = "Pick an egg from the table",
	toIncubator = "Put the egg in the incubator",
	tapHatch = "Tap Hatch!",
	collectPile = "Walk over the coins to collect",
	findEgg = "Find an egg in the meadow",
	feedHint = "Feed your dragon to grow 2x faster",
	-- a ready egg far from the player; a jump riding a teen
	hatchGo = "Egg ready - go to your nest", -- shorter: in the banner on a 667 pt phone the long line was squeezed to ~10 px
	tooYoung = "Too young to fly - it flies when it grows up",
	-- the combat steps - the Gloom at the meadow, the guard, the sky
	gloomHint = "Breathe at the Gloom",
	glowEggHint = "Sneak to the golden nest - the Gloom is asleep", -- the pack sleeps, approaching does not wake it
	glowHomeHint = "Run home with the glowing egg!", -- the glowing egg in the hands, the Gloom chases
	guardianHint = "Purify the guardian before time runs out",
	skyHint = "Fly up - the Gloom took the sky",
	-- the egg raid - the steps
	raidHint = "Sneak to the Gloom nest - it is asleep",
	raidFirstHint = "Steal an egg from the sleeping Gloom - your first dragon!", -- no dragons yet
	raidHomeHint = "Run home with the egg!",
	raidDragonHint = "Run to your dragon!",
	raidRideHint = "Ride home - the egg hatches soon",
	raidWaitHint = "Next egg in {t}",
	raidDayHint = "Steal another egg - {n} left today", -- the daily raids (Config.Raid.daily), the RaidLeft attribute
	-- the one-dragon day - the stand and the stall
	warmHint = "Warm your golden egg with coins",
	stallHint = "Visit the Berry Stall - berries grow dragons 2x faster",
}

Strings.Steps = { -- P10 (02 addendum 1.3, craft/04 §7.1): the current step banner at the top center: the category in color, one line, the progress
	hatch = "HATCH",
	coins = "COINS",
	glide = "GLIDE", -- the step "step off the ledge into the updraft" (errand 2)
	egg = "EGG",
	feed = "FEED",
	ride = "RIDE", -- 1.9 (DA RIDING / FLYING)
	companion = "TAKE", -- the dragon grew up in the nest, no companion - take it
	fly = "FLY",
	fight = "FIGHT", -- the Gloom and the guards
	glow = "GLOW", -- the glowing egg
	raid = "RAID", -- the egg raid
	done = "Done!",
	progress = "{k}/{n}",
	distance = "{n} m", -- P34 (Ride A Pet "62m Away"): the distance to the step target
}

Strings.Menu = {
	-- the ascension line in the Dragons tab (05 §6)
	ascendTitle = "Ascension {roman}: income x{n}",
	ascendNeed = "Needs {what} + {cost} coins",
	ascend = "Ascend",
	needAdult = "an Adult dragon",
	needElder = "an Elder dragon",
	needElders = "Elders of {n} elements", -- 1.8 part 2 (02 §1, §6): the menu stack
	dragons = "Dragons",
	settings = "Settings",
	back = "Back",
	close = "Close",
	music = "Music",
	sounds = "Sounds",
	otherDragons = "Show other riders' dragons", -- P37
	on = "On",
	off = "Off",
	reset = "Reset (hold 3 s)", -- the admin buttons in a row; the reset only by holding - written on the button
	resetHold = "Hold 3 s", -- the reset only by holding
	resetHolding = "Hold... {n}",
	bots = "Bots: {n}", -- 1.14: load for measuring FPS
	botsOff = "Bots: off",
	perfTest = "Perf test", -- an experiment of a minute per graphics mode (Controllers/Perf)
	perfStep = "Perf {k}/{n}",
	perfStart = "Perf test: stay by your nest, {n} minutes",
	perfDone = "Perf test done. Thank you!",
	botName = "Bot {n}",
	fps = "{n} fps",
	resetDone = "Progress reset. Your nest is new again.",
	nest = "Nest",
	sanctuary = "Sanctuary",
	empty = "No dragons yet. Hatch an egg!",
	version = "Find, Feed & Fly Dragons {v}",
	slots = "{k} / {n} Slots",
	randomName = "Random name",
	-- 2.9 (09 §1): the code of the week field in Settings
	code = "Code",
	codeHint = "Enter code",
	redeem = "Redeem",
}

-- random names for the dice in the name window (HTTYD: the dice next to the quill); by element + common
Strings.Names = {
	ember = { "Ash", "Blaze", "Cinder", "Flare", "Pyra", "Scorch", "Kindle", "Rusty" },
	frost = { "Snow", "Glacier", "Icicle", "Winter", "Frosty", "Crystal", "Hail", "Nimbus" },
	moss = { "Fern", "Clover", "Sprout", "Willow", "Ivy", "Thistle", "Bramble", "Sage" },
	tide = { "Wave", "Marina", "Coral", "Ripple", "Splash", "Pearl", "Brook", "Kelpie" },
	storm = { "Bolt", "Thunder", "Zap", "Gale", "Tempest", "Rumble", "Spark", "Volt" },
	dusk = { "Luna", "Star", "Shadow", "Comet", "Nova", "Twilight", "Eclipse", "Vesper" },
	any = { "Pip", "Momo", "Ziggy", "Biscuit", "Pepper", "Juno", "Scout", "Nugget" },
}

Strings.Card = { -- the dragon card (1.8 DragonCard; 03 addendum, craft: the card on the element color)
	tagHuge = "HUGE", -- the size and shine tags were text in the code - now translated
	tagBig = "Big",
	tagShiny = "Shiny",
	stageLine = "{stage}  -  {element}",
	growsIn = "Grows in {time}",
	fullyGrown = "Fully grown",
	fedLine = "Growing 2x faster  {time}",
	income = "+{n}/s",
	feed = "Feed  {n}",
	rename = "Rename",
	setCompanion = "Companion", -- 1.9 (craft/04 §7.11: the "companion" star)
	isCompanion = "Your companion",
	inNest = "In the Nest",
	inSanctuary = "In the Sanctuary",
	tapToOpen = "Tap a dragon to see its card",
	growNow = "Grow now", -- 2.2: the context shop buttons on the card (07 §2 no. 1b, no. 8)
	treat = "Treat",
	looks = "Looks",
	-- the move nest <-> sanctuary and the release (a second press within releaseConfirm s - the confirmation)
	toNest = "To Nest",
	toSanctuary = "To Sanctuary",
	release = "Release",
	releaseSure = "Sure? +{n}",
	released = "Dragon released: +{n} coins",
	releaseCommonTile = "Release {k} Common", -- the Dragons tab tile, a second press - the confirmation
	releaseCommonSure = "Sure? +{n}",
	releasedAll = "{k} dragons released: +{n} coins",
	swapped = "{name} went to the Sanctuary",
}

Strings.Hatch = {
	result = "{rarity} {element}", -- above the hatchling: the rarity and the name
	named = "Name your dragon",
	done = "Done",
	skip = "Skip",
	fed = "Fed! Grows 2x faster for 5:00",
	hatchingIn = "{egg}  {time}", -- the pill above the incubator
	eggAt = "{zone} Egg",
	insideIn = "{rarity} {element} inside  {time}", -- the outcome before paying Hatch now
	serverLine = "{player} hatched a {rarity} {element} dragon!",
	rareNest = "A rare egg appeared at the {zone}!",
	hugeLine = "{player} hatched a HUGE {element}!",
}

Strings.Index = {
	title = "Dragon Index",
	-- the set names = Core/Index (the loc_spec test compares), here - so they are translated
	sets = { meadow = "Meadow set", ember = "{Ember} set", frost = "{Frost} set", moss = "{Moss} set", tide = "{Tide} set", storm = "{Storm} set", dusk = "{Dusk} set" },
	meadowSet = "Dragon Index: Meadow set {n}/10",
	odds = "Odds",
	unknown = "???",
	claimAll = "CLAIM ALL ({n})!",
	-- the Index tab, the plate, the toasts
	button = "Index {pct}%",
	header = "Dragon Index {k}/{n}  ({pct}%)",
	bonusNow = "Income +{b}%",
	bonusNext = "Next: +{b}% at {t}%",
	setRow = "{name}: {k}/{n}",
	claim = "Claim",
	claimed = "Claimed",
	rewardSet = "{m} min of income",
	newEntry = "New Index entry: {name} ({k}/{n})",
	ancientWorldwide = "Ancient dragons hatched worldwide: {n}",
	keeperEntry = "Old Ash",
}

Strings.HUD = {
	shop = "Shop",
	dragons = "Dragons",
	index = "Index",
	quests = "Quests",
	gifts = "Gifts",
	settings = "Settings",
	stormIn = "Storm in {time}",
	nextGift = "Next gift {time}",
	perSecond = "{n}/s",
	boost = "x2 {time}", -- 2.2: the boost timer in the income line: "+83/s x2 29:57"
}

Strings.Quests = {
	panel = "Keeper {n}/{total}: {title}",
	daily = "Daily quests",
	allThree = "All three: Cliffs egg",
	ascensionGoal = "Ascension I: an Adult dragon + 5,000 coins",
	view = "View",
	start = "Keeper {n}/{total}: {title}",
	-- the plate on the right, the Quests tab, the Done! banner
	keeperN = "KEEPER {n}/{total}",
	header = "Keeper's tales: {n}/{total}",
	done = "Done! Keeper {n}/{total}: {title}",
	rewardCoins = "{n} coins",
	rewardMinutes = "{n} min of income",
	rewardEgg = "{zone} egg",
	rewardRare = "Rare egg",
	pickEgg = "Old Ash's gift - pick your Rare egg:",
	allDone = "ALL TALES TOLD",
	locked = "???",
	current = "Now",
	doneMark = "Done",
}

Strings.Rewards = {
	timeGift = "{n}-minute gift",
	timeGiftCoins = "{n}-minute gift: +{coins} coins",
	nextGift = "Next gift: {time}",
	welcomeGift = "Welcome gift",
	joinGroup = "Join Lanternfox Studios - get a {Moss} egg (Uncommon or better)", -- the group was renamed to the studio
	join = "Join",
	likeNote = "Like and favorite if you enjoy it - no reward, just thanks",
	-- 2.5 (06 §9): the "while you were away" card - the title, the coins large, the explanation small, the egg and growth lines, Collect
	awayTitle = "While you were away",
	awayCoins = "+{coins} coins",
	awayNote = "Your nest kept earning at 25%, up to 8 h",
	awayEggs = "{n} {ew} ready to hatch",
	awayGrew = "{name} grew to {stage}",
	awayMore = "and {n} more",
	awayDragon = "Your dragon",
	collect = "Collect",
	calendarDay = "Day {n}: {what}",
	-- 2.4 (06 §2-4, §6): the Gifts tab, the pill at the top, the reward banners
	tab = "Gifts",
	giftsHeader = "Gifts for playing",
	giftsNote = "Timer pauses after 5 min without input",
	calendarHeader = "Daily calendar - Day {n}",
	calendarNote = "Come back tomorrow for Day {n}",
	calendarStart = "Come back tomorrow for your next day",
	calendarNext = "Come back tomorrow for Day {n}: {gift}", -- what exactly awaits tomorrow
	tomorrowTitle = "Tomorrow, Day {n}: {gift}", -- the banner once per session: after the first dismount or afterSeconds (Config.Rewards.tomorrowBanner)
	tomorrowNote = "Your nest keeps earning while you are away",
	pickDragon = "Pick your Rare dragon:",
	claim = "Claim",
	claimed = "Done",
	pillReady = "Claim!",
	gotCoins = "+{n} coins",
	berries = "Berries x{n}",
	berriesFed = "Berries: {n} dragons fed",
	egg = "{zone} egg",
	rareNest = "Rare egg", -- "Rare nest egg" on the 90 min tile came out smaller than its neighbors
	epicEgg = "Epic egg",
	lantern = "Nest lantern",
	rareDragon = "Rare dragon",
	coins = "Coins",
	minutes = "{n} min of income",
	gift = {
		[5] = "5-minute gift", [10] = "10-minute gift", [15] = "15-minute gift: berries", [20] = "20-minute gift",
		[30] = "30-minute gift: a Cliffs egg!", [45] = "45-minute gift", [60] = "60-minute gift: a Springs egg!", [90] = "90-minute gift: a rare nest egg!",
	},
	day = {
		-- [2] "berries" and [3] "a Cliffs egg" are from an older layout (now day 2 - a Cliffs egg or the dragon
		-- of the d2 experiment, day 3 - berries) - removed: days 2-3 take the template calendarDay "Day {n}: {what}" with what was granted
		[1] = "Day 1: coins", [4] = "Day 4: coins", [5] = "Day 5: a nest lantern",
		[6] = "Day 6: a Springs egg", [7] = "Day 7: a Rare dragon!", [14] = "Day 14: an Epic egg!",
	},
	dayTile = "Day {n}",
	giftTile = "{n} min",
	paused = "Paused",
	calendarWaiting = "Your Day {n} reward is waiting - open Gifts",
	-- 2.4 Season 1 (06 §8) and the chest (§3)
	seasonHeader = "Season 1 - {n} points",
	seasonHeaderOne = "Season 1 - 1 point",
	seasonNote = "Points come from daily quests: 1 per quest, 1 more for all three",
	seasonNoteWeekly = "Points: daily quests 1 each, +1 for all three; weekly quests {n} each", -- with the tasks of the week (from 08.11)
	seasonStep = "{n} pts",
	seasonDone = "Season 1: step {n}",
	seasonEnded = "Season 1 has ended - {Solstice} returns next year",
	banner = "Season 1 banner",
	solstice = "{Solstice} color",
	solsticeDragon = "{Solstice} dragon!",
	chestPrompt = "Open gifts",
	chestObject = "Gift chest",
	welcomeTitle = "Welcome gift",
	joined = "Welcome to Lanternfox Studios! Here is your {Moss} egg",
	notJoined = "Join the group first, then tap Join again",
	freeGiftDone = "Studio gift taken",
}

-- 2.4 (06 §2): the daily tasks - the names verbatim from the spec, the groups, the banners
Strings.Daily = {
	header = "Daily quests",
	newIn = "New quests in {time}",
	tiers = { easy = "Easy", medium = "Medium", hard = "Hard" },
	bonus = "All three: Cliffs egg",
	done = "Daily done! {title}",
	allDone = "All three done! Cliffs egg",
	open = "Daily quests are open - see Quests",
	titles = {
		eggs3 = "Collect 3 eggs", feed3 = "Feed 3 times", visit2 = "Visit 2 nests", play10 = "Play 10 minutes",
		hatch2 = "Hatch 2 dragons", fly2 = "Fly for 2 minutes", cliffsEgg = "Bring an egg from the Cliffs", grow1 = "Grow a dragon one stage",
		rings5 = "Fly through 5 wind rings", hatchRare = "Hatch a Rare or better", summitEgg = "Bring an egg from the Summit",
		shards6 = "Collect 6 Storm shards", party1 = "Help in a Hatch Party",
		-- 2.9 pool B (from 09.11)
		eggs5 = "Collect 5 eggs", feed5 = "Feed 5 times", springsEgg = "Bring an egg from the Springs", shards3 = "Collect 3 Storm shards",
		weatherHatch = "Hatch a dragon during a storm, starfall or aurora", hatch4 = "Hatch 4 dragons", rings15 = "Fly through 15 wind rings",
	},
	keeperTitle = "Keeper's tales",
}

-- the tasks of the week - the Quests tab, the completion banner, the toast of the first entry in the week; titles by id from
-- Content.Updates[n].weekly
Strings.Weekly = {
	header = "Weekly quests: {title}",
	newIn = "new in {time}",
	tag = "Week",
	reward = "+{n} pts, {zone} egg",
	done = "Weekly quest done! {title}",
	gotBoth = "+{n} season points, {zone} egg",
	open = "New weekly quests - see Quests",
	badge = "Complete one: {badge} badge", -- the event badge, the name is not translated
	badgeDone = "✓ {badge} badge",
	titles = {
		auroraHatch = "Hatch 2 dragons under the aurora", glacier = "Hatch a {Glacier} dragon",
		emberHatch = "Hatch 3 {Ember} dragons", emberGrow = "Grow {Ember} dragons 2 stages",
		shards10 = "Collect 10 Storm shards", pearl = "Hatch a {Pearl} {Tide} dragon",
		nightHatch = "Hatch 2 dragons at night", duskHatch = "Hatch 3 {Dusk} dragons",
	},
}

Strings.Weather = {
	storm = "Storm! Coins x2 for 3:00. Dragons hatched now are Stormborn",
	starfall = "Starfall! Eggs everywhere for 3:00",
	stormDragonComing = "The {StormDragon} is coming in 1:00",
	stormDragonShards = "Storm shards {k}/{n}",
	-- 2.7
	over = "The sky clears",
	shardPicked = "{name} found a storm shard ({k}/{n})",
	lastShard = "{name} took the last storm shard!",
	dragonDone = "{StormDragon}: {k}/{n} shards",
	dragonReward = "+{coins} coins",
	dragonRewardEgg = "+{coins} coins + Cliffs egg",
	timerStorm = "Storm x2  {time}",
	timerStarfall = "Starfall  {time}",
	-- 2.9 (09 §3): Aurora from update 1
	aurora = "Aurora! {Frost} eggs from the Summit hatched now become {Glacier} dragons",
	timerAurora = "Aurora  {time}",
	updateParty = "Update Party! Coins x2 until the update",
	partyTimer = "Update Party! New content in {time}",
	ascended = "Ascension {roman}! Income x{n}",
}

-- purchases for coins (05 §1-3): the button above a locked incubator, the slot tile in the Dragons tab, the toasts after a purchase
Strings.Buy = {
	unlock = "Unlock  {price}",
	slotTile = "+1 Slot",
	incubator = "New incubator unlocked!",
	slot = "Nest slot +1! One more dragon earns",
	shelf = "Egg shelf +2",
	shelfButton = "+2 Shelf  {price}", -- the button above the first locked shelf cup
}

-- 2.9 (09 §1-3): live operations - the errand scrolls 16-20, the codes, the update announcement, the variant caption
Strings.LiveOps = {
	read = "Read",
	noteObject = "Old Ash's note",
	noteOf = "Old Ash's note {n}/{total}",
	codeDone = "Code {code}!",
	-- the community goal after the "favorite" window - a code for everyone, not a reward for one's own like
	likeAsk = "Enjoying the game? Give it a 👍",
	likeGoal = "At {n} likes, every rider gets a new code",
	updateLive = "The {title} update is live!",
	updateSub = "New tales from Old Ash - see Quests",
	variant = "{label} {element}", -- the element variant above the hatchling and in the card: "Glacier Frost"
	variantLine = "{player} hatched a {label} {element} dragon!",
}

Strings.Shop = {
	title = "Shop",
	tabs = { time = "Time", nest = "Nest", coins = "Coins", looks = "Looks", gifts = "Gifts" },
	view = "View",
	seePrice = "See price",
	openShop = "Open shop",
	owned = "Owned",
	hatchNow = "Hatch now",
	growNow = "Grow now",
	fasterIncubator = "Faster incubator",
	needsCoins = "Needs {n} more coins",
	bought = "Got it: {name}",
	giftSent = "Gift sent to {name}",
	giftReceived = "A gift from {name}: {item}!",
	giftRegion = "Gifting isn't available between your regions",
	alreadyOwn = "You already own {k} of {n} items",
	archived = "Archived - returns next year at a higher price",
	-- 2.1-2.2: the cards (07 §2-3, add. 2.4): the name, 1-2 lines of what it gives; the key = the SKU without the price (the steps and the packs - by class)
	names = {
		hatchNow = "Hatch now", growNow = "Grow now", treats = "Treats x{n}", boost = "Coins x2 for {time}", income = "Nest income: {time}",
		StarterPack_49 = "Starter Pack", NestBundle_2999 = "Everything for the Nest", VIP_299 = "VIP", X2Coins_299 = "x2 Coins",
		AutoCollect_149 = "Auto Collect", NestSlot1_99 = "Nest slot +1 (I)", NestSlot2_199 = "Nest slot +1 (II)", NestSlot3_399 = "Nest slot +1 (III)",
		FastIncubator_249 = "Fast Incubator", Preset_Sunset_99 = "Sunset color preset", Trail_Comet_149 = "Comet flight trail",
		NestSkin_Lagoon_299 = "Lagoon nest skin",
		Trail_Tidal_149 = "Tidal flight trail", NestSkin_Night_299 = "Night Sky nest skin",
		DragonWeek_1_199 = "Dragon of the week: {Cinder}", DragonWeek_2_299 = "Dragon of the week: {Nightfall}",
	},
	lines = {
		hatchNow = "Finish hatching your longest egg. Price depends on the time left.",
		growNow = "Finish a dragon's growth timer. Price depends on the time left.",
		treats = "A treat finishes half of a dragon's growth timer",
		boost = "Double coins while you play. The timer only runs in game",
		income = "= {coins} coins at your current rate",
		StarterPack_49 = "Two eggs of your chosen elements (Rare or better), a second incubator and a rider scarf. One per account",
		-- the same pack without randomness - where Roblox closes paid randomness (BE, NL, AU, UK < 18, BR...)
		StarterPack_49_fixed = "Two Rare eggs of your chosen elements, a second incubator and a rider scarf. One per account",
		NestBundle_2999 = "Royal nest skin, three nest slots, the Royal aura and the Nest Lord title",
		VIP_299 = "+1 nest slot, +10% coins (also offline), VIP name tag, Gilded nest skin",
		X2Coins_299 = "Your nest earns double coins forever",
		AutoCollect_149 = "Nest coins go straight to your balance, no pile cap",
		NestSlot1_99 = "One more dragon earns in your nest",
		NestSlot2_199 = "One more dragon earns in your nest. Requires slot I",
		NestSlot3_399 = "One more dragon earns in your nest. Requires slot II",
		FastIncubator_249 = "All eggs hatch 40% faster",
		Preset_Sunset_99 = "A warm color preset for one dragon. Move it between dragons any time",
		Trail_Comet_149 = "A glowing trail behind you in flight",
		NestSkin_Lagoon_299 = "Turquoise fence, sign, egg table, showcase and incubator bowls for your nest", -- honest about what gets painted (the item image - shells and water)
		Trail_Tidal_149 = "A sea-blue trail behind you in flight",
		NestSkin_Night_299 = "Night-blue fence, sign, table and bowls with silver posts for your nest",
		DragonWeek_1_199 = "An Epic {Ember} hatchling with glowing cinder colors. One per account, this week only",
		DragonWeek_2_299 = "A Legendary {Dusk} hatchling. One per account, this week only",
	},
	-- only old emoji (before Unicode 12): the new ones (🪙, 🪺, 🧺) are not drawn by the Roblox client (checked with a sampler)
	icons = { hatchNow = "🥚", growNow = "⏩", treats = "🍖", boost = "⚡", income = "💰", StarterPack_49 = "🎒", NestBundle_2999 = "👑", VIP_299 = "⭐",
		X2Coins_299 = "✨", AutoCollect_149 = "🔄", NestSlot1_99 = "🏠", NestSlot2_199 = "🏠", NestSlot3_399 = "🏠", FastIncubator_249 = "🔥",
		Preset_Sunset_99 = "🎨", Trail_Comet_149 = "☄️", NestSkin_Lagoon_299 = "🏝️", gift = "🎁",
		Trail_Tidal_149 = "🌊", NestSkin_Night_299 = "🌙", DragonWeek_1_199 = "🐉", DragonWeek_2_299 = "🐉" },
	gift = "Gift",
	giftTo = "Gift to {name}",
	giftPick = "Pick a player on this server, then choose a gift",
	giftNobody = "Nobody else on this server right now. Gifts need a player here to receive them",
	nothingTime = "Nothing to speed up right now. Eggs and growing dragons show up here",
	ticket = "Ticket x{n}",
	ticketUsed = "Ticket used: {name}",
	useTicket = "Use ticket",
	treatsLeft = "Treats: {n}",
	treat = "Treat",
	requires = "Requires {name}",
	starterPick = "Pick two elements for your eggs",
	starterIncubator = "You already have a second incubator: you get {n} coins instead",
	-- the odds of every outcome before the purchase, in percent
	starterOdds = "Odds for each egg: {list}",
	starterVariants = "Also for each egg: Shiny {shiny}, Big {big}, Huge {huge}",
	starterRounded = "Probabilities are rounded",
	starterFixed = "Both eggs will be Rare",
	pickTitle = "Choose elements",
	robux = "R$",
	applied = { slot = "Your egg is ready to hatch!", dragon = "{name} finished growing!", ticket = "Ticket saved: it applies to your next egg or dragon", items = "Treats added", boost = "Coins x2 for {time}", coins = "+{coins} coins", flag = "Unlocked forever", look = "Added to your Looks", dragonWeek = "{name} joined your dragons!", starter = "Starter Pack: eggs on your shelf, incubator ready" },
	ownedLine = "You own this",
	bundleHint = "Best value for a full nest",
	-- the stop list: the shop_spec test fails if a shop string contains this
	banned = { "buy now", "last chance", "hurry", "limited time", "ask your parents", "only today" },
}

Strings.Social = {
	hatchParty = "Hatch Party: a friend who touches your incubator makes the egg hatch twice as fast",
	invite = "Invite friends",
	-- 2.6
	partyDone = "Hatch Party! {name} helped - hatching twice as fast",
	friendParty = "Friend party! {name} helped - hatching x3 faster",
	partyHelper = "Hatch Party! You helped {name}",
	friendPartyHelper = "Friend party! You helped {name} - x3",
	joinedFriend = "You joined {name} - stand by their egg for a Hatch Party!",
	rareAppeared = "A rare egg appeared at the {zone}!",
	rareFound = "{name} found the rare egg",
	hatchAnnounce = "{name} hatched a {rarity} {element}!",
	topNests = "Top nests",
	signRate = "{name}'s Nest  {rate}",
	friendsOn = "Friends on server: {n} (+{pct}%)",
	friendsPill = "+{pct}%",
	inviteTitle = "Play with friends",
	inviteBonus = "Invite a friend - you BOTH get an Epic dragon egg!",
	-- after the invite window, the friend's arrival, the grant, the day limit
	inviteHow = "Egg for you both when your friend has played 10 min. Their account: 60+ days. Premium or verified: Legendary!",
	inviteEggEpic = "an Epic dragon egg",
	inviteEggLegendary = "a Legendary dragon egg",
	yourFriend = "your friend",
	inviteStay = "Play 10 min - you and {name} BOTH get {egg}!",
	inviteFriendIn = "{name} is here! After 10 min you BOTH get {egg}",
	inviteTooNew = "{name} is here! Their account is under 60 days - no egg gift this time",
	inviteGot = "FRIEND GIFT!",
	inviteGotSub = "You and {name} both got {egg}!",
	inviteLimit = "Friend gifts today: {n} of {n} - more tomorrow!",
	invitePrompt = "Hatch dragons with me!",
	inviteUnavailable = "Invites are not available right now",
	frostIsle = "Opens in a future update", -- the sign on the rock in front of the strait; was "needs an adult Frost dragon" - the wall let nobody through
	nestSign = "{name}'s Nest",
	unhatched = "Unhatched",
	newborn = "Newborn",
}

Strings.Migr = {
	spareEggs = "Your {n} spare eggs turned into {coins} coins!",
}

Strings.Errors = { -- the Remotes.Reasons codes -> one toast line
	loading = "Still loading...",
	bad_request = "Something went wrong",
	too_fast = "Slow down a little",
	not_enough = "Needs {n} more coins",
	nest_full = "Nest is full",
	sanctuary_full = "Sanctuary is full",
	over_water = "Reach land before you dismount", -- Dismount above the sea
	no_shore = "No shore nearby",
	no_dragon = "No such dragon",
	no_egg = "No egg here",
	too_far = "Come closer",
	already = "Already done",
	already_fed = "Already fed",
	elder = "Elders are fully grown",
	companion = "Pick another companion first",
	not_in_nest = "Only nest dragons",
	not_ready = "Not ready yet",
	bad_name = "Try another name",
	name_cooldown = "You can rename again in {n} s",
	locked = "Locked",
	no_slot = "No free incubator",
	needs_adult = "Needs an Adult dragon",
	needs_elder = "Needs an Elder dragon",
	needs_elements = "Needs Elders of {n} elements",
	forbidden = "Not allowed",
	needs_juvenile = "Needs a Juvenile dragon", -- 1.9
	not_companion = "Set it as your companion first",
	riding = "You are already riding",
	owned = "You already have this", -- 2.1 the shop
	no_target = "Nothing to speed up right now",
	no_player = "That player has left the server",
	region = "Gifting isn't available between your regions",
	no_treats = "No treats left",
	-- the appearance: SetLook
	not_owned = "Get it in the Shop first",
	wrong_element = "This color is for {element} dragons only",
	bad_code = "That code doesn't work", -- 2.9 the codes of the week
	expired = "That code has expired",
}

Strings.Loop = { -- 1.7 the loop before the 1.8 client: the buttons at items (ProximityPrompt) and the pop-ups above the head
	pick = "Pick up",
	eggObject = "{rarity} egg",
	place = "Place egg",
	incubator = "Incubator",
	hatch = "Hatch!",
	warming = "Hatching in {time}",
	locked = "Locked",
	collect = "Collect",
	coins = "{n} coins",
	basketFull = "Your basket is full",
	needEgg = "Find an egg first",
	notYours = "This is not your nest",
	busy = "This incubator is busy",
	picked = "{rarity} {element} egg! Take it to your nest",
	hatched = "{rarity} {element} hatched!",
	stageUp = "{name} grew into an {stage}!", -- the banner only for the Elder (Banners.showStage stage >= 3)
	toSanctuary = "Nest full: {name} went to the Sanctuary",
	swappedOut = "{name} moved to the Sanctuary to make room for {new}", -- entry into the nest by potential
	withRider = "{name} is out with its rider", -- the sign on the companion's empty stand
	yourNest = "{player}'s Nest",
	coinStat = "Coins",
	carrying = "Carrying: {rarity} {element} egg",
}
Strings.Rarity = { Common = "Common", Uncommon = "Uncommon", Rare = "Rare", Epic = "Epic", Legendary = "Legendary", Mythic = "Mythic" }
Strings.Stage = { [0] = "Hatchling", [1] = "Juvenile", [2] = "Adult", [3] = "Elder" }
Strings.Zone = { Meadow = "Meadow", Cliffs = "Cliffs", Springs = "Springs", Summit = "Summit" }
Strings.World = { -- the world signs and captions (04, task 1.5; spec 1.2 §5.1)
	freeNest = "Free Nest {n}",
	nestWord = "Nest",
	summitSign = "Summit - Fly Up",
	updraft = "Updraft",
	updraftSub = "Jump in to rise up",
	stall = "Berry Stall",
	stallSub = "Feed to grow 2x faster",
	stallFeed = "Feed", -- the hint at the stall (errand 4 "Buy berries at my stall"), ObjectText - stallBerries
	stallBerries = "Berries for your nest",
	standTitle = "Dragon of the week", -- the stand on the plaza; below the name, the rarity and the element, the price (the client)
	standView = "View",
	keeperSub = "the Keeper",
	windRings = "Fly through the wind rings",
	ringBonus = "+{n} coins",
	springsGate = "Hot Springs", -- the visible zone gate (craft/04 §7.4 item 2)
	springsGateSub = "Ride a Juvenile dragon across",
	springsGuard = "Hot Springs open to Juvenile riders - grow your dragon!",
	secretFound = "Secret found: the hidden grotto behind the falls!", -- the first find of the secret spot -- the hatchling was returned to the crossing
	frostGate = "Frost Isle",
	coin = "+{n}",
	phase = { dawn = "Dawn", day = "Day", dusk = "Dusk", night = "Night" }, -- P16: the day phase icon in the HUD (1.8)
	-- P35 (Ride A Pet "☀ in 1m 15s" at the jump): the timer to the day/night change
	timerIn = "in {t}",
	timerMinSec = "{m}m {s}s",
	timerSec = "{s}s",
}

-- ---------------------------------------------------------------------------------------------- appearance: the appearance showcase (07 add. 2.6)
-- the names of the presets, skins and titles; the preset buttons on the dragon card; the nest look choice in the shop's Looks tab; the tag above the head
Strings.Looks = {
	presets = { sunset = "Sunset", solstice = "Solstice", cinder = "Cinder" },
	presetOn = "✓ {name}",
	presetMove = "Move {name}",
	presetSet = "{name} color on {dragon}",
	presetOff = "{name} color removed",
	presetAuto = "{name} color is on {dragon}. Move it on any dragon card",
	skins = { classic = "Classic", lagoon = "Lagoon", gilded = "Gilded", royal = "Royal", night = "Night Sky", ascended = "Ascended" }, -- Ascended - the Ascension tint as a choice
	skinRow = "Nest look:",
	skinSet = "Nest look: {name}. See it at your nest",
	vipTag = "VIP",
	titles = { nestLord = "Nest Lord" },
	ascendedTag = "Ascended {roman}", -- the title for Ascension above the head
}
-- the line "what awaits you and when" under the coins (Controllers/NextUp), the next update
-- block in the Gifts tab with the RSVP button (the Roblox event)
Strings.Next = {
	label = "NEXT",
	grow = "{name}: {stage} in {time}",
	hatch = "Egg hatches in {time}",
	growThenRide = "{name} grows up in {time} - then you can ride", -- the firstborn before the first ride
	growThenFly = "{name} grows up in {time} - then you can fly", -- the firstborn before the first flight
	stormIn = "{StormDragon} in {time}", -- the target for the waiting time; the dragon name by the Loc.NAMES substitution, not translated
	starfallNow = "Starfall! Eggs respawn fast", -- (B4)
	update = "{title} update in {time}",
	days = "{d}d {h}h",
	updateHead = "Next update: {title} in {time}",
	notify = "Notify me",
	going = "You'll be notified",
}

-- the fight with the Gloom. The guard names ({name}) are names, not translated
Strings.Combat = {
	breath = "BREATH",
	auto = "AUTO",
	autoLocked = "AUTO is free for group members",
	stage = "Stage {k}/{n}",
	replay = "The Gloom returns",
	left = "{n} left",
	timer = "{name} {time}",
	clear = "Purified! +{n} coins",
	clearEgg = "Purified! +{n} coins and an egg",
	guardianWin = "{name} purified!",
	skyOpen = "The sky islands are calling - fly up!",
	fail = "The Gloom retreats. Try again in {s}s",
	muted = "The Gloom chokes your breath!",
	stunned = "Shockwave! Step out of the circle",
	help = "You helped a friend! +{n} coins",
	noDragon = "Take your dragon with you",
	noTarget = "No Gloom nearby",
	incoming = "The Gloom is coming!", -- 2 s before the wave
	keeper = "The Gloom creeps at the meadow edge. Let your little one breathe at it.",
	feedTip = "Feed your dragon - x2 power while it's full", -- before the guard if not fed and there are enough coins
	-- after a win if the next Gloom is beyond the dragon's power (the server, Core/Combat.huntStage)
	weakFeed = "Stronger Gloom ahead - feed your dragon for x2 power",
	weakGrow = "Your dragon must grow before the next Gloom",
	weakStorm = "The Storm Gloom waits - grow stronger and come back tomorrow",
}

-- the pass buttons at the coins and the pass card (Controllers/PassChips). The "what you get" lines -
-- only what the pass really does (x2: the Economy.nestRate multiplier x2Mult together with VIP and the boost; Auto Collect: Nest - the coins straight to the account,
-- without the pile and its ceiling, while the player is in the game)
-- the glowing egg after the first flight
Strings.GlowEgg = {
	spawn = "A GOLDEN NEST WITH A GLOWING EGG!",
	spawnSub = "A fairy-tale glowing dragon sleeps inside - follow the arrow!", -- the player must understand the value
	take = "You stole the Glowing Egg!",
	takeSub = "RUN HOME - the Gloom is chasing you! It hatches TOMORROW", -- the chase (Combat.chaseEgg)
	caught = "CAUGHT!",
	caughtSub = "The egg flew back to the golden nest - steal it again!",
	escaped = "You got away! Take the egg home",
	-- a sortie on foot, "RUN!" / "SAFE!" (Steal An Egg), the caption on the floor at the gate
	run = "RUN!",
	safe = "SAFE!",
	safeSub = "You stole the glowing egg! It hatches TOMORROW",
	gateWait = "Your dragon waits at the gate - sneak in on foot",
	safeZone = "SAFE ZONE",
	handsFull = "Put your egg in an incubator first",
	toShelf = "Your egg went to the shelf at home", -- an ordinary egg from the hands - to the shelf, a glowing one - into the hands
	guard = "The Gloom guards the egg - defeat them!",
	free = "The guards are gone - steal the egg!",
	home = "The Glowing Egg is safe at home!",
	homeSub = "Come back TOMORROW - your glowing dragon will hatch!",
	hatchIn = "Glowing dragon in {t}",
	cardHatchIn = "Hatches in {t}", -- large in the card above the buttons
	tomorrow = "Tomorrow: your Glowing Dragon hatches!", -- the "tomorrow" line (Gifts) while the egg is on the stand
	tomorrowNote = "Not an ordinary dragon - it shines at night. Come back!",
	ready = "Your glowing egg is hatching!",
	-- the button on the stand - coins take an hour off the timer; the toast after warming
	warm = "Warm the egg",
	warmHint = "-1 h for {n} coins",
	warmed = "Warmer! Your glowing dragon in {t}",
	stepUp = "Step up to the egg!", -- dismounted right at the nest and stands - the egg only after his own step
}

-- the raid screen (Controllers/Glow, Services/Raid)
Strings.Raid = {
	run = "RUN!",
	runHome = "RUN HOME - the Gloom is chasing you!",
	runDragon = "RUN TO YOUR DRAGON!",
	safe = "SAFE!",
	safeSub = "You stole a {rarity} egg! It hatches in {t}",
	safeDragon = "Your dragon scared the Gloom away - ride home!",
	caught = "CAUGHT!",
	caughtSub = "The egg flew back to the nest - steal it again!",
	escaped = "You got away! Take the egg home",
	gateWait = "Your dragon won't go near the Gloom - sneak on foot",
	toShelf = "Your egg went to the shelf at home",
	home = "The egg is in your incubator!",
	homeShelf = "Incubators are full - the egg is on your shelf",
	eggLabel = "{rarity} egg",
	eggIn = "Egg in {t}",
	take = "You stole a {rarity} egg!",
	-- after the egg at home - how many more today; the limit is over - again tomorrow
	dayLeft = "{n} more eggs today - the Gloom gets faster!",
	dayLeftOne = "Last egg today - the Gloom is at its fastest!",
	dayDone = "THAT'S ALL FOR TODAY!",
	dayDoneSub = "Come back tomorrow - {n} new eggs to steal",
	noRoom = "No room at home - hatch an egg or unlock a bowl first",
}

Strings.PassCard = {
	chip = { x2 = "x2", auto = "Auto" },
	tag = "GAME PASS",
	whatYouGet = "WHAT YOU GET",
	forever = "Buy once - keep it forever",
	notNow = "Not now",
	lines = {
		X2Coins_299 = { "Your nest earns double coins", "Every dragon you add earns double too", "Stacks with VIP and coin boosts" },
		AutoCollect_149 = { "Nest coins go straight to your balance", "No more flying back to collect", "No pile cap while you play" },
	},
}

-- "{name} grew to {stage}" + {name="Zap", stage="Adult"} -> "Zap grew to Adult"
function Strings.fill(template: string, values: { [string]: any }): string
	return (template:gsub("{(%w+)}", function(key)
		local v = values[key]
		return if v ~= nil then tostring(v) else "{" .. key .. "}"
	end))
end

return Strings
