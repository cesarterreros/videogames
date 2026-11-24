--!strict
-- CaveDecor - lays out one cave's decoration (rock stalagmites and crystal clusters on the walls) in the plot's
-- LOCAL coordinates: x across the interior (-32..32), z depth (-22 = the open entrance facing the hub, +22 = the
-- back wall), floor top at y = 0.2. Pure math with no requires: the server passes in a random function so it can
-- seed the layout (a fixed seed per plot index makes every server build the same caves).

export type Stalagmite = {
	X: number,
	Z: number,
	Width: number,
	Height: number,
	Yaw: number,
	Tilt: number,
}

export type Prism = {
	Length: number,
	Width: number,
	Pitch: number,
	Yaw: number,
}

export type Cluster = {
	Wall: "Left" | "Right" | "Back",
	Along: number,
	Y: number,
	Prisms: { Prism },
	ColorIndex: number,
}

export type Layout = {
	Stalagmites: { Stalagmite },
	Clusters: { Cluster },
}

-- Interior bounds a stalagmite centre may occupy, keeping a 2-stud margin from the walls.
local MIN_X = -30
local MAX_X = 30
local MIN_Z = -18
local MAX_Z = 20
local INTERIOR_WIDTH = MAX_X - MIN_X
local INTERIOR_DEPTH = MAX_Z - MIN_Z

-- Keep-out zones.
local PEDESTAL_CLEARANCE = 5 -- centre to centre, so rock never grows through a pedestal
local SPAWN_CLEARANCE = 6
local SPAWN_X = -16
local SPAWN_Z = -15
local LANE_HALF_WIDTH = 10 -- the walkway in from the cave mouth: |x| < 10 ...
local LANE_FROM_Z = -10 -- ... and z < -10 is left clear so players can walk in
local STALAGMITE_CLEARANCE = 4

local MIN_STALAGMITES = 8 -- 8 + floor(rng() * 5) = 8..12
local STALAGMITE_VARIANTS = 5
local MAX_DRAWS = 200 -- give up after this many candidate positions

-- The 13 pedestal centres, identical to MapService's PEDESTAL_SPOTS (local x, z).
local PEDESTAL_SPOTS: { { number } } = {
	{ -16, -6 },
	{ -8, -6 },
	{ 0, -6 },
	{ 8, -6 },
	{ 16, -6 },
	{ -16, 2 },
	{ -8, 2 },
	{ 0, 2 },
	{ 8, 2 },
	{ 16, 2 },
	{ -8, 10 },
	{ 0, 10 },
	{ 8, 10 },
}

-- Distance between two points in the ground plane (x, z).
local function distance(ax: number, az: number, bx: number, bz: number): number
	local dx = ax - bx
	local dz = az - bz
	return math.sqrt(dx * dx + dz * dz)
end

-- True when a candidate (x, z) keeps every clearance: away from the pedestals, the spawn point, the entrance
-- walkway and every stalagmite already placed.
local function isClear(x: number, z: number, placed: { Stalagmite }): boolean
	-- The entrance lane: nothing may stand in the walkway from the cave mouth.
	if math.abs(x) < LANE_HALF_WIDTH and z < LANE_FROM_Z then
		return false
	end
	-- Never crowd the pedestals the players plant on.
	for _, spot in PEDESTAL_SPOTS do
		if distance(x, z, spot[1], spot[2]) < PEDESTAL_CLEARANCE then
			return false
		end
	end
	-- Leave the player a free spot to stand when they enter.
	if distance(x, z, SPAWN_X, SPAWN_Z) < SPAWN_CLEARANCE then
		return false
	end
	-- Stalagmites must not merge into each other.
	for _, other in placed do
		if distance(x, z, other.X, other.Z) < STALAGMITE_CLEARANCE then
			return false
		end
	end
	return true
end

-- Draws one candidate stalagmite inside the interior with its size and angles. Assumes the caller already
-- checked that the position is clear, so the geometry draws don't shift when a candidate is rejected.
local function makeStalagmite(rng: () -> number, x: number, z: number): Stalagmite
	return {
		X = x,
		Z = z,
		Width = 1.5 + rng() * 1.5, -- 1.5..3 thick
		Height = 3 + rng() * 4, -- 3..7 tall
		Yaw = rng() * 360, -- degrees, so no two rocks face the same way
		Tilt = (rng() - 0.5) * 10, -- degrees, a slight lean either way
	}
end

-- Places 8..12 stalagmites by rejection sampling: each draw is a random point in the interior, kept only if it
-- clears every keep-out zone. Stops after MAX_DRAWS candidates and returns however many fitted.
local function layoutStalagmites(rng: () -> number): { Stalagmite }
	local target = MIN_STALAGMITES + math.floor(rng() * STALAGMITE_VARIANTS)
	local placed: { Stalagmite } = {}

	local draws = 0
	while #placed < target and draws < MAX_DRAWS do
		draws += 1
		local x = MIN_X + rng() * INTERIOR_WIDTH
		local z = MIN_Z + rng() * INTERIOR_DEPTH
		if isClear(x, z, placed) then
			table.insert(placed, makeStalagmite(rng, x, z))
		end
	end

	return placed
end

-- One crystal cluster on one wall. Left/Right walls run along z (Along in -16..16), the back wall runs along x
-- (Along in -24..24). Y is the height above the floor; the prisms fan out of the wall into the cave.
local function makeCluster(rng: () -> number, wall: "Left" | "Right" | "Back"): Cluster
	local alongLimit = if wall == "Back" then 24 else 16
	local prismCount = 3 + math.floor(rng() * 2) -- 3 or 4
	local prisms: { Prism } = {}
	for _ = 1, prismCount do
		table.insert(prisms, {
			Length = 1.5 + rng() * 2, -- 1.5..3.5 long
			Width = 0.5 + rng() * 0.5, -- 0.5..1 thick
			Pitch = 20 + rng() * 40, -- degrees out from the wall plane
			Yaw = (rng() - 0.5) * 60, -- degrees of spread around the wall normal
		})
	end
	return {
		Wall = wall,
		Along = (rng() * 2 - 1) * alongLimit,
		Y = 6 + rng() * 5, -- 6..11 studs above the floor
		Prisms = prisms,
		ColorIndex = 1 + math.floor(rng() * 3), -- the server picks one of 3 crystal colours
	}
end

-- The whole decoration for one cave: the stalagmites and exactly three wall clusters (Left, Right, Back).
local function layout(rng: () -> number): Layout
	local stalagmites = layoutStalagmites(rng)
	local clusters: { Cluster } = {
		makeCluster(rng, "Left"),
		makeCluster(rng, "Right"),
		makeCluster(rng, "Back"),
	}
	return { Stalagmites = stalagmites, Clusters = clusters }
end

export type CaveDecorModule = {
	PedestalSpots: { { number } },
	layout: (rng: () -> number) -> Layout,
}

local CaveDecor: CaveDecorModule = {
	PedestalSpots = PEDESTAL_SPOTS,
	layout = layout,
}

return CaveDecor
