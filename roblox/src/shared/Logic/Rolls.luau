--!strict
-- Pure roll helpers: size bands, mutations, shape seeds and tier lookups.
-- The caller owns randomness: every draw comes from the `rng` function it passes in
-- ((() -> number) returning a value in [0, 1)), so results are reproducible in tests.

-- One size band: a roll lands in [Min, Max) and `Chance` is the odds of picking the band.
export type SizeTier = {
	Name: string,
	Min: number,
	Max: number,
	Chance: number,
}

-- One mutation band. Chances normally sum to less than 1; the remainder is the "None" outcome.
export type MutationTier = {
	Name: string,
	Mult: number,
	Chance: number,
}

local SHAPE_MAX = 2147483646

local Rolls = {}

-- Picks a size band with one draw, then a value inside it with a second draw.
-- Returns the roll and the band name.
function Rolls.size(rng: () -> number, sizeTable: { SizeTier }): (number, string)
	local r = rng()
	-- Default to the last (rarest) band so float error in the chances can never leave us tierless.
	local tier = sizeTable[#sizeTable]
	local cumulative = 0
	for _, entry in sizeTable do
		cumulative += entry.Chance
		if r < cumulative then
			tier = entry
			break
		end
	end
	local roll = tier.Min + (tier.Max - tier.Min) * rng()
	return roll, tier.Name
end

-- Picks a mutation with one draw, walking the table from rarest to most common so rare bands stay
-- exactly as likely as their chance says. Returns "None", 1 when no mutation wins.
-- `chanceMult` scales every chance; if the scaled chances would exceed certainty they are normalised.
function Rolls.mutation(rng: () -> number, mutationTable: { MutationTier }, chanceMult: number?): (string, number)
	local mult = chanceMult or 1
	local chances = table.create(#mutationTable, 0)
	local total = 0
	for index = 1, #mutationTable do
		local chance = mutationTable[index].Chance * mult
		chances[index] = chance
		total += chance
	end
	local scale = if total > 1 then 1 / total else 1

	local r = rng()
	local cumulative = 0
	for index = #mutationTable, 1, -1 do
		cumulative += chances[index] * scale
		if r < cumulative then
			local entry = mutationTable[index]
			return entry.Name, entry.Mult
		end
	end
	return "None", 1
end

-- A random shape seed in 1..2147483646 (never 0, never the int32 maximum).
function Rolls.shape(rng: () -> number): number
	return math.clamp(math.floor(rng() * SHAPE_MAX) + 1, 1, SHAPE_MAX)
end

-- The size band whose [Min, Max) range holds `sizeRoll`; rolls past the table clamp to the first or last band.
function Rolls.sizeTierName(sizeRoll: number, sizeTable: { SizeTier }): string
	for _, entry in sizeTable do
		if sizeRoll < entry.Max then
			return entry.Name
		end
	end
	return sizeTable[#sizeTable].Name
end

return Rolls
