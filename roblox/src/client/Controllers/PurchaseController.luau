--!strict
-- The only client code that touches MarketplaceService, AdService and the purchase remotes. UI screens never do:
-- they call this module through ctx.Purchase (so this module must never require UIController: that is a cycle).
-- The client never decides grants. It only shows live prices, opens Roblox purchase prompts and sends intents;
-- the server prices, validates and grants. Prices are never hard-coded: they come from GetProductInfoAsync.

local MarketplaceService = game:GetService("MarketplaceService")
local AdService = game:GetService("AdService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Strings = require(Shared.Strings.Strings)

local PurchaseController = {}

type Kind = "Pass" | "Product"

type Ids = {
	Passes: { [string]: number },
	Products: { [string]: number },
}

type Prices = {
	Pass: { [string]: number },
	Product: { [string]: number },
}

type Remotes = {
	RequestInstantGrow: RemoteFunction,
	UseToken: RemoteEvent,
	RequestAd: RemoteEvent,
	PolicyInfo: RemoteEvent,
}

-- Items the paid-random-items policy hides: coin-feeding products and the Double Coins pass.
-- stylua: ignore
local RESTRICTED_HIDDEN: { [string]: { [string]: boolean } } = {
	Pass = { DoubleCoins = true },
	Product = {
		CoinPouchS = true,
		CoinPouchM = true,
		CoinPouchL = true,
		SeedBundle = true,
		StarterPack = true,
		LuckBoost = true,
	},
}

-- Built once, lazily, from IdsByGameId (only keys the config knows, only real IDs: whole numbers above 0).
local ids: Ids? = nil
-- Cached PriceInRobux per key; a key stays missing when its lookup failed (the UI keeps showing "loading").
local prices: Prices = { Pass = {}, Product = {} }
-- Safe default until the server's PolicyInfo remote says otherwise.
local restricted = true
local remotes: Remotes? = nil
-- True while an InstantGrow InvokeServer is in flight, so a double tap never opens two prompts.
local instantGrowBusy = false

local changed = Instance.new("BindableEvent")

-- Fires with no arguments whenever prices load, PolicyInfo arrives, or a Pass_* attribute changes.
PurchaseController.Changed = changed.Event

-- Only keys the config knows with a whole-number ID above 0; anything else counts as "not sold here".
local function pick(known: { [string]: any }, source: { [string]: number }?): { [string]: number }
	local out: { [string]: number } = {}
	if source == nil then
		return out
	end
	for key in known do
		local id = source[key]
		if type(id) == "number" and id > 0 and id % 1 == 0 then
			out[key] = id
		end
	end
	return out
end

-- The IDs of the experience this client runs in (empty tables for an unknown experience, e.g. a place in Studio).
local function build(): Ids
	local built = ids
	if built ~= nil then
		return built
	end
	local entry = Monetization.IdsByGameId[game.GameId]
	local passes: { [string]: number } = {}
	local products: { [string]: number } = {}
	if entry ~= nil then
		passes = pick(Monetization.Passes, entry.Passes)
		products = pick(Monetization.Products, entry.Products)
	end
	local result: Ids = { Passes = passes, Products = products }
	ids = result
	return result
end

local function idFor(kind: Kind, key: string): number?
	local built = build()
	if kind == "Pass" then
		return built.Passes[key]
	end
	return built.Products[key]
end

-- The Remotes folder and the four remotes this module uses, resolved once (Start warms them).
local function getRemotes(): Remotes
	local cached = remotes
	if cached ~= nil then
		return cached
	end
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local built: Remotes = {
		RequestInstantGrow = folder:WaitForChild("RequestInstantGrow") :: RemoteFunction,
		UseToken = folder:WaitForChild("UseToken") :: RemoteEvent,
		RequestAd = folder:WaitForChild("RequestAd") :: RemoteEvent,
		PolicyInfo = folder:WaitForChild("PolicyInfo") :: RemoteEvent,
	}
	remotes = built
	return built
end

local function localPlayer(): Player?
	return Players.LocalPlayer
end

-- Fetches one live price and caches it. Failures and non-number prices leave the key unset.
local function loadPrice(kind: Kind, key: string, id: number, infoType: Enum.InfoType)
	if id <= 0 then
		return
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, infoType)
	end)
	if not ok or typeof(info) ~= "table" then
		return
	end
	local price = info.PriceInRobux
	if type(price) == "number" then
		prices[kind][key] = price
	end
end

-- Prices every ID of this experience concurrently (the engine batches the calls); fires changed once all finish.
local function loadPrices()
	local built = build()
	local passes = built.Passes
	local products = built.Products

	local pending = 0
	for _, id in passes do
		if id > 0 then
			pending += 1
		end
	end
	for _, id in products do
		if id > 0 then
			pending += 1
		end
	end

	if pending == 0 then
		changed:Fire()
		return
	end

	local function finished()
		pending -= 1
		if pending == 0 then
			changed:Fire()
		end
	end

	for key, id in passes do
		task.spawn(function()
			pcall(loadPrice, "Pass", key, id, Enum.InfoType.GamePass)
			finished()
		end)
	end
	for key, id in products do
		task.spawn(function()
			pcall(loadPrice, "Product", key, id, Enum.InfoType.Product)
			finished()
		end)
	end
end

-- True when this experience sells that pass (it has an ID for it).
function PurchaseController:HasPass(key: string): boolean
	return build().Passes[key] ~= nil
end

-- True when this experience sells that product (it has an ID for it).
function PurchaseController:HasProduct(key: string): boolean
	return build().Products[key] ~= nil
end

-- True when the server says this player owns the pass (it writes the "Pass_<Key>" attribute).
function PurchaseController:OwnsPass(key: string): boolean
	local player = localPlayer()
	if player == nil then
		return false
	end
	return player:GetAttribute("Pass_" .. key) == true
end

-- The paid-random-items policy flag; true (hidden and refused) until the server says otherwise.
function PurchaseController:IsRestricted(): boolean
	return restricted
end

-- True when the shop row must not be shown at all: not sold here, or restricted while it feeds random rolls.
function PurchaseController:IsHidden(kind: Kind, key: string): boolean
	if idFor(kind, key) == nil then
		return true
	end
	if restricted and RESTRICTED_HIDDEN[kind][key] then
		return true
	end
	return false
end

-- The live PriceInRobux, or nil until it has loaded (or after a failed lookup).
function PurchaseController:Price(kind: Kind, key: string): number?
	return prices[kind][key]
end

-- The price as the UI shows it ("R$ <live price>") once known, the loading placeholder until then.
function PurchaseController:PriceText(kind: Kind, key: string): string
	local price = PurchaseController:Price(kind, key)
	if price == nil then
		return Strings.get("Price.Loading")
	end
	return Strings.get("Price.Robux", { price = price })
end

-- Opens the Roblox game pass prompt. False when there is nothing to sell right now (hidden, owned or no ID).
function PurchaseController:PromptPass(key: string): boolean
	if PurchaseController:IsHidden("Pass", key) or PurchaseController:OwnsPass(key) then
		return false
	end
	local id = idFor("Pass", key)
	local player = localPlayer()
	if id == nil or player == nil then
		return false
	end
	pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, id)
	end)
	return true
end

-- Opens the Roblox developer product prompt. Instant Grow tiers are skipped: those go through :InstantGrow,
-- because only the server may pick the tier its pending target.
function PurchaseController:PromptProduct(key: string): boolean
	if PurchaseController:IsHidden("Product", key) then
		return false
	end
	if string.sub(key, 1, 11) == "InstantGrow" then
		return false
	end
	local id = idFor("Product", key)
	local player = localPlayer()
	if id == nil or player == nil then
		return false
	end
	pcall(function()
		MarketplaceService:PromptProductPurchase(player, id)
	end)
	return true
end

-- Yields. Asks the server which tier fits this crystal and opens that prompt. One call in flight at a time.
function PurchaseController:InstantGrow(pedestal: number): boolean
	if instantGrowBusy then
		return false
	end
	instantGrowBusy = true
	local ok, productId = pcall(function()
		return getRemotes().RequestInstantGrow:InvokeServer(pedestal)
	end)
	instantGrowBusy = false
	if not ok or type(productId) ~= "number" then
		return false
	end
	local player = localPlayer()
	if player == nil then
		return false
	end
	pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	return true
end

-- Spends a saved Instant Grow token on this crystal; the server decides whether one covers it.
function PurchaseController:UseToken(pedestal: number)
	getRemotes().UseToken:FireServer(pedestal)
end

-- Yields. True only when the ad service says a rewarded video is available right now (an error counts as no).
function PurchaseController:CheckAd(): boolean
	local ok, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	if not ok or typeof(result) ~= "table" then
		return false
	end
	return result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
end

-- Yields. Offers a rewarded ad for a placement the server then shows. Coin-feeding and luck ads are refused while
-- the player is restricted, and availability is re-checked right before because one result covers a single ad.
function PurchaseController:RequestAd(placement: string, pedestal: number?): boolean
	if restricted and (placement == "Luck" or placement == "CoinPouch") then
		return false
	end
	if not PurchaseController:CheckAd() then
		return false
	end
	getRemotes().RequestAd:FireServer(placement, pedestal)
	return true
end

-- The Instant Grow product key the UI shows for a crystal. Display only: the server picks the real tier.
function PurchaseController:InstantGrowKey(secondsLeft: number): string
	local small = Monetization.Products.InstantGrowS.MaxSeconds
	if small ~= nil and secondsLeft <= small then
		return "InstantGrowS"
	end
	local medium = Monetization.Products.InstantGrowM.MaxSeconds
	if medium ~= nil and secondsLeft <= medium then
		return "InstantGrowM"
	end
	return "InstantGrowL"
end

-- Nothing to set up. Must not yield (the ID table is built lazily on first use, in Start or later).
function PurchaseController:Init() end

-- Watches PolicyInfo and the server's Pass_* attributes, then fills the price cache.
function PurchaseController:Start()
	local policyInfo = getRemotes().PolicyInfo

	policyInfo.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		local value = payload.paidRandomItemsRestricted
		if type(value) ~= "boolean" then
			return
		end
		restricted = value
		changed:Fire()
	end)

	local player = localPlayer()
	if player ~= nil then
		player.AttributeChanged:Connect(function(name: string)
			if string.sub(name, 1, 5) == "Pass_" then
				changed:Fire()
			end
		end)
	end

	task.spawn(loadPrices)
end

return PurchaseController
