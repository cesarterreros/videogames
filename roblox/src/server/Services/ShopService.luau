--!strict
-- The seed shop and the coin upgrades (pedestals, Growth Lamp). Every price and lock is read from config and
-- checked against the caller's own profile; the client only names what it wants. RemoteService has already
-- validated the argument types (seed ID, qty 1 or 5, "Pedestal" or "Lamp").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Seeds = require(Shared.Config.Seeds)
local EconomyConfig = require(Shared.Config.Economy)
local Economy = require(Shared.Logic.Economy)
local Strings = require(Shared.Strings.Strings)

local RemoteService = require(script.Parent.RemoteService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local PlotService = require(script.Parent.PlotService)
local TutorialService = require(script.Parent.TutorialService)

local ShopService = {}

local function toast(player: Player, key: string, params: { [string]: any }?)
	RemoteService:Fire("Toast", player, key, params)
end

-- Display name of the seed with this tier ("" if none).
local function seedNameForTier(tier: number): string
	for _, seed in Seeds do
		if seed.Tier == tier then
			return Strings.get("Seed." .. seed.Id)
		end
	end
	return ""
end

-- Goal progress for an upgrade (Track changes data only; the caller syncs). ProgressionService is required
-- here, not at the top, to avoid a require cycle.
local function trackUpgrade(player: Player)
	local ProgressionService = require(script.Parent.ProgressionService) :: any
	ProgressionService:Track(player, "Upgrade", 1)
end

-- BuySeed(seedId, qty): qty is 1 or 5. Locked tier or too few coins -> a toast and no change.
local function onBuySeed(player: Player, seedId: string, qty: number)
	local data = DataService:GetData(player)
	local seed = Economy.seedById(Seeds, seedId)
	if data == nil or seed == nil then
		return
	end
	local ok, reason = Economy.canBuySeed(seed, data.HighestUnlockedTier, data.Coins, qty)
	if not ok then
		if reason == "Locked" then
			toast(player, "Toast.SeedLocked", { prev = seedNameForTier(seed.Tier - 1) })
		else
			toast(player, "Toast.NotEnoughCoins")
		end
		return
	end
	if not DataService:SpendCoins(player, seed.Price * qty, seed.Id) then
		toast(player, "Toast.NotEnoughCoins")
		return
	end
	data.SeedBag[seed.Id] = (data.SeedBag[seed.Id] or 0) + qty
	TutorialService:OnEvent(player, "BuySeed") -- tutorial step 5 (data only)
	DataService:SyncState(player)
end

-- The next coin pedestal: unlocked in the profile and on the player's plot straight away.
local function buyPedestal(player: Player, data: { [string]: any }): boolean
	local nextIndex = data.UnlockedPedestals + 1
	local cost =
		Economy.nextPedestalCost(data.UnlockedPedestals, EconomyConfig.PedestalCosts, EconomyConfig.MaxCoinPedestals)
	if cost == nil then
		toast(player, "Toast.MaxLevel")
		return false
	end
	if not DataService:SpendCoins(player, cost, "Pedestal_" .. nextIndex) then
		toast(player, "Toast.NotEnoughCoins")
		return false
	end
	data.UnlockedPedestals = nextIndex
	local pedestal = PlotService:GetPedestal(player, nextIndex)
	if pedestal ~= nil then
		pedestal:SetAttribute("Unlocked", true)
		MapService.setPedestalLook(pedestal, true)
	end
	return true
end

-- The next Growth Lamp level. ReadyAt is fixed at planting, so only crystals planted from now on grow faster.
local function buyLamp(player: Player, data: { [string]: any }): boolean
	local nextLevel = data.LampLevel + 1
	local cost = Economy.nextLampCost(data.LampLevel, EconomyConfig.LampCosts)
	if cost == nil then
		toast(player, "Toast.MaxLevel")
		return false
	end
	if not DataService:SpendCoins(player, cost, "Lamp_" .. nextLevel) then
		toast(player, "Toast.NotEnoughCoins")
		return false
	end
	data.LampLevel = nextLevel
	return true
end

-- BuyUpgrade("Pedestal" | "Lamp").
local function onBuyUpgrade(player: Player, kind: string)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	local bought = if kind == "Pedestal" then buyPedestal(player, data) else buyLamp(player, data)
	if bought then
		trackUpgrade(player)
		DataService:SyncState(player)
	end
end

function ShopService:Init()
	RemoteService:On("BuySeed", onBuySeed)
	RemoteService:On("BuyUpgrade", onBuyUpgrade)
end

function ShopService:Start() end

return ShopService
