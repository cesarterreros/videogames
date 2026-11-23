--!strict
-- The pass and product IDs of the experience this server runs in: Config/Monetization.IdsByGameId[game.GameId].
-- An experience without an entry (an unpublished place in Studio has GameId 0) gets no IDs at all, so every paid
-- feature stays hidden and nothing can be sold there. A plain module (no Init/Start); the tables are frozen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage:WaitForChild("Shared").Config.Monetization)

local MonetizationIds = {}

export type Ids = {
	Passes: { [string]: number },
	Products: { [string]: number },
}

local ids: Ids? = nil
local passKeyById: { [number]: string } = {}
local productKeyById: { [number]: string } = {}

-- Only keys the config knows, and only real IDs (whole numbers above 0).
local function pick(known: { [string]: any }, source: { [string]: number }?, reverse: { [number]: string })
	local out: { [string]: number } = {}
	if source == nil then
		return out
	end
	for key in known do
		local id = source[key]
		if type(id) == "number" and id > 0 and id % 1 == 0 then
			out[key] = id
			reverse[id] = key
		end
	end
	return out
end

local function load(): Ids
	local loaded = ids
	if loaded ~= nil then
		return loaded
	end
	local entry = Monetization.IdsByGameId[game.GameId]
	local built: Ids = {
		Passes = table.freeze(pick(Monetization.Passes, entry and entry.Passes, passKeyById)),
		Products = table.freeze(pick(Monetization.Products, entry and entry.Products, productKeyById)),
	}
	ids = table.freeze(built)
	return built
end

-- Every ID of this experience; empty tables where there are none.
function MonetizationIds.get(): Ids
	return load()
end

-- The pass ID for a key ("FastGrow"), or nil if this experience has none.
function MonetizationIds.passId(key: string): number?
	return load().Passes[key]
end

-- The developer product ID for a key ("InstantGrowS"), or nil.
function MonetizationIds.productId(key: string): number?
	return load().Products[key]
end

-- Reverse lookups for incoming events and receipts; nil for an ID this experience doesn't sell.
function MonetizationIds.passKey(id: number): string?
	load()
	return passKeyById[id]
end

function MonetizationIds.productKey(id: number): string?
	load()
	return productKeyById[id]
end

return MonetizationIds
