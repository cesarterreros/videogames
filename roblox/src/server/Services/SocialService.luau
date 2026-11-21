--!strict
-- The social side of the server: the friend coin bonus and server-wide announcements of rare finds.
-- Friendships are checked once per unordered pair and cached, so a busy server never spams the API.
-- Nothing here writes coins or profiles: the bonus is only published as the FriendBonus attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.Economy)
local GameConfig = require(Shared.Config.Game)
local Seeds = require(Shared.Config.Seeds)
local Strings = require(Shared.Strings.Strings)

local RemoteService = require(script.Parent.RemoteService)

local SocialService = {}

local IS_STUDIO = RunService:IsStudio()

-- Pair key -> friends? A false entry means "checked, not friends" and is never rechecked.
local friendPairs: { [string]: boolean } = {}
-- Pairs with an IsFriendsWithAsync call in flight -> that call's token; they count as not friends until it
-- resolves. A leave clears the token, so a check that finishes after a leave (or a leave and rejoin) is ignored.
local inFlight: { [string]: number } = {}
local nextToken = 0

-- Cache key for an unordered pair of user IDs.
local function pairKey(a: number, b: number): string
	return math.min(a, b) .. ":" .. math.max(a, b)
end

-- Number of other players in the server whose pair with this player is cached as friends.
local function friendCountOf(player: Player): number
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and friendPairs[pairKey(player.UserId, other.UserId)] == true then
			count += 1
		end
	end
	return count
end

-- The bonus fraction for one player, rounded to 2 decimals so 3 friends give exactly 0.3.
local function computeBonus(player: Player): number
	local count = friendCountOf(player)
	local raw = math.min(count * EconomyConfig.FriendBonusPer, EconomyConfig.FriendBonusCap)
	return math.floor(raw * 100 + 0.5) / 100
end

-- Writes the recalculated bonus onto the player's attribute, if they are still in the server.
local function publishBonus(player: Player)
	if player.Parent ~= Players then
		return
	end
	player:SetAttribute("FriendBonus", computeBonus(player))
end

-- One check per pair, spawned because the API yields. A failed or non-boolean result counts as not friends.
local function checkPair(newPlayer: Player, other: Player, token: number)
	local key = pairKey(newPlayer.UserId, other.UserId)

	local isFriend: boolean
	if newPlayer.UserId <= 0 or other.UserId <= 0 then
		-- Studio local test players have no real user ID; the API would error on them.
		isFriend = false
	else
		local ok, value = pcall(function()
			return newPlayer:IsFriendsWithAsync(other.UserId)
		end)
		isFriend = if ok and type(value) == "boolean" then value else false
	end

	-- A leave since this check started cleared or replaced the token: the result is stale, drop it.
	if inFlight[key] ~= token then
		return
	end
	-- Cached either way, so a failure is never retried (no retry storm).
	inFlight[key] = nil
	friendPairs[key] = isFriend

	if IS_STUDIO then
		print("[Social] friends " .. newPlayer.Name .. " & " .. other.Name .. " = " .. tostring(isFriend))
	end
	publishBonus(newPlayer)
	publishBonus(other)
end

-- A join starts with no bonus, then every uncached pair with an existing player is checked once.
local function onPlayerAdded(player: Player)
	player:SetAttribute("FriendBonus", 0)

	for _, other in Players:GetPlayers() do
		if other ~= player then
			local key = pairKey(player.UserId, other.UserId)
			if friendPairs[key] == nil and inFlight[key] == nil then
				-- Marked in flight before spawning so the same pair is never checked twice.
				nextToken += 1
				inFlight[key] = nextToken
				task.spawn(checkPair, player, other, nextToken)
			end
		end
	end
end

-- A leave forgets every pair that player was in (rechecked on rejoin) and re-publishes the survivors.
local function onPlayerRemoving(player: Player)
	local userId = player.UserId

	local function involves(key: string): boolean
		local ids = string.split(key, ":")
		return tonumber(ids[1]) == userId or tonumber(ids[2]) == userId
	end
	for key in friendPairs do
		if involves(key) then
			friendPairs[key] = nil
		end
	end
	for key in inFlight do
		if involves(key) then
			inFlight[key] = nil
		end
	end

	for _, other in Players:GetPlayers() do
		if other ~= player then
			publishBonus(other)
		end
	end
end

-- Studio only: rare finds are far too rare to trigger by hand, so the DebugAnnounce attribute fakes one.
local function hookDebugAnnounce()
	workspace:GetAttributeChangedSignal("DebugAnnounce"):Connect(function()
		if workspace:GetAttribute("DebugAnnounce") ~= true then
			return
		end
		workspace:SetAttribute("DebugAnnounce", false)

		local player: Player? = nil
		for _, candidate in Players:GetPlayers() do
			player = candidate
			break
		end
		if player == nil then
			return
		end

		local quartz: Seeds.Seed? = nil
		for _, seed in Seeds do
			if seed.Id == "Quartz" then
				quartz = seed
			end
		end
		if quartz == nil then
			return
		end

		print("[Social] debug announcement test from " .. player.Name)
		SocialService:Announce(player, { mutation = "Prismatic", sizeTier = "Colossal", coins = 0, carats = 0 }, quartz)
	end)
end

-- Sets up nothing that yields: the remotes already exist and the attribute hook is Studio only.
function SocialService:Init() end

-- Connects the player lifecycle, catches players already in the server, and installs the Studio test hook.
function SocialService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Players that were already here (a service restart, or Studio test players).
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	if IS_STUDIO then
		hookDebugAnnounce()
	end
end

-- The friend coin bonus for one player: FriendBonusPer per friend, capped at FriendBonusCap.
function SocialService:FriendBonus(player: Player): number
	return computeBonus(player)
end

-- Announces a rare shatter to the whole server when the mutation or size tier is worth one.
function SocialService:Announce(player: Player, result: { [string]: any }, seed: Seeds.Seed)
	if not (GameConfig.AnnounceMutations[result.mutation] or GameConfig.AnnounceSizeTiers[result.sizeTier]) then
		return
	end
	RemoteService:FireAll("Announce", "Announce.RareFind", {
		player = player.DisplayName,
		size = Strings.get("Size." .. result.sizeTier),
		mutation = if result.mutation == "None" then "" else Strings.get("Mutation." .. result.mutation),
		seed = Strings.get("Seed." .. seed.Id),
	})
end

return SocialService
