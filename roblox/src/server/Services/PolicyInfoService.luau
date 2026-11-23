--!strict
-- Reads each player's PolicyService flags once, on the server, and tells their client what the UI needs
-- (the PolicyInfo remote). Until the lookup succeeds, and if every try fails, a player counts as restricted:
-- the safe side of the paid-random-items policy (coin-feeding products and Double Coins stay hidden and refused).

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")

local RemoteService = require(script.Parent.RemoteService)

local PolicyInfoService = {}

local IS_STUDIO = RunService:IsStudio()
local TRIES = 3
local BACKOFF_SECONDS = { 1, 2 }

local restricted: { [Player]: boolean } = {}

local function lookup(player: Player): boolean?
	for try = 1, TRIES do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" then
			return info.ArePaidRandomItemsRestricted == true
		end
		if player.Parent ~= Players then
			return nil
		end
		if try < TRIES then
			task.wait(BACKOFF_SECONDS[try])
		end
	end
	return nil
end

local function onPlayerAdded(player: Player)
	if restricted[player] ~= nil then
		return
	end
	restricted[player] = true
	local result = lookup(player)
	if player.Parent ~= Players then
		restricted[player] = nil
		return
	end
	local value = if result == nil then true else result
	if result == nil then
		warn("[Policy] lookup failed for a player; treating them as restricted")
	end
	restricted[player] = value
	if IS_STUDIO then
		print(("[Policy] %s paidRandomItemsRestricted = %s"):format(player.Name, tostring(value)))
	end
	RemoteService:Fire("PolicyInfo", player, { paidRandomItemsRestricted = value })
end

function PolicyInfoService:Init() end

function PolicyInfoService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		restricted[player] = nil
	end)
end

-- True when the player must not get paid random items (and while unknown).
function PolicyInfoService:IsRestricted(player: Player): boolean
	return restricted[player] ~= false
end

return PolicyInfoService
