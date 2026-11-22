--!strict
-- Rewarded video ads: RequestAd(placement, pedestal?) -> every check passes -> the server shows an ad whose reward is
-- a developer product, granted ONLY by ReceiptService on the AdReward channel (never here).
-- Checks, in order: no tutorial; the placement's product exists in this experience; paid-random-items policy (Luck and
-- CoinPouch feed random rolls); no ad already running for this player; daily caps and the 60 s cooldown (AdCaps);
-- the placement's own rule (FinishNow: your crystal with 15 min or less; Luck: 5 min or less of boost left;
-- CoinPouch: today's daily reward claimed). The request is COUNTED before the ad is shown, so an ad closed early still
-- uses the cooldown and the cap (Decision 1). The client's GetAdAvailabilityNowAsync check comes before all this
-- (change P: AreAdsAllowed is not used).

local AdService = game:GetService("AdService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local AdCaps = require(Shared.Logic.AdCaps)
local LuckBoost = require(Shared.Logic.LuckBoost)
local WeekId = require(Shared.Logic.WeekId)

local RemoteService = require(script.Parent.RemoteService)
local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)
local MonetizationIds = require(script.Parent.MonetizationIds)
local PolicyInfoService = require(script.Parent.PolicyInfoService)
local TutorialService = require(script.Parent.TutorialService)
local CrystalService = require(script.Parent.CrystalService)

local RewardedAdService = {}

local IS_STUDIO = RunService:IsStudio()

-- The developer product each placement rewards (each is also sold for Robux: guardrail 6).
local REWARD_PRODUCT: { [string]: string } = {
	FinishNow = "InstantGrowS",
	Luck = "LuckBoost",
	CoinPouch = "CoinPouchS",
}

-- Placements whose reward feeds random crystal rolls (hidden and refused for restricted players).
local COIN_FEEDING: { [string]: boolean } = { Luck = true, CoinPouch = true }

local LUCK_AD_MAX_LEFT_SECONDS = 5 * 60 -- monetization spec, ad #2

-- When each player's current ad request started (os.clock). Ads last 6–30 s; a request older than RUNNING_MAX_SECONDS
-- counts as finished, so an ad call that never returns can't block ads for the rest of the session.
local RUNNING_MAX_SECONDS = 120
local running: { [Player]: number } = {}

local function toast(player: Player, key: string, params: { [string]: any }?)
	RemoteService:Fire("Toast", player, key, params)
end

local function refuse(player: Player, placement: string, reason: string)
	if IS_STUDIO then
		print(("[Ad] %s %s refused: %s"):format(player.Name, placement, reason))
	end
end

-- The placement's own rule. Returns false (and why) if the ad isn't allowed right now.
local function placementAllows(
	player: Player,
	data: { [string]: any },
	placement: string,
	pedestal: number?,
	now: number
): (boolean, string?)
	if placement == "FinishNow" then
		if pedestal == nil then
			return false, "no pedestal"
		end
		local left = CrystalService:SecondsLeft(player, pedestal)
		if left == nil or CrystalService:InstantGrowTier(left) ~= "S" then
			return false, "target not yours, not growing, or more than 15 min left"
		end
		return true, nil
	elseif placement == "Luck" then
		if not LuckBoost.canWatchAd(now, data.Monetization.LuckBoostEndsAt, LUCK_AD_MAX_LEFT_SECONDS) then
			return false, "boost has more than 5 min left"
		end
		return true, nil
	elseif placement == "CoinPouch" then
		if data.Streak.LastClaimDate ~= WeekId.dateString(now) then
			return false, "daily reward not claimed today"
		end
		return true, nil
	end
	return false, "unknown placement"
end

local function onRequestAd(player: Player, placement: string, pedestal: number?)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	if TutorialService:IsActive(player) then
		return refuse(player, placement, "tutorial")
	end
	local productKey = REWARD_PRODUCT[placement]
	local productId = productKey and MonetizationIds.productId(productKey)
	if productKey == nil or productId == nil then
		return refuse(player, placement, "no product in this experience")
	end
	if COIN_FEEDING[placement] and PolicyInfoService:IsRestricted(player) then
		return refuse(player, placement, "paid random items restricted")
	end
	local startedAt = running[player]
	if startedAt ~= nil and os.clock() - startedAt < RUNNING_MAX_SECONDS then
		return refuse(player, placement, "an ad is already running")
	end

	local now = os.time()
	local today = WeekId.dateString(now)
	local m = data.Monetization
	local ok, reason = AdCaps.check(m.AdCounts, today, placement, now, m.LastAdAt, Monetization.Ads)
	if not ok then
		if reason == "Cooldown" then
			toast(player, "Toast.AdCooldown", { seconds = AdCaps.cooldownLeft(now, m.LastAdAt, Monetization.Ads) })
		elseif reason == "PlacementCap" or reason == "DailyCap" then
			toast(player, "Toast.AdLimit")
		end
		return refuse(player, placement, tostring(reason))
	end
	local allowed, why = placementAllows(player, data, placement, pedestal, now)
	if not allowed then
		return refuse(player, placement, tostring(why))
	end

	-- Count the request now (anti-abuse), and remember the FinishNow target for the receipt.
	m.AdCounts = AdCaps.recordRequest(m.AdCounts, today, placement)
	m.LastAdAt = now
	if placement == "FinishNow" and pedestal ~= nil then
		CrystalService:SetPendingTarget(player, "S", pedestal)
	end
	DataService:SyncState(player)
	Analytics:Custom(player, "AdRequested", 1, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = placement })

	local myStart = os.clock()
	running[player] = myStart
	local shown, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(productId)
		return AdService:ShowRewardedVideoAdAsync(player, reward)
	end)
	if running[player] == myStart then
		running[player] = nil
	end
	if IS_STUDIO then
		print(
			("[Ad] %s %s -> %s"):format(
				player.Name,
				placement,
				if shown then tostring(result) else "error: " .. tostring(result)
			)
		)
	end
	if player.Parent ~= Players then
		return
	end
	-- The reward arrives through ProcessReceipt. The result is used only for this message; closing the ad early
	-- (ShowInterrupted) gets none.
	if not shown or (result ~= Enum.ShowAdResult.ShowCompleted and result ~= Enum.ShowAdResult.ShowInterrupted) then
		toast(player, "Toast.NoAd")
	end
end

function RewardedAdService:Init()
	RemoteService:On("RequestAd", onRequestAd)
end

function RewardedAdService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		running[player] = nil
	end)
end

return RewardedAdService
