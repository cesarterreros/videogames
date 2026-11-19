--!strict
-- Loads, holds and saves each player's profile with ProfileStore (session-locked, auto-saved).
-- Rule: if loading fails, the player is kicked and nothing is ever written over their data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.Game)
local Seeds = require(Shared.Config.Seeds)
local Economy = require(Shared.Config.Economy)
local ProfileTemplate = require(Shared.Logic.ProfileTemplate)
local Migration = require(Shared.Logic.Migration)
local Strings = require(Shared.Strings.Strings)

local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)
local RemoteService = require(script.Parent.RemoteService)
local Analytics = require(script.Parent.Analytics)

local DataService = {}

local IS_STUDIO = RunService:IsStudio()

local store: any = nil
local profiles: { [Player]: any } = {}
local loadedEvent = Instance.new("BindableEvent")
local sanitizeConfig: Migration.SanitizeConfig

-- Fires (player, data) once a player's profile is loaded and ready to use.
DataService.ProfileLoaded = loadedEvent.Event

local function profileKey(player: Player): string
	return GameConfig.ProfileKeyPrefix .. tostring(player.UserId)
end

-- What the client may see: everything except purchase history and the secret crystal size rolls.
local function publicSnapshot(data: { [string]: any }): { [string]: any }
	local snapshot = ProfileTemplate.deepCopy(data)
	snapshot.Monetization.ProcessedReceipts = nil
	for _, crystal in snapshot.Pedestals do
		crystal.SizeRoll = nil
	end
	return snapshot
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(profileKey(player), {
		-- Stop waiting for the session lock if the player leaves while loading.
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- DataStore outage or the lock couldn't be taken: never continue without real data.
		if player.Parent == Players then
			player:Kick(Strings.get("Error.DataLoad"))
		end
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: links the key to the user for data deletion requests
	profile:Reconcile() -- fills fields added to the template since this profile was saved
	Migration.migrate(profile.Data, ProfileTemplate.new())
	local _, issues = Migration.sanitize(profile.Data, sanitizeConfig)
	if #issues > 0 then
		Analytics:Custom(player, "Anomaly", #issues, nil)
		if IS_STUDIO then
			warn("[Data] Sanitized " .. profileKey(player) .. ": " .. table.concat(issues, "; "))
		end
	end

	-- If another server takes the session (player joined elsewhere), stop using this copy.
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick(Strings.get("Error.DataLoad"))
		end
	end)

	if player.Parent ~= Players then
		-- Left during loading: release immediately without changing anything.
		profile:EndSession()
		return
	end

	local data = profile.Data
	local now = os.time()
	data.Sessions += 1
	data.LastJoinAt = now
	if data.FirstJoinAt == 0 then
		data.FirstJoinAt = now
	end
	profiles[player] = profile

	if IS_STUDIO then
		print(("[Data] Loaded %s v%d sessions=%d"):format(profileKey(player), data.Version, data.Sessions))
		if ProfileStore.DataStoreState ~= "Access" then
			warn("[Data] Studio has no DataStore access – data will not be saved")
		end
	end

	DataService:SyncState(player)
	loadedEvent:Fire(player, data)
end

function DataService:Init()
	store = ProfileStore.New(GameConfig.ProfileStoreName, ProfileTemplate.new())

	local seedIds = {}
	for _, seed in Seeds do
		seedIds[seed.Id] = true
	end
	sanitizeConfig = {
		seedIds = seedIds,
		maxPedestals = GameConfig.MaxPedestals,
		maxLamp = #Economy.LampCosts,
		maxTier = #Seeds,
		startPedestals = Economy.StartPedestals,
		maxCoinPedestals = Economy.MaxCoinPedestals,
	}

	RemoteService:SetLoadedCheck(function(player)
		return profiles[player] ~= nil
	end)
end

function DataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	-- Players who joined before this ran (possible in Studio).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile ~= nil then
			profile:EndSession() -- saves and releases the session lock
		end
	end)
	-- Server shutdown is handled by ProfileStore itself (it saves and releases every active profile).
end

-- The loaded profile, or nil while loading / after leaving.
function DataService:GetProfile(player: Player): any
	return profiles[player]
end

-- The loaded profile's data table, or nil.
function DataService:GetData(player: Player): { [string]: any }?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

-- Asks ProfileStore to save soon. Does not yield (see batch 1 findings for receipt handling in batch 5).
function DataService:Save(player: Player)
	local profile = profiles[player]
	if profile ~= nil and profile:IsActive() then
		profile:Save()
	end
end

-- Sends the player their current public state.
function DataService:SyncState(player: Player)
	local data = DataService:GetData(player)
	if data ~= nil then
		RemoteService:Fire("StateSync", player, publicSnapshot(data))
	end
end

return DataService
