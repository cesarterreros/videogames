--!strict
-- Roll tables for size, mutation and overgrowth; tuned after launch.

-- A size band. Chances across all size bands add up to exactly 1.
export type SizeRoll = {
	Name: string,
	Min: number,
	Max: number,
	Chance: number,
}

-- A mutation band. Chances stay below 1; the remainder is the "None" outcome.
export type MutationRoll = {
	Name: string,
	Mult: number,
	Chance: number,
}

-- Per-hour overgrowth growth of a plant's value, clamped at Cap.
export type OvergrowthRoll = {
	PerHour: number,
	Cap: number,
}

export type RollsConfig = {
	Size: { SizeRoll },
	Mutation: { MutationRoll },
	Overgrowth: OvergrowthRoll,
}

local Rolls: RollsConfig = {
	Size = {
		{ Name = "Normal", Min = 1.0, Max = 1.4, Chance = 0.88 },
		{ Name = "Big", Min = 1.4, Max = 2.0, Chance = 0.10 },
		{ Name = "Huge", Min = 2.0, Max = 4.0, Chance = 0.018 },
		{ Name = "Colossal", Min = 4.0, Max = 8.0, Chance = 0.002 },
	},
	Mutation = {
		-- "None" is the remainder: 1 - (sum of the chances below).
		{ Name = "Glowing", Mult = 2, Chance = 0.06 },
		{ Name = "Molten", Mult = 5, Chance = 0.012 },
		{ Name = "Prismatic", Mult = 20, Chance = 0.0015 },
	},
	Overgrowth = { PerHour = 0.10, Cap = 0.50 },
}

return Rolls
