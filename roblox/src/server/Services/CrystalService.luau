--!strict
-- Plants, grows and shatters crystals. The server owns every roll, timer and coin: the client only asks
-- "plant seed X on pedestal N" or "shatter pedestal N", and every request is checked against the caller's
-- own profile and plot. Public crystal fields are mirrored onto pedestal attributes for the client renderer;
-- the size roll never leaves the server until the crystal is shattered.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.Game)
local Seeds = require(Shared.Config.Seeds)
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Config.Progression)
local RollsConfig = require(Shared.Config.Rolls)
local Growth = require(Shared.Logic.Growth)
local Rolls = require(Shared.Logic.Rolls)
local WeekId = require(Shared.Logic.WeekId)
local EconomyLogic = require(Shared.Logic.Economy)
local Codex = require(Shared.Logic.Codex)
local Surge = require(Shared.Logic.Surge)

local RemoteService = require(script.Parent.RemoteService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local PlotService = require(script.Parent.PlotService)
local TutorialService = require(script.Parent.TutorialService)

local CrystalService = {}

-- Services that run after this one in Main.server. Required on first use, not at the top, so no require
-- cycle can form (they're only called at runtime, from remote handlers).
local function progression(): any
	return require(script.Parent.ProgressionService)
end
local function social(): any
	return require(script.Parent.SocialService)
end
local function leaderboard(): any
	return require(script.Parent.LeaderboardService)
end

local IS_STUDIO = RunService:IsStudio()

local seedById: { [string]: Seeds.Seed } = {}
local mutationMult: { [string]: number } = { None = 1 }

-- One server-wide generator; Rolls takes it as a plain () -> number.
local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

-- Pedestals 1..MaxCoinPedestals can be unlocked with coins; 11–13 (the pass) stay locked in this batch.
local function isUnlocked(data: { [string]: any }, index: number): boolean
	return index <= math.min(data.UnlockedPedestals, Economy.MaxCoinPedestals)
end

-- Copies a crystal's public fields onto its pedestal (or clears them). SizeRoll is never written.
local function applyAttributes(pedestal: BasePart, crystal: { [string]: any }?)
	if crystal == nil then
		pedestal:SetAttribute("SeedId", "")
		pedestal:SetAttribute("PlantedAt", 0)
		pedestal:SetAttribute("ReadyAt", 0)
		pedestal:SetAttribute("Mutation", "None")
		pedestal:SetAttribute("Shape", 0)
	else
		pedestal:SetAttribute("SeedId", crystal.SeedId)
		pedestal:SetAttribute("PlantedAt", crystal.PlantedAt)
		pedestal:SetAttribute("ReadyAt", crystal.ReadyAt)
		pedestal:SetAttribute("Mutation", crystal.Mutation)
		pedestal:SetAttribute("Shape", if type(crystal.Shape) == "number" then crystal.Shape else 1)
	end
end

-- Writes the unlock state and every stored crystal of a player onto their plot's pedestals.
local function refreshPlot(player: Player, data: { [string]: any })
	for index = 1, GameConfig.MaxPedestals do
		local pedestal = PlotService:GetPedestal(player, index)
		if pedestal ~= nil then
			local unlocked = isUnlocked(data, index)
			pedestal:SetAttribute("Unlocked", unlocked)
			MapService.setPedestalLook(pedestal, unlocked)
			applyAttributes(pedestal, data.Pedestals[tostring(index)])
		end
	end
end

-- Studio only (Decision 1): top the bag up to a few Quartz for testing. Not during the tutorial (batch 4), whose
-- steps depend on the bag holding exactly what the tutorial gives.
local function studioTopUp(player: Player, data: { [string]: any })
	if not IS_STUDIO or TutorialService:IsActive(player) then
		return
	end
	local count = data.SeedBag.Quartz or 0
	if count < GameConfig.DevStudioSeedTopUp then
		data.SeedBag.Quartz = GameConfig.DevStudioSeedTopUp
		print(
			("[Crystal] Studio top-up for %s: Quartz %d -> %d"):format(
				player.Name,
				count,
				GameConfig.DevStudioSeedTopUp
			)
		)
	end
end

-- Plant(index, seedId): validated in this order, and nothing changes unless every check passes.
local function onPlant(player: Player, index: number, seedId: string)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	local pedestal = PlotService:GetPedestal(player, index) -- nil unless it is in the caller's own plot
	local seed = seedById[seedId]
	local key = tostring(index)
	local count = data.SeedBag[seedId]
	if pedestal == nil or seed == nil or not isUnlocked(data, index) or data.Pedestals[key] ~= nil then
		return
	end
	if type(count) ~= "number" or count < 1 then
		return
	end

	-- Tutorial favours, asked before the crystal is stored (they count the plants made so far): the first
	-- crystal grows in Tutorial.GrowSeconds and the 3rd plant overall is Glowing.
	local growOverride = TutorialService:GrowSecondsOverride(player)
	local forcedMutation = TutorialService:ForcedMutation(player)

	-- Take the seed.
	data.SeedBag[seedId] = if count - 1 > 0 then count - 1 else nil

	-- Roll everything now; the size stays secret until the shatter. During a Crystal Surge (the first
	-- SurgeMinutes of every UTC hour) mutation chances are multiplied.
	local plantedAt = os.time()
	local chanceMult = if Surge.isActive(plantedAt, Economy.SurgeMinutes) then Economy.SurgeMutationMult else 1
	local sizeRoll = Rolls.size(rng, RollsConfig.Size)
	local mutation = forcedMutation or Rolls.mutation(rng, RollsConfig.Mutation, chanceMult)
	local shape = Rolls.shape(rng)
	local growSeconds = growOverride or Growth.growSeconds(seed.GrowSeconds, data.LampLevel, Economy.LampStep)
	local crystal = {
		SeedId = seedId,
		PlantedAt = plantedAt,
		ReadyAt = plantedAt + growSeconds,
		SizeRoll = sizeRoll,
		Mutation = mutation,
		InstantGrown = false,
		Shape = shape,
	}
	data.Pedestals[key] = crystal

	applyAttributes(pedestal, crystal)
	if seed.Tier >= 3 then
		progression():Track(player, "PlantUncommon", 1)
	end
	TutorialService:OnEvent(player, "Plant")
	DataService:SyncState(player)
end

-- Shatters one ready crystal of the caller and returns the ShatterResult payload, or nil if not allowed.
-- No yields in here: the crystal is removed before the coins are added, so a repeat request finds nothing.
local function shatterOne(player: Player, data: { [string]: any }, index: number): { [string]: any }?
	local key = tostring(index)
	local crystal = data.Pedestals[key]
	local pedestal = PlotService:GetPedestal(player, index)
	if crystal == nil or pedestal == nil then
		return nil
	end
	local now = os.time()
	local seed = seedById[crystal.SeedId]
	if seed == nil or not Growth.isReady(now, crystal.ReadyAt) then
		return nil
	end

	-- 1. Remove first.
	data.Pedestals[key] = nil

	-- 2. Value. A completed Codex entry (bonus from the shatter after the one that completes it) and friends
	-- in the server multiply the coins.
	local coinMult = EconomyLogic.shatterCoinMult(
		Codex.isComplete(data.Codex, seed.Id),
		Progression.CodexBonus,
		social():FriendBonus(player)
	)
	local overgrowth =
		Growth.overgrowth(now, crystal.ReadyAt, RollsConfig.Overgrowth.PerHour, RollsConfig.Overgrowth.Cap)
	local coins, carats = Growth.shatterValue(
		seed.BaseValue,
		seed.BaseCarats,
		crystal.SizeRoll,
		mutationMult[crystal.Mutation] or 1,
		overgrowth,
		coinMult
	)
	carats = math.floor(carats * 100 + 0.5) / 100 -- 2 decimals, the leaderboard's precision

	-- 3. Grant (one economy Source event), plus the tutorial bonus on the tutorial's first shatter as its own
	-- Onboarding event. The bonus is read here, before step 6b moves the tutorial on.
	DataService:AddCoins(player, coins, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, seed.Id)
	data.Stats.Shatters += 1
	data.Stats.CoinsEarned += coins
	local bonusCoins = TutorialService:BonusCoins(player)
	if bonusCoins > 0 then
		DataService:AddCoins(player, bonusCoins, Enum.AnalyticsEconomyTransactionType.Onboarding.Name, "TutorialBonus")
	end

	local result = {
		pedestal = index,
		coins = coins,
		carats = carats,
		mutation = crystal.Mutation,
		sizeTier = Rolls.sizeTierName(crystal.SizeRoll, RollsConfig.Size),
		newBest = false,
		instantGrown = crystal.InstantGrown == true,
		bonusCoins = bonusCoins, -- batch 4: the tutorial bonus (0 normally), shown on the result card
		seedId = seed.Id, -- batch 4: the result card pitches the shatter sound by the seed's tier
	}

	-- 4. Codex, goals, tier unlock.
	progression():OnShatter(player, result, seed)

	-- 5. Weekly best and the leaderboard queue.
	local week = WeekId.fromUnix(now)
	if data.WeeklyBest.WeekId ~= week then
		data.WeeklyBest = { WeekId = week, Carats = 0 }
	end
	if carats > data.WeeklyBest.Carats then
		data.WeeklyBest.Carats = carats
		result.newBest = true
		leaderboard():Submit(player, carats, result.instantGrown)
	end

	-- 6. Rare finds are announced to the server.
	social():Announce(player, result, seed)

	-- 6b. Tutorial steps 3 (first shatter) and 7 (first mutation). Data only.
	TutorialService:OnEvent(player, "Shatter", { mutation = crystal.Mutation })

	-- 7. Clear the pedestal. The caller sends ShatterResult, then StateSync.
	applyAttributes(pedestal, nil)

	return result
end

-- Shatter(index): one crystal.
local function onShatter(player: Player, index: number)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	local result = shatterOne(player, data, index)
	if result ~= nil then
		RemoteService:Fire("ShatterResult", player, result)
		DataService:SyncState(player)
	end
end

-- ShatterAll(): every ready crystal in the caller's cave, one ShatterResult each, one StateSync at the end.
local function onShatterAll(player: Player)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	local any = false
	for index = 1, GameConfig.MaxPedestals do
		local result = shatterOne(player, data, index)
		if result ~= nil then
			any = true
			RemoteService:Fire("ShatterResult", player, result)
		end
	end
	if any then
		DataService:SyncState(player)
	end
end

function CrystalService:Init()
	for _, seed in Seeds do
		seedById[seed.Id] = seed
	end
	for _, band in RollsConfig.Mutation do
		mutationMult[band.Name] = band.Mult
	end

	RemoteService:On("Plant", onPlant)
	RemoteService:On("Shatter", onShatter)
	RemoteService:On("ShatterAll", onShatterAll)
end

-- Runs once per player when their plot is assigned: restores their crystals onto the pedestals.
local function onPlotAssigned(player: Player)
	-- A plot is assigned only after the profile has loaded, so the data is normally there.
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	studioTopUp(player, data)
	refreshPlot(player, data)
	DataService:SyncState(player)
end

function CrystalService:Start()
	PlotService.PlotAssigned:Connect(onPlotAssigned)
	-- PlotService:Start runs first and may already have assigned plots (its own catch-up) before this connected.
	for _, player in Players:GetPlayers() do
		if PlotService:GetPlot(player) ~= nil then
			onPlotAssigned(player)
		end
	end
end

return CrystalService
