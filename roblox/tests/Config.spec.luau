-- Config.spec.luau - unit tests for the pure shared config modules.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Seeds = require("../src/shared/Config/Seeds")
local Rolls = require("../src/shared/Config/Rolls")
local Economy = require("../src/shared/Config/Economy")

local VALID_RARITIES = {
	Common = true,
	Uncommon = true,
	Rare = true,
	Epic = true,
	Legendary = true,
}

local CONFIG_PATHS = {
	"src/shared/Config/Seeds.luau",
	"src/shared/Config/Rolls.luau",
	"src/shared/Config/Economy.luau",
}

return function(test)
	test("Seeds: 10 rows, tiers 1..10 in order", function()
		expect(#Seeds):toBe(10)
		for index, seed in Seeds do
			expect(seed.Tier):toBe(index)
		end
	end)

	test("Seeds: price, grow time, value and carats strictly ascending", function()
		for index = 2, #Seeds do
			local previous, current = Seeds[index - 1], Seeds[index]
			expect(current.Price > previous.Price):toBeTruthy()
			expect(current.GrowSeconds > previous.GrowSeconds):toBeTruthy()
			expect(current.BaseValue > previous.BaseValue):toBeTruthy()
			expect(current.BaseCarats > previous.BaseCarats):toBeTruthy()
		end
	end)

	test("Seeds: unique Ids and valid rarities", function()
		local seen = {}
		for _, seed in Seeds do
			expect(seen[seed.Id]):toBeNil()
			seen[seed.Id] = true
			expect(VALID_RARITIES[seed.Rarity]):toBeTruthy()
		end
		expect(#Seeds):toBe(10)
	end)

	test("Seeds: ColorHex format", function()
		for _, seed in Seeds do
			local matched = string.match(seed.ColorHex, "^#%x%x%x%x%x%x$")
			expect(matched).never:toBeNil()
		end
	end)

	test("Rolls: size chances sum to 1", function()
		local total = 0
		for index, size in Rolls.Size do
			expect(size.Min < size.Max):toBeTruthy()
			if index > 1 then
				expect(size.Min):toBe(Rolls.Size[index - 1].Max)
			end
			total += size.Chance
		end
		expect(total):toBeNear(1, 1e-9)
	end)

	test("Rolls: mutation chances below 1 and multipliers ascending", function()
		local previousMult = 0
		for _, mutation in Rolls.Mutation do
			expect(mutation.Chance > 0):toBeTruthy()
			expect(mutation.Chance < 1):toBeTruthy()
			expect(mutation.Mult > previousMult):toBeTruthy()
			previousMult = mutation.Mult
		end
		expect(Rolls.Overgrowth.PerHour > 0):toBeTruthy()
		expect(Rolls.Overgrowth.Cap > Rolls.Overgrowth.PerHour):toBeTruthy()
	end)

	test("Economy: pedestal costs exist for 4..10 and ascend; 5 lamp costs ascend", function()
		expect(Economy.StartPedestals):toBe(3)
		expect(Economy.MaxCoinPedestals):toBe(10)
		for tier = 4, 10 do
			local cost = Economy.PedestalCosts[tier]
			expect(cost).never:toBeNil()
			if tier > 4 then
				expect(cost > Economy.PedestalCosts[tier - 1]):toBeTruthy()
			end
		end
		expect(#Economy.LampCosts):toBe(5)
		for index = 2, #Economy.LampCosts do
			expect(Economy.LampCosts[index] > Economy.LampCosts[index - 1]):toBeTruthy()
		end
	end)

	test("Config files contain no require", function()
		for _, path in CONFIG_PATHS do
			local source = fs.readFile(path)
			expect(string.find(source, "require", 1, true)):toBeNil()
		end
	end)

	test("Progression: 7 streak days, each with Coins or Seed", function()
		local Progression = require("../src/shared/Config/Progression")
		local streak = Progression.Streak
		expect(#streak):toBe(7)
		for _, day in streak do
			local hasCoins = day.Coins ~= nil
			local hasSeed = day.Seed ~= nil
			expect(hasCoins or hasSeed):toBeTruthy()
			expect(hasCoins and hasSeed):toBeFalsy()
			if hasSeed then
				expect(day.Count).never:toBeNil()
				local found = false
				for _, seed in Seeds do
					if seed.Id == day.Seed then
						found = true
					end
				end
				expect(found):toBeTruthy()
			end
		end
	end)

	test("Progression: goal pool has 6 unique ids and GoalsPerDay <= pool size", function()
		local Progression = require("../src/shared/Config/Progression")
		local seen = {}
		for _, goal in Progression.GoalPool do
			expect(seen[goal.Id]):toBeNil()
			seen[goal.Id] = true
			expect(goal.Target > 0):toBeTruthy()
		end
		expect(#Progression.GoalPool):toBe(6)
		expect(Progression.GoalsPerDay <= #Progression.GoalPool):toBeTruthy()
	end)

	test("Monetization: 5 passes and 10 products, each with numeric Id and DefaultPrice > 0", function()
		local Monetization = require("../src/shared/Config/Monetization")
		local passCount, productCount = 0, 0
		for _, pass in Monetization.Passes do
			passCount += 1
			expect(type(pass.Id)):toBe("number")
			expect(pass.Id >= 0):toBeTruthy()
			expect(pass.DefaultPrice > 0):toBeTruthy()
		end
		for _, product in Monetization.Products do
			productCount += 1
			expect(type(product.Id)):toBe("number")
			expect(product.Id >= 0):toBeTruthy()
			expect(product.DefaultPrice > 0):toBeTruthy()
		end
		expect(passCount):toBe(5)
		expect(productCount):toBe(10)
	end)

	test("Monetization: ad caps sum to at most DailyTotal", function()
		local Monetization = require("../src/shared/Config/Monetization")
		local total = 0
		for _, cap in Monetization.Ads.Caps do
			total += cap
		end
		expect(total <= Monetization.Ads.DailyTotal):toBeTruthy()
	end)

	test("Game: MaxPedestals equals Economy pedestal budget and PlotCount matches MaxPlayers", function()
		local Game = require("../src/shared/Config/Game")
		expect(Game.MaxPedestals):toBe(Economy.MaxCoinPedestals + Economy.PassPedestals)
		expect(Game.PlotCount):toBe(Game.MaxPlayers)
	end)

	test("New config files contain no require", function()
		local paths = {
			"src/shared/Config/Progression.luau",
			"src/shared/Config/Monetization.luau",
			"src/shared/Config/Game.luau",
		}
		for _, path in paths do
			local source = fs.readFile(path)
			expect(string.find(source, "require", 1, true)):toBeNil()
		end
	end)
end
