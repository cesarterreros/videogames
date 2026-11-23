-- Economy.spec.luau - unit tests for the pure shop economy helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Economy = require("../src/shared/Logic/Economy")

-- The ten shipping seeds, tier 1..10, copied from Config/Seeds so this spec stands alone.
local SEEDS = {
	{
		Id = "Quartz",
		Tier = 1,
		Rarity = "Common",
		Price = 10,
		GrowSeconds = 20,
		BaseValue = 15,
		BaseCarats = 1,
		ColorHex = "#EEF3F7",
	},
	{
		Id = "Amethyst",
		Tier = 2,
		Rarity = "Common",
		Price = 40,
		GrowSeconds = 45,
		BaseValue = 60,
		BaseCarats = 1.5,
		ColorHex = "#9B59D0",
	},
	{
		Id = "Citrine",
		Tier = 3,
		Rarity = "Uncommon",
		Price = 150,
		GrowSeconds = 120,
		BaseValue = 240,
		BaseCarats = 2.5,
		ColorHex = "#F5B82E",
	},
	{
		Id = "RoseQuartz",
		Tier = 4,
		Rarity = "Uncommon",
		Price = 500,
		GrowSeconds = 300,
		BaseValue = 800,
		BaseCarats = 4,
		ColorHex = "#F4A6C1",
	},
	{
		Id = "Emerald",
		Tier = 5,
		Rarity = "Rare",
		Price = 2000,
		GrowSeconds = 900,
		BaseValue = 3500,
		BaseCarats = 6,
		ColorHex = "#2ECC71",
	},
	{
		Id = "Sapphire",
		Tier = 6,
		Rarity = "Rare",
		Price = 7500,
		GrowSeconds = 1800,
		BaseValue = 13000,
		BaseCarats = 9,
		ColorHex = "#2E6FE0",
	},
	{
		Id = "Ruby",
		Tier = 7,
		Rarity = "Epic",
		Price = 30000,
		GrowSeconds = 3600,
		BaseValue = 55000,
		BaseCarats = 14,
		ColorHex = "#E0245E",
	},
	{
		Id = "Moonstone",
		Tier = 8,
		Rarity = "Epic",
		Price = 120000,
		GrowSeconds = 7200,
		BaseValue = 230000,
		BaseCarats = 20,
		ColorHex = "#B8D8F0",
	},
	{
		Id = "StarfireOpal",
		Tier = 9,
		Rarity = "Legendary",
		Price = 500000,
		GrowSeconds = 14400,
		BaseValue = 1000000,
		BaseCarats = 30,
		ColorHex = "#FF8A3D",
	},
	{
		Id = "Voidheart",
		Tier = 10,
		Rarity = "Legendary",
		Price = 2500000,
		GrowSeconds = 28800,
		BaseValue = 5500000,
		BaseCarats = 45,
		ColorHex = "#4B1D7A",
	},
}

-- Tier 2 fixture used by the canBuySeed cases: price 40, price x 5 is 200.
local AMETHYST = SEEDS[2]

-- Pedestal prices keyed by the pedestal index the player is buying.
local PEDESTAL_COSTS = {
	[4] = 100,
	[5] = 500,
	[6] = 2000,
	[7] = 8000,
	[8] = 30000,
	[9] = 120000,
	[10] = 500000,
}

-- Tenth pedestal is the last one the coin shop sells.
local MAX_PEDESTALS = 10

-- Grow lamp prices by level: level 1 costs 1000, level 5 costs 5000000.
local LAMP_COSTS = { 1000, 10000, 100000, 1000000, 5000000 }

return function(test)
	test("seedById: finds a seed by Id", function()
		local seed = Economy.seedById(SEEDS, "Amethyst")
		expect(seed and seed.Id):toBe("Amethyst")
		expect(seed and seed.Tier):toBe(2)
	end)

	test("seedById: an unknown Id gives nil", function()
		expect(Economy.seedById(SEEDS, "Nope")):toBeNil()
	end)

	test("canBuySeed: a locked tier is refused before the coin check", function()
		local ok, reason = Economy.canBuySeed(AMETHYST, 1, 1000000, 1)
		expect(ok):toBe(false)
		expect(reason):toBe("Locked")
	end)

	test("canBuySeed: one coin short of the price is refused", function()
		local ok, reason = Economy.canBuySeed(AMETHYST, 2, 39, 1)
		expect(ok):toBe(false)
		expect(reason):toBe("Coins")
	end)

	test("canBuySeed: the exact price is accepted", function()
		local ok, reason = Economy.canBuySeed(AMETHYST, 2, 40, 1)
		expect(ok):toBe(true)
		expect(reason):toBeNil()
	end)

	test("canBuySeed: bulk buys multiply the price by the quantity", function()
		local shortOk, shortReason = Economy.canBuySeed(AMETHYST, 2, 199, 5)
		expect(shortOk):toBe(false)
		expect(shortReason):toBe("Coins")
		local ok, reason = Economy.canBuySeed(AMETHYST, 2, 200, 5)
		expect(ok):toBe(true)
		expect(reason):toBeNil()
	end)

	test("nextPedestalCost: walks the cost table and stops at the last pedestal", function()
		expect(Economy.nextPedestalCost(3, PEDESTAL_COSTS, MAX_PEDESTALS)):toBe(100)
		expect(Economy.nextPedestalCost(4, PEDESTAL_COSTS, MAX_PEDESTALS)):toBe(500)
		expect(Economy.nextPedestalCost(9, PEDESTAL_COSTS, MAX_PEDESTALS)):toBe(500000)
		expect(Economy.nextPedestalCost(10, PEDESTAL_COSTS, MAX_PEDESTALS)):toBeNil()
	end)

	test("nextLampCost: walks the lamp ladder and stops at its end", function()
		expect(Economy.nextLampCost(0, LAMP_COSTS)):toBe(1000)
		expect(Economy.nextLampCost(4, LAMP_COSTS)):toBe(5000000)
		expect(Economy.nextLampCost(5, LAMP_COSTS)):toBeNil()
	end)

	test("shatterCoinMult: codex and friend bonuses stack multiplicatively", function()
		expect(Economy.shatterCoinMult(true, 0.1, 0.3)):toBeNear(1.43)
		expect(Economy.shatterCoinMult(false, 0.1, 0)):toBe(1)
		expect(Economy.shatterCoinMult(true, 0.1, 0)):toBeNear(1.1)
		expect(Economy.shatterCoinMult(false, 0.1, 0.2)):toBeNear(1.2)
	end)

	test("goalReward: pays the base value of the goal tier times the multiplier", function()
		expect(Economy.goalReward(SEEDS, 1, 10)):toBe(150)
		expect(Economy.goalReward(SEEDS, 3, 10)):toBe(2400)
	end)

	test("surpriseSeedId: one tier above the player, capped at the top seed", function()
		expect(Economy.surpriseSeedId(SEEDS, 1)):toBe("Amethyst")
		expect(Economy.surpriseSeedId(SEEDS, 9)):toBe("Voidheart")
		expect(Economy.surpriseSeedId(SEEDS, 10)):toBe("Voidheart")
	end)

	test("coinPouchAmount: tier 1 pays Quartz value times the pouch multiplier", function()
		expect(Economy.coinPouchAmount(SEEDS, 1, 5)):toBe(75)
		expect(Economy.coinPouchAmount(SEEDS, 1, 30)):toBe(450)
		expect(Economy.coinPouchAmount(SEEDS, 1, 100)):toBe(1500)
	end)

	test("coinPouchAmount: tier 10 pays the Voidheart value times the pouch multiplier", function()
		expect(Economy.coinPouchAmount(SEEDS, 10, 5)):toBe(27500000)
		expect(Economy.coinPouchAmount(SEEDS, 10, 100)):toBe(550000000)
	end)

	test("coinPouchAmount: equals goalReward for the same tier and multiplier", function()
		expect(Economy.coinPouchAmount(SEEDS, 3, 30)):toBe(7200)
		expect(Economy.coinPouchAmount(SEEDS, 3, 30)):toBe(Economy.goalReward(SEEDS, 3, 30))
	end)

	test("Economy module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/Economy.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
