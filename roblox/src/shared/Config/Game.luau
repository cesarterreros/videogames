--!strict
-- Server-wide gameplay and data limits (players, plots, persistence, remotes); tuned after launch.

export type GameConfig = {
	MaxPlayers: number,
	PlotCount: number,
	MaxPedestals: number,
	ProfileStoreName: string,
	ProfileKeyPrefix: string,
	LeaderboardStorePrefix: string,
	LeaderboardRefreshSeconds: number,
	LeaderboardFlushSeconds: number,
	RemoteDefaultRate: number,
	RemoteDefaultBurst: number,
	AnomalyThresholdPerMinute: number,
}

local Game: GameConfig = {
	MaxPlayers = 6,
	PlotCount = 6,
	MaxPedestals = 13,
	ProfileStoreName = "PlayerData",
	ProfileKeyPrefix = "Player_",
	LeaderboardStorePrefix = "BiggestCrystal_",
	LeaderboardRefreshSeconds = 120,
	LeaderboardFlushSeconds = 30,
	RemoteDefaultRate = 8,
	RemoteDefaultBurst = 12,
	AnomalyThresholdPerMinute = 50,
}

return Game
