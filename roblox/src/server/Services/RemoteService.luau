--!strict
-- Creates every remote from Shared.Net.Remotes and runs each client request through the security layer:
-- profile loaded -> rate limit -> argument validation -> pcall(handler). The client is never trusted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Seeds = require(Shared.Config.Seeds)
local GameConfig = require(Shared.Config.Game)
local Validate = require(Shared.Logic.Validate)
local RateLimiter = require(Shared.Logic.RateLimiter)

local Analytics = require(script.Parent.Analytics)

type Handler = (Player, ...any) -> ...any

local RemoteService = {}

local IS_STUDIO = RunService:IsStudio()

local instances: { [string]: RemoteEvent | RemoteFunction } = {}
local schemas: { [string]: { Validate.ArgSpec } } = {}
local limiters: { [string]: RateLimiter.Limiter } = {}
local handlers: { [string]: Handler } = {}
local rejections: { [Player]: { count: number, windowStart: number, reported: boolean } } = {}

-- Set by DataService so this module doesn't need to require it (avoids a require cycle).
local isLoaded: (Player) -> boolean = function()
	return false
end

-- Replaces {kind="enum", valuesFrom="SeedIds"} with the real list of seed IDs.
local function resolveSchema(args: { any }?): { Validate.ArgSpec }
	local seedIds = {}
	for _, seed in Seeds do
		table.insert(seedIds, seed.Id)
	end
	local resolved = {}
	for i, spec in args or {} do
		local copy = table.clone(spec)
		if copy.valuesFrom == "SeedIds" then
			copy.values = seedIds
			copy.valuesFrom = nil
		elseif copy.valuesFrom ~= nil then
			error("[RemoteService] unknown valuesFrom " .. tostring(copy.valuesFrom))
		end
		resolved[i] = copy :: any
	end
	return resolved
end

-- Counts a rejected request. Crossing the per-minute threshold logs one Anomaly event per window.
local function reject(name: string, player: Player, reason: string, countsAsAnomaly: boolean)
	if IS_STUDIO then
		print(("[Remote] rejected %s from %s: %s"):format(name, player.Name, reason))
	end
	if not countsAsAnomaly then
		return
	end
	local now = os.clock()
	local entry = rejections[player]
	if entry == nil or now - entry.windowStart >= 60 then
		entry = { count = 0, windowStart = now, reported = false }
		rejections[player] = entry
	end
	entry.count += 1
	if not entry.reported and entry.count > GameConfig.AnomalyThresholdPerMinute then
		entry.reported = true
		Analytics:Custom(player, "Anomaly", entry.count, nil)
	end
end

-- The single entry point for every client request.
local function dispatch(name: string, player: Player, ...: any): ...any
	if not isLoaded(player) then
		-- Normal right after joining; not treated as an anomaly.
		reject(name, player, "profile not loaded", false)
		return nil
	end
	if not limiters[name]:allow(player, os.clock()) then
		reject(name, player, "rate limited", true)
		return nil
	end
	local n = select("#", ...)
	local args = { ... }
	local schema = schemas[name]
	local ok, reason = Validate.check(schema, args, n)
	if not ok then
		reject(name, player, reason or "invalid", true)
		return nil
	end
	local handler = handlers[name]
	if handler == nil then
		reject(name, player, "no handler", true)
		return nil
	end
	local results = table.pack(pcall(handler, player, table.unpack(args, 1, #schema)))
	if not results[1] then
		warn(("[Remote] handler %s failed for %s: %s"):format(name, player.Name, tostring(results[2])))
		return nil
	end
	return table.unpack(results, 2, results.n)
end

function RemoteService:Init()
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"

	for name, def in Remotes :: { [string]: any } do
		local remote: RemoteEvent | RemoteFunction
		if def.Kind == "Function" then
			assert(def.Direction == "ToServer", "[RemoteService] RemoteFunctions must be ToServer: " .. name)
			remote = Instance.new("RemoteFunction")
		else
			remote = Instance.new("RemoteEvent")
		end
		remote.Name = name
		remote.Parent = folder
		instances[name] = remote

		if def.Direction == "ToServer" then
			schemas[name] = resolveSchema(def.Args)
			limiters[name] =
				RateLimiter.new(def.Rate or GameConfig.RemoteDefaultRate, def.Burst or GameConfig.RemoteDefaultBurst)
			if remote:IsA("RemoteFunction") then
				remote.OnServerInvoke = function(player: Player, ...: any)
					return dispatch(name, player, ...)
				end
			else
				local event = remote :: RemoteEvent
				event.OnServerEvent:Connect(function(player: Player, ...: any)
					dispatch(name, player, ...)
				end)
			end
		end
	end

	-- Parent last so clients only see the folder once every remote exists.
	folder.Parent = ReplicatedStorage
end

function RemoteService:Start()
	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:forget(player)
		end
		rejections[player] = nil
	end)
end

-- DataService registers how to tell whether a player's profile is loaded.
function RemoteService:SetLoadedCheck(fn: (Player) -> boolean)
	isLoaded = fn
end

-- Registers the handler for a client -> server remote. Arguments arrive already validated.
function RemoteService:On(name: string, handler: Handler)
	local def = (Remotes :: any)[name]
	assert(def ~= nil, "[RemoteService] unknown remote " .. name)
	assert(def.Direction == "ToServer", "[RemoteService] " .. name .. " is not a ToServer remote")
	assert(handlers[name] == nil, "[RemoteService] handler already registered for " .. name)
	handlers[name] = handler
end

-- Sends a server -> client event to one player.
function RemoteService:Fire(name: string, player: Player, ...: any)
	local def = (Remotes :: any)[name]
	assert(def ~= nil and def.Direction == "ToClient", "[RemoteService] " .. name .. " is not a ToClient remote")
	local remote = instances[name] :: RemoteEvent
	remote:FireClient(player, ...)
end

-- Sends a server -> client event to everyone.
function RemoteService:FireAll(name: string, ...: any)
	local def = (Remotes :: any)[name]
	assert(def ~= nil and def.Direction == "ToClient", "[RemoteService] " .. name .. " is not a ToClient remote")
	local remote = instances[name] :: RemoteEvent
	remote:FireAllClients(...)
end

return RemoteService
