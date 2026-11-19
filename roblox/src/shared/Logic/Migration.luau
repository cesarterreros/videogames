--!strict
-- Upgrades stored profiles to the current schema and repairs impossible values. Pure, no requires.

local Migration = {}

type Data = { [string]: any }

export type SanitizeConfig = {
	seedIds: { [string]: true },
	maxPedestals: number, -- 13 (10 coin + 3 pass)
	maxLamp: number, -- 5
	maxTier: number, -- 10
	startPedestals: number?, -- default 3
	maxCoinPedestals: number?, -- default 10
}

local CURRENT_VERSION = 1
local MUTATIONS = { None = true, Glowing = true, Molten = true, Prismatic = true }

-- Copies every key missing in `data` from `template`, recursing into tables that exist on both sides.
local function fillMissing(data: Data, template: Data)
	for key, default in template do
		local value = data[key]
		if value == nil then
			if type(default) == "table" then
				local copy = {}
				fillMissing(copy, default)
				data[key] = copy
			else
				data[key] = default
			end
		elseif type(value) == "table" and type(default) == "table" then
			fillMissing(value, default)
		end
	end
end

-- Ordered upgrade steps: STEPS[n] turns a version n-1 profile into version n.
local STEPS: { [number]: (Data, Data) -> () } = {
	-- v0 (no Version field, e.g. an empty or corrupt profile) -> v1: fill every field from the template.
	[1] = function(data, template)
		fillMissing(data, template)
	end,
}

-- Brings `data` up to CURRENT_VERSION. A profile from a newer version is left as-is (and flagged by sanitize).
function Migration.migrate(data: Data, template: Data): Data
	local version = if type(data.Version) == "number" then data.Version else 0
	for v = version + 1, CURRENT_VERSION do
		STEPS[v](data, template)
		data.Version = v
	end
	return data
end

local function isNumber(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function clampInt(x: any, lo: number, hi: number): number
	if not isNumber(x) then
		return lo
	end
	return math.clamp(math.floor(x), lo, hi)
end

-- Repairs values no honest play can produce. Returns the data and a list of what was fixed (for logging).
function Migration.sanitize(data: Data, config: SanitizeConfig): (Data, { string })
	local issues: { string } = {}
	local function fix(text: string)
		table.insert(issues, text)
	end

	if type(data.Version) == "number" and data.Version > CURRENT_VERSION then
		fix("version " .. tostring(data.Version) .. " is newer than " .. tostring(CURRENT_VERSION))
	end

	-- Coins: a finite whole number >= 0.
	if not isNumber(data.Coins) or data.Coins < 0 or data.Coins % 1 ~= 0 then
		fix("coins " .. tostring(data.Coins))
		data.Coins = if isNumber(data.Coins) and data.Coins > 0 then math.floor(data.Coins) else 0
	end

	-- Seed bag: only known seeds with whole, positive counts.
	if type(data.SeedBag) ~= "table" then
		fix("seed bag not a table")
		data.SeedBag = {}
	end
	for id, count in data.SeedBag do
		if not config.seedIds[id] then
			fix("unknown seed " .. tostring(id))
			data.SeedBag[id] = nil
		elseif not isNumber(count) or count < 1 or count % 1 ~= 0 then
			fix("seed count " .. tostring(id) .. "=" .. tostring(count))
			data.SeedBag[id] = if isNumber(count) and count >= 1 then math.floor(count) else nil
		end
	end

	-- Pedestals: keys "1".."maxPedestals", each a well-formed crystal of a known seed.
	if type(data.Pedestals) ~= "table" then
		fix("pedestals not a table")
		data.Pedestals = {}
	end
	for key, crystal in data.Pedestals do
		local index = tonumber(key)
		local validKey = type(key) == "string"
			and index ~= nil
			and index % 1 == 0
			and index >= 1
			and index <= config.maxPedestals
			and tostring(index) == key
		local validCrystal = type(crystal) == "table"
			and config.seedIds[crystal.SeedId] == true
			and isNumber(crystal.PlantedAt)
			and isNumber(crystal.ReadyAt)
			and isNumber(crystal.SizeRoll)
			and crystal.SizeRoll > 0
			and MUTATIONS[crystal.Mutation] == true
		if not validKey or not validCrystal then
			fix("pedestal " .. tostring(key))
			data.Pedestals[key] = nil
		end
	end

	-- Counters with fixed ranges.
	local startPedestals = config.startPedestals or 3
	local maxCoinPedestals = config.maxCoinPedestals or 10
	local unlocked = clampInt(data.UnlockedPedestals, startPedestals, maxCoinPedestals)
	if unlocked ~= data.UnlockedPedestals then
		fix("unlocked pedestals " .. tostring(data.UnlockedPedestals))
		data.UnlockedPedestals = unlocked
	end
	local lamp = clampInt(data.LampLevel, 0, config.maxLamp)
	if lamp ~= data.LampLevel then
		fix("lamp level " .. tostring(data.LampLevel))
		data.LampLevel = lamp
	end
	local tier = clampInt(data.HighestUnlockedTier, 1, config.maxTier)
	if tier ~= data.HighestUnlockedTier then
		fix("highest tier " .. tostring(data.HighestUnlockedTier))
		data.HighestUnlockedTier = tier
	end

	-- Codex: only known seeds.
	if type(data.Codex) ~= "table" then
		fix("codex not a table")
		data.Codex = {}
	end
	for id in data.Codex do
		if not config.seedIds[id] then
			fix("codex seed " .. tostring(id))
			data.Codex[id] = nil
		end
	end

	return data, issues
end

Migration.CURRENT_VERSION = CURRENT_VERSION

return Migration
