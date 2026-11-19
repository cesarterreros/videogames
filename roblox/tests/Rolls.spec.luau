-- Rolls.spec.luau - unit tests for the pure roll helpers, driven by a seeded PRNG.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Rolls = require("../src/shared/Logic/Rolls")
local RollsConfig = require("../src/shared/Config/Rolls")

-- The shipped tables: pure, no requires, so they can be reused verbatim here.
local SIZE = RollsConfig.Size
local MUTATION = RollsConfig.Mutation

local ROLLS = 1000000
local TOLERANCE = 0.1

-- xorshift32: a tiny deterministic PRNG so the suite always rolls the same numbers.
-- (Never math.random or os.time, so failures are reproducible.)
local function makeRng(seed: number): () -> number
	local state = seed % 4294967296
	if state == 0 then
		state = 2463534242
	end
	return function(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / 4294967296
	end
end

-- A stub rng that always returns the same value.
local function constantRng(value: number): () -> number
	return function(): number
		return value
	end
end

-- A stub rng that walks a fixed list of values, repeating the last one forever.
local function sequenceRng(values: { number }): () -> number
	local index = 0
	return function(): number
		index += 1
		return values[index] or values[#values]
	end
end

-- True when `count` is within TOLERANCE (relative) of `expected`.
local function withinTolerance(count: number, expected: number): boolean
	return math.abs(count - expected) <= expected * TOLERANCE
end

-- Sum of the chances in a mutation table, used for the "None" remainder.
local function chanceTotal(mutationTable: { Rolls.MutationTier }, chanceMult: number): number
	local total = 0
	for _, band in mutationTable do
		total += band.Chance * chanceMult
	end
	return total
end

return function(test)
	test("size: a million seeded rolls match the tier chances", function()
		local byName = {}
		for _, band in SIZE do
			byName[band.Name] = band
		end

		local counts = {}
		for _, band in SIZE do
			counts[band.Name] = 0
		end

		local rng = makeRng(20251119)
		local outsideBand = 0
		local misnamed = 0
		for _ = 1, ROLLS do
			local roll, name = Rolls.size(rng, SIZE)
			local band = byName[name]
			counts[name] += 1
			if roll < band.Min or roll >= band.Max then
				outsideBand += 1
			end
			if Rolls.sizeTierName(roll, SIZE) ~= name then
				misnamed += 1
			end
		end

		expect(outsideBand):toBe(0)
		expect(misnamed):toBe(0)
		for _, band in SIZE do
			local expected = band.Chance * ROLLS
			expect(withinTolerance(counts[band.Name], expected)):toBeTruthy()
		end
	end)

	test("mutation: a million seeded rolls match the mutation chances", function()
		local mults = {}
		local counts = { None = 0 }
		for _, band in MUTATION do
			mults[band.Name] = band.Mult
			counts[band.Name] = 0
		end

		local rng = makeRng(777)
		local badMult = 0
		for _ = 1, ROLLS do
			local name, mult = Rolls.mutation(rng, MUTATION)
			counts[name] += 1
			if mult ~= (mults[name] or 1) then
				badMult += 1
			end
		end

		expect(badMult):toBe(0)
		for _, band in MUTATION do
			expect(withinTolerance(counts[band.Name], band.Chance * ROLLS)):toBeTruthy()
		end
		local noneChance = 1 - chanceTotal(MUTATION, 1)
		expect(withinTolerance(counts.None, noneChance * ROLLS)):toBeTruthy()
	end)

	test("mutation: chanceMult doubles every rate", function()
		local counts = { None = 0 }
		for _, band in MUTATION do
			counts[band.Name] = 0
		end

		local rng = makeRng(424242)
		for _ = 1, ROLLS do
			local name = Rolls.mutation(rng, MUTATION, 2)
			counts[name] += 1
		end

		for _, band in MUTATION do
			expect(withinTolerance(counts[band.Name], band.Chance * 2 * ROLLS)):toBeTruthy()
		end
		local noneChance = 1 - chanceTotal(MUTATION, 2)
		expect(withinTolerance(counts.None, noneChance * ROLLS)):toBeTruthy()
	end)

	test("mutation: chances above certainty are normalised and never fall through to None", function()
		local scaled = {
			{ Name = "Alpha", Mult = 2, Chance = 0.4 },
			{ Name = "Beta", Mult = 3, Chance = 0.3 },
			{ Name = "Gamma", Mult = 5, Chance = 0.2 },
		}
		local sum = chanceTotal(scaled, 2) -- 1.8 after chanceMult
		local counts = { None = 0, Alpha = 0, Beta = 0, Gamma = 0 }

		local rng = makeRng(99)
		local draws = 10000
		for _ = 1, draws do
			local name = Rolls.mutation(rng, scaled, 2)
			counts[name] += 1
		end

		expect(counts.None):toBe(0)
		for _, band in scaled do
			local rate = band.Chance * 2 / sum
			expect(withinTolerance(counts[band.Name], rate * draws)):toBeTruthy()
		end
	end)

	test("mutation: rarest band wins the lowest draw, highest draw gives None", function()
		local name, mult = Rolls.mutation(constantRng(0), MUTATION)
		expect(name):toBe("Prismatic")
		expect(mult):toBe(20)

		local noneName, noneMult = Rolls.mutation(constantRng(0.9999), MUTATION)
		expect(noneName):toBe("None")
		expect(noneMult):toBe(1)

		-- Draws just past one band fall through to the next rarer-than-common candidate.
		local prismaticName, prismaticMult = Rolls.mutation(constantRng(0.001), MUTATION)
		expect(prismaticName):toBe("Prismatic")
		expect(prismaticMult):toBe(20)

		local moltenName, moltenMult = Rolls.mutation(constantRng(0.005), MUTATION)
		expect(moltenName):toBe("Molten")
		expect(moltenMult):toBe(5)

		local glowingName, glowingMult = Rolls.mutation(constantRng(0.05), MUTATION)
		expect(glowingName):toBe("Glowing")
		expect(glowingMult):toBe(2)

		-- Above the total chance of all bands (0.0735) the roll is a plain crystal.
		expect(Rolls.mutation(constantRng(0.08), MUTATION)):toBe("None")
	end)

	test("size: stub rng picks the first and the last band", function()
		local firstRoll, firstName = Rolls.size(constantRng(0), SIZE)
		expect(firstName):toBe("Normal")
		expect(firstRoll):toBeNear(SIZE[1].Min)

		local lastRoll, lastName = Rolls.size(constantRng(0.99999999), SIZE)
		expect(lastName):toBe("Colossal")
		expect(lastRoll >= SIZE[#SIZE].Min):toBeTruthy()
		expect(lastRoll < SIZE[#SIZE].Max):toBeTruthy()

		-- First draw picks the band, second draw places the value inside it.
		local midRoll, midName = Rolls.size(sequenceRng({ 0.99999999, 0.5 }), SIZE)
		expect(midName):toBe("Colossal")
		expect(midRoll):toBeNear(6.0)
	end)

	test("sizeTierName: band edges", function()
		expect(Rolls.sizeTierName(1.0, SIZE)):toBe("Normal")
		expect(Rolls.sizeTierName(1.4, SIZE)):toBe("Big")
		expect(Rolls.sizeTierName(1.999, SIZE)):toBe("Big")
		expect(Rolls.sizeTierName(2.0, SIZE)):toBe("Huge")
		expect(Rolls.sizeTierName(4.0, SIZE)):toBe("Colossal")
		expect(Rolls.sizeTierName(8.0, SIZE)):toBe("Colossal")
		expect(Rolls.sizeTierName(0.5, SIZE)):toBe("Normal")
	end)

	test("shape: fixed draws stay inside the 1..2147483646 range", function()
		expect(Rolls.shape(constantRng(0))):toBe(1)
		expect(Rolls.shape(constantRng(0.9999999999))):toBe(2147483646)

		local half = Rolls.shape(constantRng(0.5))
		expect(half):toBe(1073741824)
		expect(half % 1):toBe(0)
	end)

	test("shape: a million-free seeded sweep is always an in-range integer", function()
		local rng = makeRng(0x5EED)
		local bad = 0
		for _ = 1, 10000 do
			local shape = rng()
			local value = Rolls.shape(constantRng(shape))
			if value % 1 ~= 0 or value < 1 or value > 2147483646 then
				bad += 1
			end
		end
		expect(bad):toBe(0)
	end)

	test("shape: the same rng value gives the same shape", function()
		local a = Rolls.shape(constantRng(0.4242))
		local b = Rolls.shape(constantRng(0.4242))
		expect(a):toBe(b)
		expect(Rolls.shape(constantRng(0.4243))).never:toBe(a)
	end)

	test("Rolls module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/Rolls.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
