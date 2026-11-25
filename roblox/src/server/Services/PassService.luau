--!strict
-- Pass ownership for this session. The server is the only source of truth: ownership is checked with
-- UserOwnsGamePassAsync on join (up to 3 tries with backoff), re-checked every 60 s during the first 5 minutes
-- (catching failed checks and passes bought on the website), and confirmed by a fresh call after
-- PromptGamePassPurchaseFinished. It is never read from the client and never saved in the profile, so a
-- refunded pass is off at the next join. Ownership only turns on during a session, never off.
-- Each pass is mirrored to a Player attribute "Pass_<Key>" (bool) so the client can show OWNED and the Auto toggle.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Analytics = require(script.Parent.Analytics)
local MonetizationIds = require(script.Parent.MonetizationIds)

local PassService = {}

local IS_STUDIO = RunService:IsStudio()

local TRIES = 3
local BACKOFF_SECONDS = { 1, 2 } -- wait after try 1 and after try 2
local RECHECK_EVERY = 60
local RECHECK_COUNT = 5 -- 5 × 60 s = the first 5 minutes

local changedEvent = Instance.new("BindableEvent")

-- Fires (player, passKey, owns) whenever a pass turns on for a player in this session.
PassService.OwnershipChanged = changedEvent.Event

local owned: { [Player]: { [string]: boolean } } = {}
-- Studio only: passes a test has forced on or off (DebugPass_<Key>). The checks leave these alone until a purchase.
local forced: { [Player]: { [string]: boolean } } = {}

local function isForced(player: Player, key: string): boolean
	local set = forced[player]
	return set ~= nil and set[key] ~= nil
end

local function attributeName(key: string): string
	return "Pass_" .. key
end

-- Purchases whose prompt said "bought" but that Roblox hadn't confirmed yet: the re-check that confirms one logs
-- PassPurchased (batch 6, task 6). In-memory only; a purchase confirmed only at the next join isn't logged.
local unconfirmed: { [Player]: { [string]: boolean } } = {}

local function logPurchased(player: Player, key: string)
	Analytics:Custom(player, "PassPurchased", 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = key,
	})
end

local function setOwned(player: Player, key: string, owns: boolean)
	local set = owned[player]
	if set == nil or (set[key] == true) == owns then
		return
	end
	set[key] = owns
	player:SetAttribute(attributeName(key), owns)
	changedEvent:Fire(player, key, owns)
	if IS_STUDIO then
		print(("[Pass] %s %s = %s"):format(player.Name, key, tostring(owns)))
	end
end

-- Asks Roblox whether the player owns the pass. nil means every try failed (the benefit stays off until a re-check).
local function query(player: Player, passId: number): boolean?
	for try = 1, TRIES do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if ok then
			return result == true
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

-- Checks every pass not yet owned, in parallel (the engine batches concurrent calls).
local function checkAll(player: Player)
	for key, passId in MonetizationIds.get().Passes do
		local set = owned[player]
		if set ~= nil and set[key] ~= true and not isForced(player, key) then
			task.spawn(function()
				if query(player, passId) == true and not isForced(player, key) then
					setOwned(player, key, true)
					local pending = unconfirmed[player]
					if pending ~= nil and pending[key] then
						pending[key] = nil
						logPurchased(player, key)
					end
				end
			end)
		end
	end
end

-- Studio only: a test can turn a pass on or off by setting the player attribute "DebugPass_<Key>" (bool) from the
-- server command bar, e.g. to check that a benefit disappears when ownership is false. The forced value holds
-- against the join check and the re-checks; a purchase of that pass clears it.
local function hookDebugOverride(player: Player)
	if not IS_STUDIO then
		return
	end
	forced[player] = {}
	player.AttributeChanged:Connect(function(name: string)
		local key = string.match(name, "^DebugPass_(%w+)$")
		local value = player:GetAttribute(name)
		if key ~= nil and MonetizationIds.passId(key) ~= nil and type(value) == "boolean" then
			local set = owned[player]
			local forcedSet = forced[player]
			if set ~= nil and forcedSet ~= nil then
				-- Bypasses the "never off in a session" rule on purpose: Studio tests only.
				forcedSet[key] = value
				set[key] = not value
				setOwned(player, key, value)
			end
		end
	end)
end

local function onPlayerAdded(player: Player)
	if owned[player] ~= nil then
		return
	end
	owned[player] = {}
	for key in MonetizationIds.get().Passes do
		player:SetAttribute(attributeName(key), false)
	end
	hookDebugOverride(player)
	checkAll(player)
	task.spawn(function()
		for _ = 1, RECHECK_COUNT do
			task.wait(RECHECK_EVERY)
			if player.Parent ~= Players or owned[player] == nil then
				return
			end
			checkAll(player)
		end
	end)
end

-- A purchase prompt closed. Only the server-side event is used, and only a fresh ownership call turns the pass on.
local function onPurchaseFinished(player: Player, passId: number, wasPurchased: boolean)
	local key = MonetizationIds.passKey(passId)
	if IS_STUDIO then
		print(
			("[Pass] prompt closed: %s %s wasPurchased=%s"):format(player.Name, tostring(key), tostring(wasPurchased))
		)
	end
	if not wasPurchased or key == nil or owned[player] == nil then
		return
	end
	local forcedSet = forced[player]
	if forcedSet ~= nil then
		forcedSet[key] = nil
	end
	local owns = query(player, passId)
	if owns == true then
		setOwned(player, key, true)
		local pending = unconfirmed[player]
		if pending ~= nil then
			pending[key] = nil -- a re-check in between didn't log it; log once here
		end
		logPurchased(player, key)
	elseif IS_STUDIO then
		-- Studio test purchases may not change real ownership; the server event is still trustworthy in Studio.
		warn(
			"[Pass] Studio test purchase of "
				.. key
				.. " not confirmed by UserOwnsGamePassAsync; enabled for this session"
		)
		setOwned(player, key, true)
	elseif owned[player] ~= nil then
		local pending = unconfirmed[player] or {}
		unconfirmed[player] = pending
		pending[key] = true
		warn("[Pass] purchase of " .. key .. " not confirmed yet; the re-check or the next join will pick it up")
	end
end

function PassService:Init() end

function PassService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		owned[player] = nil
		forced[player] = nil
		unconfirmed[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, wasPurchased: boolean)
			task.spawn(onPurchaseFinished, player, passId, wasPurchased)
		end
	)
end

-- Whether the player owns the pass in this session (false while unchecked or when this experience has no such pass).
function PassService:Owns(player: Player, passKey: string): boolean
	local set = owned[player]
	return set ~= nil and set[passKey] == true
end

-- Whether the player owns any pass (the Day-2 offer is shown only to players without one).
function PassService:OwnsAny(player: Player): boolean
	local set = owned[player]
	if set == nil then
		return false
	end
	for _, owns in set do
		if owns then
			return true
		end
	end
	return false
end

return PassService
