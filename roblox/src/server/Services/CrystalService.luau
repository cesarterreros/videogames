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
local InstantGrow = require(Shared.Logic.InstantGrow)
local LuckBoost = require(Shared.Logic.LuckBoost)
local MonetizationConfig = require(Shared.Config.Monetization)

local Analytics = require(script.Parent.Analytics)
local RemoteService = require(script.Parent.RemoteService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local PlotService = require(script.Parent.PlotService)
local TutorialService = require(script.Parent.TutorialService)
local MonetizationIds = require(script.Parent.MonetizationIds)
local PassService = require(script.Parent.PassService)

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
local function offers(): any
	return require(script.Parent.OfferService)
end

local IS_STUDIO = RunService:IsStudio()

local seedById: { [string]: Seeds.Seed } = {}
local mutationMult: { [string]: number } = { None = 1 }

-- One server-wide generator; Rolls takes it as a plain () -> number.
local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

-- Pedestals 1..MaxCoinPedestals are unlocked with coins; 11–13 only while the Extra Pedestals pass is confirmed.
-- Without it, crystals already growing there still finish and can be shattered, but nothing new is planted.
local function isUnlocked(player: Player, data: { [string]: any }, index: number): boolean
	if index <= Economy.MaxCoinPedestals then
		return index <= math.min(data.UnlockedPedestals, Economy.MaxCoinPedestals)
	end
	return PassService:Owns(player, "ExtraPedestals")
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
			local unlocked = isUnlocked(player, data, index)
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

-- Plants seedId on pedestal index for the caller: validated in this order, and nothing changes unless every check
-- passes. Data and pedestal attributes only; returns true if planted (the caller sends the StateSync).
local function plantOne(player: Player, data: { [string]: any }, index: number, seedId: string): boolean
	local pedestal = PlotService:GetPedestal(player, index) -- nil unless it is in the caller's own plot
	local seed = seedById[seedId]
	local key = tostring(index)
	local count = data.SeedBag[seedId]
	if pedestal == nil or seed == nil or not isUnlocked(player, data, index) or data.Pedestals[key] ~= nil then
		return false
	end
	if type(count) ~= "number" or count < 1 then
		return false
	end

	-- Tutorial favours, asked before the crystal is stored (they count the plants made so far): the first
	-- crystal grows in Tutorial.GrowSeconds and the 3rd plant overall is Glowing.
	local growOverride = TutorialService:GrowSecondsOverride(player)
	local forcedMutation = TutorialService:ForcedMutation(player)

	-- Take the seed.
	data.SeedBag[seedId] = if count - 1 > 0 then count - 1 else nil

	-- Roll everything now; the size stays secret until the shatter. Mutation chances are multiplied during a
	-- Crystal Surge (the first SurgeMinutes of every UTC hour) and by an active Luck Boost, ×3 at most together.
	-- Nothing paid touches the size roll (guardrail 1). The tutorial's favours win over every multiplier (change K).
	local plantedAt = os.time()
	local luck = MonetizationConfig.LuckBoost
	local chanceMult = LuckBoost.chanceMult(
		plantedAt,
		data.Monetization.LuckBoostEndsAt,
		Surge.isActive(plantedAt, Economy.SurgeMinutes),
		luck.Mult,
		Economy.SurgeMutationMult,
		luck.MaxTotalMult
	)
	local sizeRoll = Rolls.size(rng, RollsConfig.Size)
	local mutation = forcedMutation or Rolls.mutation(rng, RollsConfig.Mutation, chanceMult)
	local shape = Rolls.shape(rng)
	-- Fast Grow halves the growth phase only (stacks with the lamp by multiplying); overgrowth is untouched.
	local speedMult = if PassService:Owns(player, "FastGrow")
		then MonetizationConfig.Passes.FastGrow.GrowMult :: number
		else 1
	local growSeconds = growOverride
		or Growth.growSeconds(seed.GrowSeconds, data.LampLevel, Economy.LampStep, speedMult)
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
	return true
end

-- Plant(index, seedId) from the client.
local function onPlant(player: Player, index: number, seedId: string)
	local data = DataService:GetData(player)
	if data ~= nil and plantOne(player, data, index, seedId) then
		DataService:SyncState(player)
	end
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
	-- Double Coins multiplies these shatter coins only (not the tutorial bonus, daily rewards, goals or pouches).
	local coinMult = EconomyLogic.shatterCoinMult(
		Codex.isComplete(data.Codex, seed.Id),
		Progression.CodexBonus,
		social():FriendBonus(player)
	) * (if PassService:Owns(player, "DoubleCoins")
		then MonetizationConfig.Passes.DoubleCoins.CoinMult :: number
		else 1)
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

	-- 4b. MutationFound (batch 6, task 6): value = the multiplier; the tutorial's guaranteed Glowing counts too.
	if crystal.Mutation ~= "None" then
		Analytics:Custom(player, "MutationFound", mutationMult[crystal.Mutation] or 1, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = crystal.Mutation,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = seed.Id,
		})
	end

	-- 5. Weekly best and the leaderboard queue.
	-- Instant-grown crystals skip this step entirely (guardrail 2, change L): they neither raise your weekly best
	-- nor reach the board, so they can't block a later legitimate best.
	local week = WeekId.fromUnix(now)
	if data.WeeklyBest.WeekId ~= week then
		data.WeeklyBest = { WeekId = week, Carats = 0 }
	end
	if not result.instantGrown and carats > data.WeeklyBest.Carats then
		data.WeeklyBest.Carats = carats
		result.newBest = true
		leaderboard():Submit(player, carats, result.instantGrown)
		-- WeeklyBest (batch 6, task 6): value = the new best's carats.
		Analytics:Custom(player, "WeeklyBest", carats, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = seed.Id,
		})
	end

	-- 6. Rare finds are announced to the server.
	social():Announce(player, result, seed)

	-- 6b. Tutorial steps 3 (first shatter) and 7 (first mutation). Data only.
	TutorialService:OnEvent(player, "Shatter", { mutation = crystal.Mutation })

	-- 6c. Batch 5: the session's shatter count for the Starter Pack offer (it decides; the client waits for the card).
	offers():NoteShatter(player)

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

-- Batch 5: Auto Shatter. -----------------------------------------------------------------------------------------
-- For an owner of the pass with the toggle on, online and past the tutorial: every ready crystal is shattered
-- (one ShatterResult each) and the same seed is replanted if the bag has one; one StateSync at the end.
-- It runs only from the server loop in Start, so it never runs offline (overgrowth stays a real choice).
local AUTO_SHATTER_SECONDS = 2

function CrystalService:AutoShatter(player: Player)
	local data = DataService:GetData(player)
	if
		data == nil
		or data.Settings.AutoShatter ~= true
		or not PassService:Owns(player, "AutoShatter")
		or TutorialService:IsActive(player)
	then
		return
	end
	local any = false
	for index = 1, GameConfig.MaxPedestals do
		local crystal = data.Pedestals[tostring(index)]
		local seedId = crystal and crystal.SeedId
		local result = shatterOne(player, data, index)
		if result ~= nil then
			any = true
			RemoteService:Fire("ShatterResult", player, result)
			plantOne(player, data, index, seedId)
		end
	end
	if any then
		DataService:SyncState(player)
	end
end

-- Batch 5: Instant Grow. ---------------------------------------------------------------------------------------
-- A pending target remembers which crystal a purchase prompt (or a FinishNow ad) is for, per tier, for
-- PendingTargetSeconds. The receipt finishes that crystal, or becomes a token of that tier if it's gone.

local TIER_LIMITS = {
	S = MonetizationConfig.Products.InstantGrowS.MaxSeconds :: number,
	M = MonetizationConfig.Products.InstantGrowM.MaxSeconds :: number,
}

local pending: { [Player]: { [string]: { index: number, expiresAt: number } } } = {}

local function toast(player: Player, key: string, params: { [string]: any }?)
	RemoteService:Fire("Toast", player, key, params)
end

-- Seconds until the caller's crystal on `index` is ready; nil if there's no crystal of theirs there or it's ready.
function CrystalService:SecondsLeft(player: Player, index: number): number?
	local data = DataService:GetData(player)
	if data == nil or PlotService:GetPedestal(player, index) == nil then
		return nil
	end
	local crystal = data.Pedestals[tostring(index)]
	if crystal == nil then
		return nil
	end
	local left = crystal.ReadyAt - os.time()
	return if left > 0 then left else nil
end

-- The Instant Grow tier a crystal with `secondsLeft` needs: S (15 min or less), M (2 h or less) or L.
function CrystalService:InstantGrowTier(secondsLeft: number): InstantGrow.Tier
	return InstantGrow.tierFor(secondsLeft, TIER_LIMITS)
end

function CrystalService:SetPendingTarget(player: Player, tier: string, index: number)
	local set = pending[player]
	if set == nil then
		set = {}
		pending[player] = set
	end
	set[tier] = { index = index, expiresAt = os.time() + MonetizationConfig.PendingTargetSeconds }
end

-- The pedestal a tier's purchase was for, if it hasn't expired. Taking it clears it.
function CrystalService:TakePendingTarget(player: Player, tier: string): number?
	local set = pending[player]
	local target = set and set[tier]
	if set == nil or target == nil then
		return nil
	end
	set[tier] = nil
	return if os.time() <= target.expiresAt then target.index else nil
end

-- Makes the caller's growing crystal on `index` ready now and marks it instant-grown (it won't count for the
-- weekly board). Data and pedestal attributes only: the caller sends the StateSync. False if nothing is growing there.
function CrystalService:FinishNow(player: Player, index: number): boolean
	local data = DataService:GetData(player)
	local pedestal = PlotService:GetPedestal(player, index)
	if data == nil or pedestal == nil or CrystalService:SecondsLeft(player, index) == nil then
		return false
	end
	local crystal = data.Pedestals[tostring(index)]
	crystal.ReadyAt = os.time()
	crystal.InstantGrown = true
	applyAttributes(pedestal, crystal)
	return true
end

-- Batch 6 (AdminService): re-applies the caller's profile to their pedestals (unlock look, crystal attributes)
-- after an admin command rewrote the profile. Data was already changed; this only redraws. No sync.
function CrystalService:RefreshPlot(player: Player)
	local data = DataService:GetData(player)
	if data ~= nil then
		refreshPlot(player, data)
	end
end

-- Finishes every growing crystal of the caller (Grow All). Returns how many. No sync.
function CrystalService:FinishAll(player: Player): number
	local count = 0
	for index = 1, GameConfig.MaxPedestals do
		if CrystalService:FinishNow(player, index) then
			count += 1
		end
	end
	return count
end

-- RequestInstantGrow(index) -> productId?: the server picks the tier, remembers the target and returns the
-- product to prompt. Nothing is sold during the tutorial or in an experience without product IDs.
local function onRequestInstantGrow(player: Player, index: number): number?
	if TutorialService:IsActive(player) then
		return nil
	end
	local left = CrystalService:SecondsLeft(player, index)
	if left == nil then
		return nil
	end
	local tier = CrystalService:InstantGrowTier(left)
	local productId = MonetizationIds.productId(InstantGrow.productKey(tier))
	if productId == nil then
		return nil
	end
	CrystalService:SetPendingTarget(player, tier, index)
	return productId
end

-- UseToken(index): spends the smallest saved Instant Grow token that covers this crystal.
local function onUseToken(player: Player, index: number)
	local data = DataService:GetData(player)
	if data == nil or TutorialService:IsActive(player) then
		return
	end
	local left = CrystalService:SecondsLeft(player, index)
	if left == nil then
		return
	end
	local tokens = data.Monetization.InstantGrowTokens
	local tier = InstantGrow.pickToken(tokens, CrystalService:InstantGrowTier(left))
	if tier == nil then
		return
	end
	tokens[tier] -= 1
	CrystalService:FinishNow(player, index)
	toast(player, "Toast.TokenUsed")
	DataService:SyncState(player)
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
	RemoteService:On("RequestInstantGrow", onRequestInstantGrow)
	RemoteService:On("UseToken", onUseToken)
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
	-- Extra Pedestals turning on (or, in Studio tests, off) redraws the plot's unlock state.
	PassService.OwnershipChanged:Connect(function(player: Player, passKey: string)
		local data = DataService:GetData(player)
		if passKey == "ExtraPedestals" and data ~= nil and PlotService:GetPlot(player) ~= nil then
			refreshPlot(player, data)
			DataService:SyncState(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTO_SHATTER_SECONDS)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(CrystalService.AutoShatter, CrystalService, player)
				if not ok then
					warn("[Crystal] AutoShatter failed for " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)
	-- PlotService:Start runs first and may already have assigned plots (its own catch-up) before this connected.
	for _, player in Players:GetPlayers() do
		if PlotService:GetPlot(player) ~= nil then
			onPlotAssigned(player)
		end
	end
end

return CrystalService
