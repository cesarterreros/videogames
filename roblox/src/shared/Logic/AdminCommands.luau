--!strict
-- AdminCommands - parsing and the permission rule for the dev-only "/cg" chat command (batch 6, task 5).
-- Pure, no requires: AdminService passes in the seed IDs and the experience facts, so Lune can test everything here.
--
-- Commands (case-insensitive; numbers are plain whole numbers):
--   /cg coins <n>             set your coins to n (0..MaxCoins)
--   /cg seeds <seedId> <n>    add n seeds (1..MaxSeeds) of a known seed
--   /cg ready                 make every growing crystal ready
--   /cg tutorial reset        start the tutorial again
--   /cg daily reset           clear the streak and today's goals so they can be claimed again
--   /cg tier <n>              set the highest unlocked seed tier (1..MaxTier)
--   /cg wipe                  reset your profile to the template

export type Command = {
	Name: string, -- "coins" | "seeds" | "ready" | "tutorialReset" | "dailyReset" | "tier" | "wipe"
	Amount: number?,
	SeedId: string?,
}

local AdminCommands = {}

AdminCommands.Alias = "/cg"
AdminCommands.MaxCoins = 1000000000
AdminCommands.MaxSeeds = 999
AdminCommands.MaxTier = 10
AdminCommands.Usage = "/cg coins <n> | seeds <seedId> <n> | ready | tutorial reset | daily reset | tier <n> | wipe"

-- Splits on whitespace.
local function words(text: string): { string }
	local out = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(out, word)
	end
	return out
end

-- A plain whole number in [min, max] (digits only, at most 10 of them), or nil.
local function wholeNumber(token: string?, min: number, max: number): number?
	if token == nil or string.match(token, "^%d+$") == nil or #token > 10 then
		return nil
	end
	local value = tonumber(token)
	if value == nil or value < min or value > max then
		return nil
	end
	return value
end

-- Parses a full chat message ("/cg coins 500"). Returns the command, or nil and a short reason to show the player.
function AdminCommands.parse(text: any, seedIds: { string }): (Command?, string?)
	if type(text) ~= "string" then
		return nil, "Usage: " .. AdminCommands.Usage
	end
	local parts = words(text)
	if #parts == 0 or string.lower(parts[1]) ~= AdminCommands.Alias then
		return nil, "Usage: " .. AdminCommands.Usage
	end
	local sub = if parts[2] ~= nil then string.lower(parts[2]) else ""
	local count = #parts

	if sub == "coins" and count == 3 then
		local amount = wholeNumber(parts[3], 0, AdminCommands.MaxCoins)
		if amount == nil then
			return nil, "coins: give a whole number from 0 to " .. AdminCommands.MaxCoins
		end
		return { Name = "coins", Amount = amount }, nil
	elseif sub == "seeds" and count == 4 then
		local wanted = string.lower(parts[3])
		local seedId: string? = nil
		for _, id in seedIds do
			if string.lower(id) == wanted then
				seedId = id
				break
			end
		end
		if seedId == nil then
			return nil, "seeds: unknown seed " .. parts[3]
		end
		local amount = wholeNumber(parts[4], 1, AdminCommands.MaxSeeds)
		if amount == nil then
			return nil, "seeds: give a whole number from 1 to " .. AdminCommands.MaxSeeds
		end
		return { Name = "seeds", SeedId = seedId, Amount = amount }, nil
	elseif sub == "ready" and count == 2 then
		return { Name = "ready" }, nil
	elseif sub == "tutorial" and count == 3 and string.lower(parts[3]) == "reset" then
		return { Name = "tutorialReset" }, nil
	elseif sub == "daily" and count == 3 and string.lower(parts[3]) == "reset" then
		return { Name = "dailyReset" }, nil
	elseif sub == "tier" and count == 3 then
		local tier = wholeNumber(parts[3], 1, AdminCommands.MaxTier)
		if tier == nil then
			return nil, "tier: give a whole number from 1 to " .. AdminCommands.MaxTier
		end
		return { Name = "tier", Amount = tier }, nil
	elseif sub == "wipe" and count == 2 then
		return { Name = "wipe" }, nil
	end
	return nil, "Usage: " .. AdminCommands.Usage
end

-- Who may use the command (batch 6 Decision 1 and change H): anyone in Studio; otherwise only in the DEV universe and
-- only the user who owns the experience. Never in the live experience, whatever the owner check says.
function AdminCommands.isAllowed(
	isStudio: boolean,
	gameId: number,
	devUniverseId: number,
	creatorIsUser: boolean,
	creatorId: number,
	userId: number
): boolean
	if isStudio then
		return true
	end
	return gameId == devUniverseId and devUniverseId ~= 0 and creatorIsUser and creatorId > 0 and userId == creatorId
end

-- Whether the command may exist at all in this experience (checked once at server start).
function AdminCommands.existsHere(isStudio: boolean, gameId: number, devUniverseId: number): boolean
	return isStudio or (devUniverseId ~= 0 and gameId == devUniverseId)
end

return AdminCommands
