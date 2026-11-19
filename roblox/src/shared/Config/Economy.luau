--!strict
-- Economy tuning constants (pedestals, lamps, friend bonus, surges); tuned after launch.

export type EconomyConfig = {
	StartPedestals: number,
	MaxCoinPedestals: number,
	PassPedestals: number,
	PedestalCosts: { [number]: number },
	LampCosts: { number },
	LampStep: number,
	FriendBonusPer: number,
	FriendBonusCap: number,
	SurgeMinutes: number,
	SurgeMutationMult: number,
}

local Economy: EconomyConfig = {
	StartPedestals = 3,
	MaxCoinPedestals = 10,
	PassPedestals = 3,
	PedestalCosts = {
		[4] = 100,
		[5] = 500,
		[6] = 2000,
		[7] = 8000,
		[8] = 30000,
		[9] = 120000,
		[10] = 500000,
	},
	LampCosts = { 1000, 10000, 100000, 1000000, 5000000 },
	LampStep = 0.05,
	FriendBonusPer = 0.10,
	FriendBonusCap = 0.30,
	SurgeMinutes = 5,
	SurgeMutationMult = 2,
}

return Economy
