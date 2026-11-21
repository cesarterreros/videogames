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
	DevStudioSeedTopUp: number,
	RenderTickSeconds: number,
	DevUniverseId: number,
	AnnounceMutations: { [string]: boolean },
	AnnounceSizeTiers: { [string]: boolean },
	LeaderboardRows: number,
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
	-- Studio only (never live): the Quartz count a bag is topped up to on load, for testing before the shop exists.
	DevStudioSeedTopUp = 5,
	-- How often the client re-checks growing crystals, in seconds; the scale is tweened between checks.
	RenderTickSeconds = 0.25,
	-- The separate "Crystal Grove DEV" universe (game.GameId). Dev-only tools such as the crystal
	-- stress test also run there, so they can be measured on a real phone; never in the live universe.
	DevUniverseId = 10777641396,
	-- A shatter with one of these mutations or size tiers is announced to everyone in the server.
	AnnounceMutations = { Molten = true, Prismatic = true },
	AnnounceSizeTiers = { Colossal = true },
	-- Rows on the hub's weekly Biggest Crystal board.
	LeaderboardRows = 10,
}

return Game
