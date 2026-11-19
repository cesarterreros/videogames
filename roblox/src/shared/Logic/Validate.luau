--!strict
-- Validates remote arguments against a schema. Pure; every remote handler runs this before doing anything.

export type ArgSpec = {
	kind: "int" | "number" | "bool" | "enum" | "string",
	min: number?,
	max: number?,
	values: { any }?,
	maxLen: number?,
	optional: boolean?,
}

local Validate = {}

-- NaN is the only value not equal to itself; inf/-inf fail the finite check.
local function isFinite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

-- Checks one value against one spec. Returns an error string, or nil when valid.
local function checkOne(spec: ArgSpec, value: any): string?
	if value == nil then
		return if spec.optional then nil else "missing"
	end

	local kind = spec.kind
	if kind == "int" or kind == "number" then
		if type(value) ~= "number" then
			return "expected number, got " .. type(value)
		end
		if not isFinite(value) then
			return "not a finite number"
		end
		if kind == "int" and value % 1 ~= 0 then
			return "expected integer"
		end
		if spec.min ~= nil and value < spec.min then
			return "below " .. tostring(spec.min)
		end
		if spec.max ~= nil and value > spec.max then
			return "above " .. tostring(spec.max)
		end
		return nil
	elseif kind == "bool" then
		return if type(value) == "boolean" then nil else "expected boolean, got " .. type(value)
	elseif kind == "string" then
		if type(value) ~= "string" then
			return "expected string, got " .. type(value)
		end
		if spec.maxLen ~= nil and #value > spec.maxLen then
			return "string too long"
		end
		return nil
	elseif kind == "enum" then
		-- Only plain strings and numbers can match; tables/instances never do.
		local t = type(value)
		if t ~= "string" and t ~= "number" then
			return "expected enum value, got " .. t
		end
		for _, allowed in spec.values or {} do
			if allowed == value then
				return nil
			end
		end
		return "not an allowed value"
	end
	return "unknown spec kind " .. tostring(kind)
end

-- schema: the remote's ArgSpecs; args: the received values; n: select("#", ...) so extra args are caught.
-- Returns true, or false plus a short reason like "arg 2: above 13".
function Validate.check(schema: { ArgSpec }, args: { any }, n: number): (boolean, string?)
	if n > #schema then
		return false, "too many arguments (" .. tostring(n) .. " > " .. tostring(#schema) .. ")"
	end
	for i, spec in schema do
		local err = checkOne(spec, args[i])
		if err ~= nil then
			return false, "arg " .. tostring(i) .. ": " .. err
		end
	end
	return true, nil
end

return Validate
