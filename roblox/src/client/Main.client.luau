--!strict
-- Client entry point: requires, initializes, then starts every controller in order.

local Controllers = script.Parent:WaitForChild("Controllers")

local order: { string } = {
	"StateController",
	"LightingController",
	"SoundController",
	"PurchaseController",
	"UIController",
	"BrightnessButton",
	"CrystalRenderer",
	"EffectsController",
	"TapController",
	"TutorialController",
}

local modules: { { name: string, module: any } } = {}
for _, name in order do
	table.insert(modules, { name = name, module = require(Controllers:WaitForChild(name)) })
end

-- Init all first, in order. Errors are logged, not fatal.
for _, entry in modules do
	local ok, err = pcall(function()
		entry.module:Init()
	end)
	if not ok then
		warn("[Client] " .. entry.name .. " failed: " .. tostring(err))
	end
end

-- Start each on its own thread so one yielding Start doesn't block the rest.
for _, entry in modules do
	task.spawn(function()
		local ok, err = pcall(function()
			entry.module:Start()
		end)
		if not ok then
			warn("[Client] " .. entry.name .. " failed: " .. tostring(err))
		end
	end)
end
