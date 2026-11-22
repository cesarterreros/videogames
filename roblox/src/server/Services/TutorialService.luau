--!strict
-- The 60-second tutorial on the server: keeps Tutorial.Step / Tutorial.Done in the profile, logs each onboarding
-- funnel step once, and answers CrystalService's questions about the three tutorial favours (8-second first
-- crystal, guaranteed Glowing on the 3rd plant, +50 coins on the first shatter). The rules live in Logic/Tutorial.
-- Changes data only and never syncs, except for its own remote and the first load: callers send one StateSync.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared.Config.Progression)
local Tutorial = require(Shared.Logic.Tutorial)

local RemoteService = require(script.Parent.RemoteService)
local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)

local TutorialService = {}

local IS_STUDIO = RunService:IsStudio()
local CONFIG = Progression.Tutorial

-- Number of pedestals holding a crystal.
local function occupied(data: { [string]: any }): number
	local count = 0
	for _ in data.Pedestals do
		count += 1
	end
	return count
end

-- Plants so far (Logic/Tutorial header): shatters + crystals on pedestals.
local function plantsSoFar(data: { [string]: any }): number
	return Tutorial.plantsSoFar(data.Stats.Shatters, occupied(data))
end

-- Writes the result of Tutorial.advance into the live profile and logs every newly reached step once.
local function apply(player: Player, data: { [string]: any }, step: number, reached: { number }, done: boolean): boolean
	if #reached == 0 then
		return false
	end
	data.Tutorial.Step = step
	if done then
		data.Tutorial.Done = true
	end
	for _, reachedStep in reached do
		Analytics:Onboarding(player, reachedStep, Tutorial.StepNames[reachedStep])
		if IS_STUDIO then
			print(
				("[Tutorial] %s reached step %d %s"):format(player.Name, reachedStep, Tutorial.StepNames[reachedStep])
			)
		end
	end
	return true
end

-- Starts the tutorial on first use: an old profile that has already played is marked done (no funnel events);
-- a new one reaches step 1. Idempotent, so every entry point can call it, whatever order the load listeners run in.
-- Returns the live data (nil when not loaded) and whether anything changed.
local function ensureStarted(player: Player): ({ [string]: any }?, boolean)
	local data = DataService:GetData(player) -- the live profile, never ProfileLoaded's copy
	if data == nil then
		return nil, false
	end
	local tutorial = data.Tutorial
	if tutorial.Done or tutorial.Step ~= 0 then
		return data, false
	end
	if Tutorial.shouldSkip(tutorial, data.Stats.Shatters) then
		tutorial.Done = true
		if IS_STUDIO then
			print(("[Tutorial] %s: existing profile, tutorial skipped"):format(player.Name))
		end
		return data, true
	end
	local step, reached, done = Tutorial.advance(tutorial, "Load")
	return data, apply(player, data, step, reached, done)
end

-- True while the player's tutorial is running.
function TutorialService:IsActive(player: Player): boolean
	local data = ensureStarted(player)
	return data ~= nil and Tutorial.isActive(data.Tutorial)
end

-- The tutorial grow time for the very first crystal, else nil. Call before the new crystal is stored.
function TutorialService:GrowSecondsOverride(player: Player): number?
	local data = ensureStarted(player)
	if data == nil then
		return nil
	end
	return Tutorial.growOverride(data.Tutorial, plantsSoFar(data), CONFIG.GrowSeconds)
end

-- "Glowing" for the 3rd plant overall during the tutorial, else nil. Call before the new crystal is stored.
function TutorialService:ForcedMutation(player: Player): string?
	local data = ensureStarted(player)
	if data == nil then
		return nil
	end
	return Tutorial.forcedMutation(data.Tutorial, plantsSoFar(data), CONFIG.GuaranteedGlowingOnShatter)
end

-- Bonus coins for the tutorial's first shatter, else 0. Call before OnEvent("Shatter") moves the step on.
function TutorialService:BonusCoins(player: Player): number
	local data = ensureStarted(player)
	if data == nil then
		return 0
	end
	return Tutorial.bonusCoins(data.Tutorial, CONFIG.BonusCoins)
end

-- Advances a server-driven step: "Plant" (after the crystal is stored), "Shatter" (info.mutation) or "BuySeed".
-- Changes data only; the caller syncs.
function TutorialService:OnEvent(player: Player, event: string, info: { [string]: any }?)
	local data = ensureStarted(player)
	if data == nil or not Tutorial.isActive(data.Tutorial) then
		return
	end
	local details: { [string]: any } = if info then table.clone(info) else {}
	if event == "Plant" then
		details.plantsAfter = plantsSoFar(data)
	end
	local step, reached, done = Tutorial.advance(data.Tutorial, event, details)
	apply(player, data, step, reached, done)
end

-- TutorialAction(step): the client reports step 4 (Shop opened) or 8 (tip closed). RemoteService has checked
-- it is an integer 1..8; Logic/Tutorial accepts only 4 or 8 and only as the next step.
local function onAction(player: Player, step: number)
	local data, started = ensureStarted(player)
	if data == nil then
		return
	end
	local newStep, reached, done = Tutorial.advance(data.Tutorial, "Action", { step = step })
	local changed = apply(player, data, newStep, reached, done)
	if changed or started then
		DataService:SyncState(player)
	elseif IS_STUDIO then
		print(("[Tutorial] %s: TutorialAction(%d) refused at step %d"):format(player.Name, step, data.Tutorial.Step))
	end
end

-- On load: start (or skip) the tutorial and sync if that changed anything.
local function onProfileLoaded(player: Player)
	local _, changed = ensureStarted(player)
	if changed then
		DataService:SyncState(player)
	end
end

function TutorialService:Init()
	RemoteService:On("TutorialAction", onAction)
end

function TutorialService:Start()
	DataService.ProfileLoaded:Connect(onProfileLoaded)
	-- Profiles that finished loading before this connected.
	for _, player in Players:GetPlayers() do
		onProfileLoaded(player)
	end
end

return TutorialService
