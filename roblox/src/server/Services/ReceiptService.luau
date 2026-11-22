--!strict
-- The one ProcessReceipt handler: every developer product, bought or earned through a rewarded ad, is granted here,
-- exactly once. For each receipt:
--   1. player not in this server or profile not loaded -> NotProcessedYet (Roblox delivers it again at the next join)
--   2. PurchaseId already recorded -> skip the grant, go to 5
--   3. unknown ProductId -> warn, NotProcessedYet
--   4. grant (no yields) and record the PurchaseId (the newest ReceiptHistory are kept)
--   5. save, and return PurchaseGranted only once the SAVED data holds the PurchaseId; NotProcessedYet after
--      ReceiptSaveTimeoutSeconds (step 2 then stops a second grant when the receipt comes back)
-- Grant functions change data only; this service sends one StateSync and one toast per receipt.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Seeds = require(Shared.Config.Seeds)
local Receipts = require(Shared.Logic.Receipts)
local LuckBoost = require(Shared.Logic.LuckBoost)
local EconomyLogic = require(Shared.Logic.Economy)
local Strings = require(Shared.Strings.Strings)

local RemoteService = require(script.Parent.RemoteService)
local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)
local MonetizationIds = require(script.Parent.MonetizationIds)
local PolicyInfoService = require(script.Parent.PolicyInfoService)
local CrystalService = require(script.Parent.CrystalService)

local ReceiptService = {}

local IS_STUDIO = RunService:IsStudio()
local IAP = Enum.AnalyticsEconomyTransactionType.IAP.Name
local POLL_SECONDS = 0.25

-- Products that feed random crystal rolls (paid-random-items policy, guardrail 5).
local COIN_FEEDING: { [string]: boolean } = {
	CoinPouchS = true,
	CoinPouchM = true,
	CoinPouchL = true,
	SeedBundle = true,
	StarterPack = true,
	LuckBoost = true,
}

export type GrantResult = { toastKey: string, toastParams: { [string]: any }? }
type Grant = (player: Player, data: { [string]: any }, receipt: { [string]: any }) -> GrantResult

local grants: { [string]: Grant } = {}
local grantedEvent = Instance.new("BindableEvent")

-- Fires (player, productKey, isAdReward) after a receipt is granted (not on a replay). For offers and analytics.
ReceiptService.Granted = grantedEvent.Event

local seedById: { [string]: any } = {}

local function productName(key: string): string
	return Strings.get("Product." .. key)
end

local function purchased(key: string): GrantResult
	return { toastKey = "Toast.Purchased", toastParams = { item = productName(key) } }
end

-- The seed of the player's highest unlocked tier (or the closest lower one).
local function highestSeed(data: { [string]: any }): any
	local best = nil
	for _, seed in Seeds do
		if seed.Tier <= data.HighestUnlockedTier and (best == nil or seed.Tier > best.Tier) then
			best = seed
		end
	end
	return best or Seeds[1]
end

local function addSeeds(data: { [string]: any }, seedId: string, count: number)
	data.SeedBag[seedId] = (data.SeedBag[seedId] or 0) + count
end

local function addLuck(data: { [string]: any }, minutes: number)
	local m = data.Monetization
	m.LuckBoostEndsAt = LuckBoost.extend(m.LuckBoostEndsAt, os.time(), minutes, Monetization.LuckBoost.MaxBankMinutes)
end

-- Instant Grow S/M/L: finish the crystal the prompt (or ad) was for, else keep a token of that tier.
local function instantGrow(tier: string): Grant
	local key = "InstantGrow" .. tier
	return function(player, data)
		local index = CrystalService:TakePendingTarget(player, tier)
		if index ~= nil and CrystalService:FinishNow(player, index) then
			return purchased(key)
		end
		data.Monetization.InstantGrowTokens[tier] += 1
		return { toastKey = "Toast.TokenSaved" }
	end
end

local function coinPouch(key: string): Grant
	return function(player, data)
		local mult = Monetization.Products[key].Mult :: number
		local coins = EconomyLogic.coinPouchAmount(Seeds, data.HighestUnlockedTier, mult)
		DataService:AddCoins(player, coins, IAP, key)
		return purchased(key)
	end
end

local function registerGrants()
	grants.InstantGrowS = instantGrow("S")
	grants.InstantGrowM = instantGrow("M")
	grants.InstantGrowL = instantGrow("L")

	-- Grow All with nothing growing (a race with shattering) keeps an L token, so nothing paid is lost.
	grants.GrowAll = function(player, data)
		if CrystalService:FinishAll(player) > 0 then
			return purchased("GrowAll")
		end
		data.Monetization.InstantGrowTokens.L += 1
		return { toastKey = "Toast.TokenSaved" }
	end

	grants.LuckBoost = function(_player, data)
		addLuck(data, Monetization.LuckBoost.Minutes)
		return purchased("LuckBoost")
	end

	grants.CoinPouchS = coinPouch("CoinPouchS")
	grants.CoinPouchM = coinPouch("CoinPouchM")
	grants.CoinPouchL = coinPouch("CoinPouchL")

	grants.SeedBundle = function(_player, data)
		addSeeds(data, highestSeed(data).Id, Monetization.Products.SeedBundle.Count :: number)
		return purchased("SeedBundle")
	end

	-- Once per account; a second purchase (a race between two prompts) becomes the coins and seeds' value in coins.
	grants.StarterPack = function(player, data)
		local pack = Monetization.Products.StarterPack
		local coins = pack.Coins :: number
		local seedId = pack.SeedId :: string
		local count = pack.Count :: number
		if data.Monetization.StarterPackBought then
			local seed = seedById[seedId]
			local value = coins + (if seed then seed.Price * count else 0)
			DataService:AddCoins(player, value, IAP, "StarterPackConverted")
			return { toastKey = "Toast.StarterConverted" }
		end
		DataService:AddCoins(player, coins, IAP, "StarterPack")
		addSeeds(data, seedId, count)
		addLuck(data, pack.LuckMinutes :: number)
		data.Monetization.StarterPackBought = true
		return purchased("StarterPack")
	end
end

-- Waits until the saved copy of the profile holds this PurchaseId (or the timeout passes).
local function waitForSave(profile: any, purchaseId: string): boolean
	if profile:IsActive() then
		profile:Save()
	end
	local deadline = os.clock() + Monetization.ReceiptSaveTimeoutSeconds
	repeat
		local saved = profile.LastSavedData
		if
			type(saved) == "table"
			and type(saved.Monetization) == "table"
			and type(saved.Monetization.ProcessedReceipts) == "table"
			and Receipts.isProcessed(saved.Monetization.ProcessedReceipts, purchaseId)
		then
			return true
		end
		task.wait(POLL_SECONDS)
	until os.clock() >= deadline
	return false
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and DataService:GetProfile(player)
	if player == nil or profile == nil or not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local data = profile.Data
	local m = data.Monetization

	-- From here to the record step nothing yields, so the same receipt can't be granted twice in parallel.
	if not Receipts.isProcessed(m.ProcessedReceipts, purchaseId) then
		local key = MonetizationIds.productKey(receipt.ProductId)
		local grant = key and grants[key]
		if key == nil or grant == nil then
			warn("[Receipt] unknown product " .. tostring(receipt.ProductId) .. "; not processed")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local isAd = receipt.ProductPurchaseChannel == Enum.ProductPurchaseChannel.AdReward
		if COIN_FEEDING[key] and PolicyInfoService:IsRestricted(player) then
			-- Change S: they've paid, so they get it; logged so we notice if it ever happens.
			warn("[Receipt] coin-feeding product " .. key .. " granted to a restricted player")
			Analytics:Custom(player, "Anomaly", 1, {
				[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = "RestrictedPurchase",
				[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = key,
			})
		end
		local ok, result = pcall(grant, player, data, receipt)
		if not ok then
			warn("[Receipt] grant " .. key .. " failed: " .. tostring(result))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		m.ProcessedReceipts = Receipts.record(m.ProcessedReceipts, purchaseId, Monetization.ReceiptHistory)
		if IS_STUDIO then
			print(("[Receipt] %s granted %s (ad=%s, id %s)"):format(player.Name, key, tostring(isAd), purchaseId))
		end
		local granted = result :: GrantResult
		RemoteService:Fire("Toast", player, granted.toastKey, granted.toastParams)
		DataService:SyncState(player)
		if isAd then
			Analytics:Custom(player, "AdRewarded", 1, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = key })
		end
		grantedEvent:Fire(player, key, isAd)
	elseif IS_STUDIO then
		print("[Receipt] replay of " .. purchaseId .. "; not granted again")
	end

	if waitForSave(profile, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	warn("[Receipt] save not confirmed for " .. purchaseId .. "; Roblox will deliver it again at the next join")
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Studio only: the replay test calls the real handler with a receipt table, through a BindableFunction (the
-- command bar loads its own copies of modules, so it can't reach this one directly).
local function hookDebugReceipt()
	if not IS_STUDIO then
		return
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = "DebugProcessReceipt"
	fn.OnInvoke = function(receipt: { [string]: any }): string
		return processReceipt(receipt).Name
	end
	fn.Parent = ServerStorage
end

function ReceiptService:Init()
	for _, seed in Seeds do
		seedById[seed.Id] = seed
	end
	registerGrants()
	for key in Monetization.Products do
		assert(grants[key] ~= nil, "[ReceiptService] no grant for product " .. key)
	end
end

function ReceiptService:Start()
	MarketplaceService.ProcessReceipt = processReceipt -- set once, here only
	hookDebugReceipt()
end

return ReceiptService
