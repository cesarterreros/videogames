--!strict
-- Pure Crystal Codex bookkeeping: which seed/mutation variants a player has shattered, and whether a seed is complete.
-- The codex table is the profile's Codex field: [seedId] = { None = true, Glowing = true, ... }.

local Codex = {}

-- The 4 variants of every crystal. "None" (no mutation) counts as a variant.
Codex.Variants = { "None", "Glowing", "Molten", "Prismatic" }

-- Marks seedId + mutation as found. Returns true only the first time that variant is recorded.
function Codex.record(codex: { [string]: { [string]: boolean } }, seedId: string, mutation: string): boolean
	local entry = codex[seedId]
	if entry == nil then
		entry = {}
		codex[seedId] = entry
	end
	if entry[mutation] == true then
		return false
	end
	entry[mutation] = true
	return true
end

-- True when all 4 variants of seedId have been recorded.
function Codex.isComplete(codex: { [string]: { [string]: boolean } }, seedId: string): boolean
	local entry = codex[seedId]
	if entry == nil then
		return false
	end
	for _, variant in Codex.Variants do
		if entry[variant] ~= true then
			return false
		end
	end
	return true
end

return Codex
