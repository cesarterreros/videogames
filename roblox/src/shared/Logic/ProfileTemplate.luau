--!strict
-- The player profile schema (version 1) and its defaults. The only source of default values. Pure, no requires.

local ProfileTemplate = {}

ProfileTemplate.VERSION = 1

-- Crystal (a value in Pedestals) for reference:
-- { SeedId: string, PlantedAt: number, ReadyAt: number, SizeRoll: number,
--   Mutation: "None"|"Glowing"|"Molten"|"Prismatic", InstantGrown: boolean, Shape: number }

local TEMPLATE = {
	Version = 1,
	Coins = 0,
	SeedBag = { Quartz = 1 }, -- [seedId] = count
	Pedestals = {}, -- ["1".."13"] = Crystal; string keys so the table never has array holes
	UnlockedPedestals = 3, -- coin-bought pedestals, max 10
	LampLevel = 0, -- 0..5
	HighestUnlockedTier = 1, -- 1..10
	Codex = {}, -- [seedId] = { None = true, Glowing = true, ... }
	Stats = { Shatters = 0, CoinsEarned = 0 },
	Streak = { Day = 0, LastClaimDate = "" }, -- "YYYY-MM-DD" UTC
	DailyGoals = { Date = "", Goals = {}, BonusClaimed = false }, -- Goals = { {Id, Progress, Claimed} } x3
	WeeklyBest = { WeekId = "", Carats = 0 }, -- e.g. "2026W47"
	Tutorial = { Step = 0, Done = false },
	Monetization = {
		ProcessedReceipts = {}, -- last 100 PurchaseIds
		InstantGrowTokens = { S = 0, M = 0, L = 0 },
		LuckBoostEndsAt = 0,
		StarterPackBought = false,
		AdCounts = { Date = "", FinishNow = 0, Luck = 0, CoinPouch = 0 },
		LastAdAt = 0,
	},
	Settings = { AutoShatter = false, Music = true, Brightness = "Normal" }, -- Brightness: "Dark"|"Normal"|"Bright"
	FirstJoinAt = 0,
	LastJoinAt = 0,
	Sessions = 0,
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- A fresh, independent copy of the default profile.
function ProfileTemplate.new(): { [string]: any }
	return deepCopy(TEMPLATE)
end

ProfileTemplate.deepCopy = deepCopy

return ProfileTemplate
