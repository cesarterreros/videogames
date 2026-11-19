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

function Strings.has(key: string): boolean
	return en[key] ~= nil
end

return Strings
