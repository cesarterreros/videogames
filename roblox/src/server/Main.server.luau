--!strict
-- Server entry point (the only server Script): requires every service, calls Init on all in order, then Start.

local Services = script.Parent:WaitForChild("Services")

-- Build order matters: later services may use earlier ones in Init/Start.
local order: { string } =
	{ "Analytics", "RemoteService", "DataService", "SettingsService", "MapService", "PlotService", "CrystalService" }

local modules: { { name: string, module: any } } = {}
for _, name in order do
	table.insert(modules, { name = name, module = require(Services:WaitForChild(name)) })
end

-- Init must not yield; a failing Init stops the server boot so problems are found immediately.
for _, entry in modules do
	local ok, err = pcall(function()
		entry.module:Init()
	end)
	if not ok then
		error("[Server] " .. entry.name .. ":Init failed: " .. tostring(err))
	end
end

for _, entry in modules do
	local ok, err = pcall(function()
		entry.module:Start()
	end)
	if not ok then
		error("[Server] " .. entry.name .. ":Start failed: " .. tostring(err))
	end
end

print("[Server] Started " .. #modules .. " services")
