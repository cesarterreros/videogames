--!strict
-- Client-side store for server state snapshots (plus Studio-only Toast/Announce prints). Read-only: never sends to the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Strings = require(ReplicatedStorage:WaitForChild("Shared").Strings.Strings)

local StateController = {}

local current: { [string]: any }? = nil
local changed = Instance.new("BindableEvent")

-- Fires with the new snapshot table.
StateController.Changed = changed.Event

-- Studio only, until batch 4's toasts: prints a Toast/Announce message as "[Tag] text".
-- An empty parameter (for example no mutation) would leave a double space, so runs of spaces are collapsed.
local function printMessage(tag: string, key: any, params: any)
	if typeof(key) ~= "string" then
		return
	end
	local text = Strings.get(key, if typeof(params) == "table" then params else nil)
	text = (string.gsub(text, " +", " "))
	text = (string.gsub(text, "^ ", ""))
	text = (string.gsub(text, " $", ""))
	print(("[%s] %s"):format(tag, text))
end

function StateController:Init()
	-- Nothing to set up. Must not yield.
end

function StateController:Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local stateSync = remotes:WaitForChild("StateSync") :: RemoteEvent
	if RunService:IsStudio() then
		local toast = remotes:WaitForChild("Toast") :: RemoteEvent
		local announce = remotes:WaitForChild("Announce") :: RemoteEvent
		toast.OnClientEvent:Connect(function(key: any, params: any)
			printMessage("Toast", key, params)
		end)
		announce.OnClientEvent:Connect(function(key: any, params: any)
			printMessage("Announce", key, params)
		end)
	end

	stateSync.OnClientEvent:Connect(function(snapshot: any)
		if typeof(snapshot) ~= "table" then
			return
		end

		local data: { [string]: any } = snapshot
		current = data
		changed:Fire(data)

		if RunService:IsStudio() then
			local coins = data.Coins or 0
			local sessions = data.Sessions or 0
			local seedBag: { [string]: any } = if typeof(data.SeedBag) == "table" then data.SeedBag else {}

			-- Sort seed keys so the log line is stable.
			local keys: { string } = {}
			for key in pairs(seedBag) do
				table.insert(keys, key)
			end
			table.sort(keys)

			local parts: { string } = {}
			for _, key in keys do
				table.insert(parts, key .. "=" .. tostring(seedBag[key]))
			end

			print(
				"[State] coins="
					.. tostring(coins)
					.. " sessions="
					.. tostring(sessions)
					.. " seeds={"
					.. table.concat(parts, ",")
					.. "}"
			)
		end
	end)
end

function StateController:Get(): { [string]: any }?
	return current
end

return StateController
