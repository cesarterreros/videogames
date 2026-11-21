--!strict
-- Daily streak, daily goals, the Crystal Codex and seed-tier unlocks. Every reward amount comes from config and
-- every check runs against the caller's own profile; the client only says "claim the daily" or "claim goal N".
-- Dates are UTC "YYYY-MM-DD" strings taken at the moment of each action, so a rollover mid-session just works.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Seeds = require(Shared.Config.Seeds)
local Progression = require(Shared.Config.Progression)
local RollsConfig = require(Shared.Config.Rolls)
local Economy = require(Shared.Logic.Economy)
local Streak = require(Shared.Logic.Streak)
local Goals = require(Shared.Logic.Goals)
local Codex = require(Shared.Logic.Codex)
local WeekId = require(Shared.Logic.WeekId)
local Format = require(Shared.Logic.Format)
local Strings = require(Shared.Strings.Strings)

local RemoteService = require(script.Parent.RemoteService)
local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)

local ProgressionService = {}

local SECONDS_PER_DAY = 86400
local MAX_TIER = #Seeds

-- Server generator for the daily goal draw.
local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

-- Size tiers that count for the ShatterBig goal: Big and every tier after it in the roll table.
local bigSizeTiers: { [string]: boolean } = {}
do
	local reached = false
	for _, band in RollsConfig.Size do
		if band.Name == "Big" then
			reached = true
		end
		if reached then
			bigSizeTiers[band.Name] = true
		end
	end
end

local function toast(player: Player, key: string, params: { [string]: any }?)
	RemoteService:Fire("Toast", player, key, params)
end

local function seedName(seedId: string): string
	return Strings.get("Seed." .. seedId)
end

-- Display name of a mutation in a message; "None" is left out ("New in Codex: Quartz").
local function mutationName(mutation: string): string
	return if mutation == "None" then "" else Strings.get("Mutation." .. mutation)
end

local function seedOfTier(tier: number): Seeds.Seed?
	for _, seed in Seeds do
		if seed.Tier == tier then
			return seed
		end
	end
	return nil
end

-- Draws today's goals if the stored ones are from another UTC day. Returns true if they were redrawn.
local function ensureGoals(data: { [string]: any }): boolean
	local _, rerolled = Goals.ensureToday(
		data.DailyGoals,
		WeekId.dateString(os.time()),
		Progression.GoalPool,
		Progression.GoalsPerDay,
		rng
	)
	return rerolled
end

-- Adds goal progress for one event ("Shatter", "PlantUncommon", "Mutation", "Coins", "Upgrade", "ShatterBig").
-- Changes data only and never syncs: the caller sends one StateSync after all its changes.
function ProgressionService:Track(player: Player, eventName: string, amount: number)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	ensureGoals(data)
	Goals.track(data.DailyGoals, eventName, amount)
end

-- Everything progression does after a shatter, in plan order: codex -> goals -> tier unlock.
-- result is the ShatterResult payload; seed is the shattered seed's config row. Changes data only, no sync.
function ProgressionService:OnShatter(player: Player, result: { [string]: any }, seed: Seeds.Seed)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end

	-- Codex.
	if Codex.record(data.Codex, seed.Id, result.mutation) then
		toast(player, "Toast.CodexNew", { mutation = mutationName(result.mutation), seed = seedName(seed.Id) })
	end

	-- Goals.
	ProgressionService:Track(player, "Shatter", 1)
	ProgressionService:Track(player, "Coins", result.coins)
	if result.mutation ~= "None" then
		ProgressionService:Track(player, "Mutation", 1)
	end
	if bigSizeTiers[result.sizeTier] then
		ProgressionService:Track(player, "ShatterBig", 1)
	end

	-- Unlock: shattering a crystal of your highest unlocked tier opens the next one.
	if seed.Tier == data.HighestUnlockedTier and data.HighestUnlockedTier < MAX_TIER then
		data.HighestUnlockedTier += 1
		local unlocked = seedOfTier(data.HighestUnlockedTier)
		local unlockedId = if unlocked then unlocked.Id else ""
		toast(player, "Toast.SeedUnlocked", { seed = seedName(unlockedId) })
		Analytics:Progression(
			player,
			"SeedTier",
			Enum.AnalyticsProgressionType.Complete,
			data.HighestUnlockedTier,
			unlockedId
		)
	end
end

-- ClaimDaily(): once per UTC day; yesterday's claim continues the 7-day cycle, any other gap restarts at day 1.
local function onClaimDaily(player: Player)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	local now = os.time()
	local ok, newStreak, day =
		Streak.claim(data.Streak, WeekId.dateString(now), WeekId.dateString(now - SECONDS_PER_DAY), #Progression.Streak)
	if not ok or newStreak == nil or day == nil then
		toast(player, "Toast.AlreadyClaimed")
		return
	end
	data.Streak = newStreak

	local reward = Progression.Streak[day]
	if reward.Coins ~= nil then
		DataService:AddCoins(
			player,
			reward.Coins,
			Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
			"Daily_" .. day
		)
	end
	if reward.Seed ~= nil then
		data.SeedBag[reward.Seed] = (data.SeedBag[reward.Seed] or 0) + (reward.Count or 1)
	end

	toast(player, "Toast.DailyClaimed", { day = day })
	Analytics:Custom(player, "StreakClaim", day, nil)
	DataService:SyncState(player)
end

-- ClaimGoal(1 | 2 | 3 | "Bonus"). A goal pays GoalRewardValueMult × BaseValue of your highest unlocked seed;
-- the bonus (all 3 claimed) gives one seed of the next tier. Not claimable -> nothing happens.
local function onClaimGoal(player: Player, which: number | string)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	local rerolled = ensureGoals(data)
	local daily = data.DailyGoals

	if which == "Bonus" then
		if Goals.canClaimBonus(daily) then
			daily.BonusClaimed = true
			local seedId = Economy.surpriseSeedId(Seeds, data.HighestUnlockedTier)
			data.SeedBag[seedId] = (data.SeedBag[seedId] or 0) + 1
			toast(player, "Toast.BonusSeed", { seed = seedName(seedId) })
			Analytics:Custom(player, "GoalsComplete", 1, nil)
			DataService:SyncState(player)
		elseif rerolled then
			DataService:SyncState(player)
		end
		return
	end

	local index = which :: number
	if not Goals.canClaim(daily, index, Progression.GoalPool) then
		if rerolled then
			DataService:SyncState(player)
		end
		return
	end
	local goal = daily.Goals[index]
	goal.Claimed = true
	local coins = Economy.goalReward(Seeds, data.HighestUnlockedTier, Progression.GoalRewardValueMult)
	DataService:AddCoins(player, coins, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Goal_" .. goal.Id)
	toast(player, "Toast.GoalClaimed", { coins = Format.compact(coins) })
	DataService:SyncState(player)
end

-- First load of the day draws the goals; a sync follows only if anything changed.
-- Reads the live profile through GetData: ProfileLoaded is a BindableEvent, which hands listeners a copy of
-- any table argument, so changing the event's own data argument would be lost.
local function onProfileLoaded(player: Player)
	local data = DataService:GetData(player)
	if data ~= nil and ensureGoals(data) then
		DataService:SyncState(player)
	end
end

function ProgressionService:Init()
	RemoteService:On("ClaimDaily", onClaimDaily)
	RemoteService:On("ClaimGoal", onClaimGoal)
end

function ProgressionService:Start()
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	-- Profiles that finished loading before this connected.
	for _, player in Players:GetPlayers() do
		onProfileLoaded(player)
	end
end

return ProgressionService
