--!nonstrict
-- FuzzClient.client.luau - DEVELOPMENT TESTING ONLY (batch 6, task 4).
--
-- Lives in roblox/dev/, OUTSIDE the Rojo project (default.project.json maps only src/shared, src/server and
-- src/client), so it is never synced into Studio and never published. Run it in a Studio Play client: paste it into
-- the client command bar, or send it through the Studio MCP to the Client data model. It runs for about
-- DURATION + 10 seconds and returns its summary when it ends, so keep the command bar / MCP call waiting.
--
-- What it does, against every client -> server remote in Shared.Net.Remotes:
--   1. "invalid": junk argument lists (wrong types, NaN, +/-inf, huge and negative numbers, fractions, nil, tables,
--      instances such as other players' pedestals and characters, long strings, extra arguments). Each list is
--      checked with the game's own Validate module first and only sent if the schema must REJECT it, so no honest
--      request can slip in and change data.
--   2. "forbidden": calls the schema accepts but the handler must refuse, built from the player's own snapshot:
--      planting on locked or occupied pedestals or with seeds the bag doesn't hold, shattering empty or locked
--      pedestals, tokens and instant grow on them, a locked seed tier, tutorial steps after the tutorial, an ad for
--      an empty pedestal, an already-claimed daily reward or goal, Auto Shatter without the pass.
--   3. "burst": 200 Shatter calls on an empty pedestal at once (the rate limiter must drop most of them).
-- Calls are paced at 5 per second per remote (the default limit is 8/s, some remotes allow 1-2/s), so most calls
-- reach the validation layer instead of the rate limiter.
--
-- Snapshots: SetBrightness only answers with a StateSync when the level CHANGES, so the script switches to another
-- level and back to the one on screen; the second StateSync is the player's real state. The StateSync listener must
-- stay connected while it waits, so the whole run stays in this one call (a listener left behind by a call that has
-- already returned stopped receiving events in the Studio MCP context).
--
-- Pass criteria: the summary reports changedFields=0 for the fuzzing player; a second player's own before/after
-- snapshots (take them with the same switch-and-back trick) are identical; the SERVER logs no warnings, no errors and
-- no "[Remote] handler ... failed" lines (count them with a LogService.MessageOut listener on the server, since the
-- Output window and GetLogHistory keep only the last few hundred lines).

local DURATION = 60
local PER_REMOTE_INTERVAL = 0.2

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemotesDef = require(Shared.Net.Remotes)
local Validate = require(Shared.Logic.Validate)
local Seeds = require(Shared.Config.Seeds)
local LightingConfig = require(Shared.Config.Lighting)
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local rng = Random.new()

-- ---------------------------------------------------------------------------------------------------------------
-- Snapshots

-- The brightness level on screen, read back from Lighting.Ambient.
local function currentLevel(): string
	local ambient = Lighting.Ambient
	for name, preset in LightingConfig.Presets do
		local c = Color3.fromRGB(preset.Ambient[1], preset.Ambient[2], preset.Ambient[3])
		if
			math.abs(c.R - ambient.R) < 0.01
			and math.abs(c.G - ambient.G) < 0.01
			and math.abs(c.B - ambient.B) < 0.01
		then
			return name
		end
	end
	return LightingConfig.Default
end

-- A fresh copy of the player's public profile: switch the level away and back, keep the second StateSync.
local function freshSnapshot()
	local level = currentLevel()
	local other = if level == "Dark" then "Normal" else "Dark"
	local got, count = nil, 0
	local conn = remotes.StateSync.OnClientEvent:Connect(function(snapshot)
		got = snapshot
		count += 1
	end)
	remotes.SetBrightness:FireServer(other)
	local deadline = os.clock() + 5
	while count < 1 and os.clock() < deadline do
		task.wait(0.1)
	end
	task.wait(0.3)
	remotes.SetBrightness:FireServer(level)
	deadline = os.clock() + 5
	while count < 2 and os.clock() < deadline do
		task.wait(0.1)
	end
	conn:Disconnect()
	if count < 2 or got == nil then
		return nil
	end
	-- Round-trip through JSON so before and after are encoded the same way.
	return HttpService:JSONDecode(HttpService:JSONEncode(got))
end

-- Flattens a snapshot into { [path] = value } for a field-by-field comparison.
local function flatten(value, path, out)
	if type(value) == "table" then
		for k, v in value do
			flatten(v, path .. "." .. tostring(k), out)
		end
	else
		out[path] = tostring(value)
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- Junk values

local function otherPedestal(): Instance?
	for _, plot in workspace.Map.Plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") ~= player.UserId then
			local list = plot.Pedestals:GetChildren()
			if #list > 0 then
				return list[rng:NextInteger(1, #list)]
			end
		end
	end
	return nil
end

local function otherCharacter(): Instance?
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character ~= nil then
			return other.Character
		end
	end
	return nil
end

local LONG = string.rep("A", 20000)

-- Each entry makes one junk value; nil and valid-looking values are in the pool on purpose (mixed lists).
local POOL = {
	function()
		return nil
	end,
	function()
		return 0 / 0
	end,
	function()
		return math.huge
	end,
	function()
		return -math.huge
	end,
	function()
		return -1
	end,
	function()
		return 0
	end,
	function()
		return 14
	end,
	function()
		return 1e308
	end,
	function()
		return -1e308
	end,
	function()
		return 1.5
	end,
	function()
		return 2 ^ 53
	end,
	function()
		return ""
	end,
	function()
		return "1"
	end,
	function()
		return LONG
	end,
	function()
		return true
	end,
	function()
		return false
	end,
	function()
		return {}
	end,
	function()
		return { 1, 2, 3 }
	end,
	function()
		return { pedestal = 1, coins = 1e9 }
	end,
	otherPedestal,
	otherCharacter,
	function()
		return workspace
	end,
	function()
		return Vector3.new(1, 2, 3)
	end,
	function()
		return Enum.KeyCode.E
	end,
	function()
		return "Pedestal"
	end,
	function()
		return "Bonus"
	end,
	function()
		return "Quartz"
	end,
	function()
		return "Voidheart'; DROP"
	end,
	function()
		return rng:NextInteger(1, 13)
	end,
	function()
		return rng:NextInteger(-5, 20)
	end,
}

local function junkValue(): any
	return POOL[rng:NextInteger(1, #POOL)]()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Schemas (resolved like RemoteService does: SeedIds -> every seed ID)

local seedIds = {}
for _, seed in Seeds do
	table.insert(seedIds, seed.Id)
end

local toServer = {}
for name, def in RemotesDef do
	if def.Direction == "ToServer" then
		local schema = {}
		for i, spec in def.Args or {} do
			local copy = table.clone(spec)
			if copy.valuesFrom == "SeedIds" then
				copy.values = seedIds
				copy.valuesFrom = nil
			end
			schema[i] = copy
		end
		table.insert(toServer, { name = name, kind = def.Kind, schema = schema })
	end
end
table.sort(toServer, function(a, b)
	return a.name < b.name
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Sending

local counts = { invalid = 0, forbidden = 0, burst = 0, skippedValid = 0, invokeReturnedValue = 0, sendErrors = 0 }

local function send(name: string, kind: string, args, n: number)
	local remote = remotes:FindFirstChild(name)
	if remote == nil then
		return
	end
	if kind == "Function" then
		task.spawn(function()
			local ok, result = pcall(function()
				return remote:InvokeServer(table.unpack(args, 1, n))
			end)
			if ok and result ~= nil then
				counts.invokeReturnedValue += 1
			elseif not ok then
				counts.sendErrors += 1
			end
		end)
	else
		local ok = pcall(function()
			remote:FireServer(table.unpack(args, 1, n))
		end)
		if not ok then
			counts.sendErrors += 1
		end
	end
end

-- One junk call that the schema must reject (valid lists are skipped, never sent).
local function invalidCall(entry)
	for _ = 1, 20 do
		local n = rng:NextInteger(0, #entry.schema + 2)
		local args = {}
		for i = 1, n do
			args[i] = junkValue()
		end
		if not Validate.check(entry.schema, args, n) then
			send(entry.name, entry.kind, args, n)
			counts.invalid += 1
			return
		end
		counts.skippedValid += 1
	end
end

-- Calls the schema accepts but the handler must refuse, built from the starting snapshot.
local function forbiddenCalls(snapshot)
	local calls = {}
	local pedestals = snapshot.Pedestals or {}
	local bag = snapshot.SeedBag or {}
	local highest = snapshot.HighestUnlockedTier or 1
	local empty, locked, occupied = {}, {}, {}
	for i = 1, 13 do
		local unlocked = i <= (snapshot.UnlockedPedestals or 3)
			or (i >= 11 and player:GetAttribute("Pass_ExtraPedestals") == true)
		if not unlocked then
			table.insert(locked, i)
		elseif pedestals[tostring(i)] ~= nil then
			table.insert(occupied, i)
		else
			table.insert(empty, i)
		end
	end
	for _, i in locked do
		table.insert(calls, { "Plant", "Event", { i, "Quartz" }, 2 })
		table.insert(calls, { "Shatter", "Event", { i }, 1 })
		table.insert(calls, { "UseToken", "Event", { i }, 1 })
		table.insert(calls, { "RequestInstantGrow", "Function", { i }, 1 })
	end
	for _, i in occupied do
		table.insert(calls, { "Plant", "Event", { i, "Quartz" }, 2 })
	end
	for _, i in empty do
		for _, seed in Seeds do
			if (bag[seed.Id] or 0) < 1 then
				table.insert(calls, { "Plant", "Event", { i, seed.Id }, 2 })
			end
		end
		table.insert(calls, { "Shatter", "Event", { i }, 1 })
		table.insert(calls, { "UseToken", "Event", { i }, 1 })
		table.insert(calls, { "RequestInstantGrow", "Function", { i }, 1 })
		table.insert(calls, { "RequestAd", "Event", { "FinishNow", i }, 2 })
	end
	table.insert(calls, { "RequestAd", "Event", { "FinishNow" }, 1 })
	for _, seed in Seeds do
		if seed.Tier > highest then
			table.insert(calls, { "BuySeed", "Event", { seed.Id, 1 }, 2 })
			table.insert(calls, { "BuySeed", "Event", { seed.Id, 5 }, 2 })
		end
	end
	if type(snapshot.Tutorial) == "table" and snapshot.Tutorial.Done == true then
		for step = 1, 8 do
			table.insert(calls, { "TutorialAction", "Event", { step }, 1 })
		end
	end
	if type(snapshot.Streak) == "table" and snapshot.Streak.LastClaimDate == os.date("!%Y-%m-%d") then
		table.insert(calls, { "ClaimDaily", "Event", {}, 0 })
	end
	local goals = snapshot.DailyGoals
	if type(goals) == "table" and type(goals.Goals) == "table" then
		for index, goal in goals.Goals do
			if type(goal) == "table" and goal.Claimed == true then
				table.insert(calls, { "ClaimGoal", "Event", { index }, 1 })
			end
		end
		if goals.BonusClaimed == true then
			table.insert(calls, { "ClaimGoal", "Event", { "Bonus" }, 1 })
		end
	end
	if player:GetAttribute("Pass_AutoShatter") ~= true then
		table.insert(calls, { "SetSetting", "Event", { "AutoShatter", true }, 2 })
	end
	return calls
end

-- ---------------------------------------------------------------------------------------------------------------
-- Run (stays in this call until the end; see "Snapshots" above)

local before = freshSnapshot()
if before == nil then
	return "no starting snapshot (is the profile loaded?)"
end

local forbidden = forbiddenCalls(before)
local stopAt = os.clock() + DURATION
local loops = 0
for _, entry in toServer do
	loops += 1
	task.spawn(function()
		while os.clock() < stopAt do
			invalidCall(entry)
			task.wait(PER_REMOTE_INTERVAL)
		end
		loops -= 1
	end)
end

local nextForbidden = 1
while os.clock() < stopAt do
	if #forbidden > 0 then
		local call = forbidden[nextForbidden]
		send(call[1], call[2], call[3], call[4])
		counts.forbidden += 1
		nextForbidden = nextForbidden % #forbidden + 1
	end
	task.wait(0.5)
end
while loops > 0 do
	task.wait(0.1)
end

local burstIndex = 13
for i = 1, 13 do
	if (before.Pedestals or {})[tostring(i)] == nil then
		burstIndex = i
		break
	end
end
for _ = 1, 200 do
	send("Shatter", "Event", { burstIndex }, 1)
	counts.burst += 1
end

task.wait(3)
local after = freshSnapshot()
local diff = {}
local fields = 0
if after == nil then
	table.insert(diff, "no final snapshot")
else
	local a = flatten(before, "", {})
	local b = flatten(after, "", {})
	for path, value in a do
		fields += 1
		if b[path] ~= value then
			table.insert(diff, path .. ": " .. value .. " -> " .. tostring(b[path]))
		end
	end
	for path, value in b do
		if a[path] == nil then
			table.insert(diff, path .. ": nil -> " .. value)
		end
	end
	table.sort(diff)
end

return ("remotes=%d invalid=%d forbidden=%d (list %d) burst=%d skippedValid=%d invokeReturnedValue=%d sendErrors=%d fields=%d changedFields=%d\n%s"):format(
	#toServer,
	counts.invalid,
	counts.forbidden,
	#forbidden,
	counts.burst,
	counts.skippedValid,
	counts.invokeReturnedValue,
	counts.sendErrors,
	fields,
	#diff,
	table.concat(diff, "\n")
)
