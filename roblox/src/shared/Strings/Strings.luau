--!strict
local en: { [string]: string } = require(script.Parent.en)
local Format = require(script.Parent.Parent.Logic.Format)

local Strings = {}

function Strings.get(key: string, params: { [string]: any }?): string
	local text = en[key]
	if text == nil then
		return key
	end
	return Format.interpolate(text, params)
end

-- A server message (Toast or Announce payload): like get, then double spaces from empty parameters are removed.
function Strings.message(key: string, params: { [string]: any }?): string
	return Format.tidySpaces(Strings.get(key, params))
end

function Strings.has(key: string): boolean
	return en[key] ~= nil
end

return Strings
