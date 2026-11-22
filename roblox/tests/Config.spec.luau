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
			"src/shared/Config/Lighting.luau",
			"src/shared/Config/Sounds.luau",
		}
		for _, path in paths do
			local source = fs.readFile(path)
			expect(string.find(source, "require", 1, true)):toBeNil()
		end
	end)

	test("Lighting: every preset has the 4 fields with the right types", function()
		local Lighting = require("../src/shared/Config/Lighting")
		local count = 0
		for _, preset in Lighting.Presets do
			count += 1
			expect(#preset.Ambient):toBe(3)
			expect(#preset.OutdoorAmbient):toBe(3)
			expect(type(preset.Brightness)):toBe("number")
			expect(type(preset.ExposureCompensation)):toBe("number")
		end
		expect(count):toBe(3)
	end)

	test("Lighting: colours are whole numbers 0-255", function()
		local Lighting = require("../src/shared/Config/Lighting")
		for _, preset in Lighting.Presets do
			for _, colour in { preset.Ambient, preset.OutdoorAmbient } do
				for _, v in colour do
					expect(type(v)):toBe("number")
					expect(v % 1):toBe(0)
					expect(v >= 0):toBeTruthy()
					expect(v <= 255):toBeTruthy()
				end
			end
		end
	end)

	test("Lighting: Default and every Levels entry is a preset", function()
		local Lighting = require("../src/shared/Config/Lighting")
		expect(Lighting.Presets[Lighting.Default]).never:toBeNil()
		for _, name in Lighting.Levels do
			expect(Lighting.Presets[name]).never:toBeNil()
		end
	end)

	test("Lighting: SetBrightness remote accepts exactly the preset names", function()
		local Lighting = require("../src/shared/Config/Lighting")
		local Remotes = require("../src/shared/Net/Remotes")
		local args = Remotes.SetBrightness.Args
		expect(#args):toBe(1)
		expect(args[1].kind):toBe("enum")
		local presetCount = 0
		for _ in Lighting.Presets do
			presetCount += 1
		end
		expect(#args[1].values):toBe(presetCount)
		for _, name in args[1].values do
			expect(Lighting.Presets[name]).never:toBeNil()
		end
	end)

	test("Lighting: Levels names each preset exactly once", function()
		local Lighting = require("../src/shared/Config/Lighting")
		local presetCount = 0
		for _ in Lighting.Presets do
			presetCount += 1
		end
		expect(#Lighting.Levels):toBe(presetCount)
		local seen = {}
		for _, name in Lighting.Levels do
			expect(seen[name]):toBeNil()
			seen[name] = true
		end
		for name in Lighting.Presets do
			expect(seen[name]):toBe(true)
		end
	end)

	test("Batch 3: announce lists name real mutation and size bands; LeaderboardRows is 10", function()
		local Game = require("../src/shared/Config/Game")
		local mutations, sizes = {}, {}
		for _, band in Rolls.Mutation do
			mutations[band.Name] = true
		end
		for _, band in Rolls.Size do
			sizes[band.Name] = true
		end
		for name in Game.AnnounceMutations do
			expect(mutations[name]):toBe(true)
		end
		for name in Game.AnnounceSizeTiers do
			expect(sizes[name]):toBe(true)
		end
		expect(Game.LeaderboardRows):toBe(10)
	end)

	test("Batch 3: GoalRewardValueMult is 10 (tier 1 goal pays 150)", function()
		local Progression = require("../src/shared/Config/Progression")
		expect(Progression.GoalRewardValueMult):toBe(10)
		expect(Progression.GoalRewardValueMult * Seeds[1].BaseValue):toBe(150)
	end)

	test("Batch 3: every goal, mutation and size tier has an English label", function()
		local en = require("../src/shared/Strings/en")
		local Progression = require("../src/shared/Config/Progression")
		for _, goal in Progression.GoalPool do
			expect(type(en["Goal." .. goal.Id])):toBe("string")
		end
		for _, band in Rolls.Mutation do
			expect(type(en["Mutation." .. band.Name])):toBe("string")
		end
		for _, band in Rolls.Size do
			expect(type(en["Size." .. band.Name])):toBe("string")
		end
	end)

	test("Batch 4: Config/Sounds has the 7 sound IDs as whole numbers >= 0", function()
		local Sounds = require("../src/shared/Config/Sounds")
		local names = { "Shatter", "Coin", "Ready", "Mutation", "NewBest", "Click", "Music" }
		local count = 0
		for _ in Sounds.Ids do
			count += 1
		end
		expect(count):toBe(#names)
		for _, name in names do
			local id = Sounds.Ids[name]
			expect(type(id)):toBe("number")
			expect(id >= 0 and id % 1 == 0):toBe(true)
		end
		expect(Sounds.MusicVolume):toBe(0.3)
		expect(Sounds.ShatterPitchStep):toBe(0.05)
	end)

	test("Batch 4: every result size tier above Normal and every mutation has a label", function()
		local en = require("../src/shared/Strings/en")
		expect(type(en["Mutation.None"])):toBe("string")
		for index, band in Rolls.Size do
			if index > 1 then
				expect(type(en["Result.Size." .. band.Name])):toBe("string")
			end
		end
	end)
end
