--!strict
-- The session's single popup offer (kid-safe selling): at most ONE popup per session, and never during the tutorial.
-- The server decides and sends the "Offer" remote ({ kind = "StarterPack" | "DoubleCoins" }); the client shows the
-- card. Day 1 (FirstJoinAt is today, UTC) players only ever get the Starter Pack, on their 10th shatter of the
-- session. Day 2+ players only ever get Double Coins, once 30 s after the profile loads. An offer also needs the
-- tutorial to be done, the player not restricted by policy, and this experience to actually sell the item.
-- Funnel "FirstPurchase": 1 OfferShown (when the card is sent), 2 PromptOpened (the prompt closed, any outcome),
-- 3 Purchased (the receipt / the pass turned on). This service changes NO data, grants NOTHING and never yields
-- inside an event handler (only task.delay schedules work).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeekId = require(Shared.Logic.WeekId)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local MonetizationIds = require(script.Parent.MonetizationIds)
local PassService = require(script.Parent.PassService)
local PolicyInfoService = require(script.Parent.PolicyInfoService)
local ReceiptService = require(script.Parent.ReceiptService)
local RemoteService = require(script.Parent.RemoteService)
local TutorialService = require(script.Parent.TutorialService)

local OfferService = {}

local IS_STUDIO = RunService:IsStudio()

local STARTER_PACK = "StarterPack"
local DOUBLE_COINS = "DoubleCoins"
local FUNNEL_NAME = "FirstPurchase"
local STARTER_PACK_SHATTERS = 10
local DOUBLE_COINS_DELAY_SECONDS = 30

-- In-memory only: cleared on PlayerRemoving, never saved in the profile.
type State = {
	shatters: number,
	shown: boolean,
	kind: string?,
	funnelId: string?,
	promptLogged: boolean,
	purchasedLogged: boolean,
	scheduled: boolean,
}

local states: { [Player]: State } = {}

local function newState(): State
	return {
		shatters = 0,
		shown = false,
		kind = nil,
		funnelId = nil,
		promptLogged = false,
		purchasedLogged = false,
		scheduled = false,
	}
end

-- "Day 1": the profile's first join happened on today's UTC date.
local function isDayOne(data: { [string]: any }): boolean
	return WeekId.dateString(data.FirstJoinAt) == WeekId.dateString(os.time())
end

-- The common conditions for ANY offer: a fresh session state, a loaded profile, and no running tutorial.
local function canOffer(player: Player): boolean
	local state = states[player]
	if state == nil or state.shown then
		return false
	end
	local data = DataService:GetData(player)
	if data == nil then
		return false
	end
	return data.Tutorial.Done == true and not TutorialService:IsActive(player)
end

-- Sends the card and logs funnel step 1. Nothing here yields.
local function show(player: Player, kind: string)
	local state = states[player]
	if state == nil then
		return
	end
	local funnelId = tostring(player.UserId) .. "-" .. tostring(os.time())
	state.shown = true
	state.kind = kind
	state.funnelId = funnelId
	RemoteService:Fire("Offer", player, { kind = kind })
	Analytics:Custom(player, "OfferShown", 1, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = kind })
	Analytics:Funnel(player, FUNNEL_NAME, funnelId, 1, "OfferShown")
	if IS_STUDIO then
		print(("[Offer] %s shown %s"):format(player.Name, kind))
	end
end

-- Funnel step 2, once per session: the purchase prompt of the shown card closed (any outcome).
local function notePromptOpened(player: Player, kind: string)
	local state = states[player]
	if state == nil or state.promptLogged or not state.shown or state.kind ~= kind then
		return
	end
	local funnelId = state.funnelId
	if funnelId == nil then
		return
	end
	state.promptLogged = true
	Analytics:Funnel(player, FUNNEL_NAME, funnelId, 2, "PromptOpened")
end

-- Funnel step 3, once per session: the shown card was actually bought.
local function notePurchased(player: Player, kind: string)
	local state = states[player]
	if state == nil or state.purchasedLogged or not state.shown or state.kind ~= kind then
		return
	end
	local funnelId = state.funnelId
	if funnelId == nil then
		return
	end
	state.purchasedLogged = true
	Analytics:Funnel(player, FUNNEL_NAME, funnelId, 3, "Purchased")
	Analytics:Custom(player, "OfferPurchased", 1, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = kind })
	if IS_STUDIO then
		print(("[Offer] %s purchased %s"):format(player.Name, kind))
	end
end

-- Day 1: the Starter Pack card, at the 10th shatter of the session only.
local function tryStarterPack(player: Player)
	if not canOffer(player) then
		return
	end
	local data = DataService:GetData(player)
	if data == nil or not isDayOne(data) then
		return
	end
	if data.Monetization.StarterPackBought == true then
		return
	end
	if PolicyInfoService:IsRestricted(player) then
		return
	end
	if MonetizationIds.productId(STARTER_PACK) == nil then
		return
	end
	show(player, STARTER_PACK)
end

-- Day 2 or later: the Double Coins card, once the pass checks and the UI have had time to settle.
local function tryDoubleCoins(player: Player)
	if not canOffer(player) then
		return
	end
	local data = DataService:GetData(player)
	if data == nil or isDayOne(data) then
		return
	end
	if PassService:OwnsAny(player) then
		return
	end
	if PolicyInfoService:IsRestricted(player) then
		return
	end
	if MonetizationIds.passId(DOUBLE_COINS) == nil then
		return
	end
	show(player, DOUBLE_COINS)
end

-- Schedules the 30 s Double Coins check at most once per player per session.
local function scheduleDoubleCoins(player: Player)
	local state = states[player]
	if state == nil or state.scheduled then
		return
	end
	state.scheduled = true
	task.delay(DOUBLE_COINS_DELAY_SECONDS, function()
		if states[player] == nil or player.Parent ~= Players then
			return
		end
		tryDoubleCoins(player)
	end)
end

local function onPlayerAdded(player: Player)
	if states[player] ~= nil then
		return
	end
	states[player] = newState()
	-- A profile that somehow loaded before this ran still gets its one Double Coins check.
	if DataService:GetData(player) ~= nil then
		scheduleDoubleCoins(player)
	end
end

local function onPlayerRemoving(player: Player)
	states[player] = nil
end

-- A developer product receipt was granted for this player: funnel step 3 if it was the shown Starter Pack.
local function onGranted(player: Player, productKey: string, _isAd: boolean)
	if productKey == STARTER_PACK then
		notePurchased(player, STARTER_PACK)
	end
end

-- A pass turned on for this player: funnel step 3 if it was the shown Double Coins.
local function onOwnershipChanged(player: Player, passKey: string, owns: boolean)
	if owns and passKey == DOUBLE_COINS then
		notePurchased(player, DOUBLE_COINS)
	end
end

-- The Starter Pack prompt closed (bought or not): funnel step 2.
local function onPromptProductFinished(userId: number, productId: number, _isPurchased: boolean)
	local starterPackId = MonetizationIds.productId(STARTER_PACK)
	if starterPackId == nil or productId ~= starterPackId then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return
	end
	notePromptOpened(player, STARTER_PACK)
end

-- The Double Coins prompt closed (bought or not): funnel step 2.
local function onPromptPassFinished(player: Player, passId: number, _wasPurchased: boolean)
	local doubleCoinsId = MonetizationIds.passId(DOUBLE_COINS)
	if doubleCoinsId == nil or passId ~= doubleCoinsId then
		return
	end
	notePromptOpened(player, DOUBLE_COINS)
end

-- Called once per shattered crystal (CrystalService). The 10th shatter of the session is the only moment the
-- Starter Pack card can appear.
function OfferService:NoteShatter(player: Player)
	local state = states[player]
	if state == nil then
		return
	end
	state.shatters += 1
	if state.shatters ~= STARTER_PACK_SHATTERS then
		return
	end
	tryStarterPack(player)
end

-- The kind shown this session, or nil (for tests).
function OfferService:ShownKind(player: Player): string?
	local state = states[player]
	return if state then state.kind else nil
end

function OfferService:Init() end

function OfferService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	DataService.ProfileLoaded:Connect(function(player: Player, _data: { [string]: any })
		scheduleDoubleCoins(player)
	end)
	ReceiptService.Granted:Connect(onGranted)
	PassService.OwnershipChanged:Connect(onOwnershipChanged)
	MarketplaceService.PromptProductPurchaseFinished:Connect(onPromptProductFinished)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPromptPassFinished)

	-- Players who joined before Start ran, and profiles that finished loading before the listeners above.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
		if DataService:GetData(player) ~= nil then
			scheduleDoubleCoins(player)
		end
	end
end

return OfferService
