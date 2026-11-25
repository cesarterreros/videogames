--!strict
-- AdminService - the dev-only "/cg" chat command (batch 6, task 5) for fast testing.
--
-- Where it exists: only in Studio and in the DEV universe (GameConfig.DevUniverseId). Anywhere else (the live
-- experience) Start returns before creating anything, so there is no command to trigger at all (Decision 1).
-- Who may use it: anyone in Studio; in the DEV universe only the user who owns the experience (change H).
-- Parsing and the permission rule live in the pure Shared.Logic.AdminCommands (unit-tested).
--
-- The command is a TextChatCommand under TextChatService. Its Triggered event fires on the server with the sender's
-- TextSource; DeliverMessage = false sinks the message (nobody else sees it) and hands the server the full text.
-- Every command changes only the caller's own profile, logs an "Admin" custom event and prints to the Output, then
-- syncs the state. Replies go back as a toast ("Admin: ...").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Seeds = require(Shared.Config.Seeds)
local GameConfig = require(Shared.Config.Game)
local AdminCommands = require(Shared.Logic.AdminCommands)
local ProfileTemplate = require(Shared.Logic.ProfileTemplate)

local Analytics = require(script.Parent.Analytics)
local RemoteService = require(script.Parent.RemoteService)
local DataService = require(script.Parent.DataService)
local TutorialService = require(script.Parent.TutorialService)
local CrystalService = require(script.Parent.CrystalService)

local AdminService = {}

local IS_STUDIO = RunService:IsStudio()
local COMMAND_NAME = "CrystalGroveAdmin"
local MIN_SECONDS_BETWEEN = 0.5 -- one command per half second per player

local seedIds: { string } = {}
local lastAt: { [Player]: number } = {}

-- Sends the caller a toast and prints the same line to the Output.
local function reply(player: Player, text: string)
	RemoteService:Fire("Toast", player, "Admin.Reply", { text = text })
	print(("[Admin] %s: %s"):format(player.Name, text))
end

-- Applies one parsed command to the caller's live profile. Returns the reply text.
local function apply(player: Player, data: { [string]: any }, command: AdminCommands.Command): string
	local name = command.Name
	if name == "coins" then
		local amount = command.Amount :: number
		data.Coins = amount
		return "coins set to " .. amount
	elseif name == "seeds" then
		local seedId = command.SeedId :: string
		local amount = command.Amount :: number
		data.SeedBag[seedId] = (data.SeedBag[seedId] or 0) + amount
		return ("+%d %s (now %d)"):format(amount, seedId, data.SeedBag[seedId])
	elseif name == "ready" then
		-- FinishNow marks each crystal instant-grown, so admin-made crystals never reach the weekly board.
		local count = CrystalService:FinishAll(player)
		return count .. " crystal(s) ready (instant-grown: they don't count for the board)"
	elseif name == "tutorialReset" then
		-- Like a new player as far as the tutorial can tell: the batch 4 rule skips the tutorial for anyone who has
		-- shattered before, and the plant count is shatters + crystals on pedestals, so both go back to zero, and the
		-- bag goes back to the template's single Quartz.
		data.Tutorial = { Step = 0, Done = false }
		data.Stats.Shatters = 0
		table.clear(data.Pedestals)
		data.SeedBag = ProfileTemplate.new().SeedBag
		CrystalService:RefreshPlot(player)
		TutorialService:IsActive(player) -- starts the tutorial (step 1) on the reset profile
		return "tutorial reset (crystals cleared, shatters 0, bag = 1 Quartz)"
	elseif name == "dailyReset" then
		local fresh = ProfileTemplate.new()
		data.Streak = fresh.Streak
		data.DailyGoals = fresh.DailyGoals
		return "daily streak and today's goals cleared"
	elseif name == "tier" then
		local tier = command.Amount :: number
		data.HighestUnlockedTier = tier
		return "highest unlocked tier set to " .. tier
	elseif name == "wipe" then
		-- The template, in place (the profile keeps the same table). The receipt history is kept, so a purchase
		-- Roblox delivers again is still recognised and never granted twice.
		local receipts = data.Monetization.ProcessedReceipts
		local now = os.time()
		table.clear(data)
		for key, value in ProfileTemplate.new() do
			data[key] = value
		end
		data.Monetization.ProcessedReceipts = receipts
		data.FirstJoinAt = now
		data.LastJoinAt = now
		data.Sessions = 1
		CrystalService:RefreshPlot(player)
		TutorialService:IsActive(player)
		return "profile wiped to the template (receipt history kept)"
	end
	return "unknown command"
end

-- One "/cg ..." message from a player.
local function onTriggered(source: TextSource, text: string)
	local player = Players:GetPlayerByUserId(source.UserId)
	if player == nil then
		return
	end
	local allowed = AdminCommands.isAllowed(
		IS_STUDIO,
		game.GameId,
		GameConfig.DevUniverseId,
		game.CreatorType == Enum.CreatorType.User,
		game.CreatorId,
		player.UserId
	)
	if not allowed then
		return -- silently: in the DEV universe only the owner gets an answer
	end
	local now = os.clock()
	if now - (lastAt[player] or 0) < MIN_SECONDS_BETWEEN then
		return
	end
	lastAt[player] = now

	local command, reason = AdminCommands.parse(text, seedIds)
	if command == nil then
		reply(player, reason or AdminCommands.Usage)
		return
	end
	local data = DataService:GetData(player)
	if data == nil then
		reply(player, "profile not loaded yet")
		return
	end
	local ok, result = pcall(apply, player, data, command)
	if not ok then
		warn(("[Admin] %s failed for %s: %s"):format(command.Name, player.Name, tostring(result)))
		reply(player, command.Name .. " failed")
		return
	end
	Analytics:Custom(
		player,
		"Admin",
		command.Amount or 1,
		{ [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = command.Name }
	)
	DataService:SyncState(player)
	reply(player, result)
end

function AdminService:Init()
	for _, seed in Seeds do
		table.insert(seedIds, seed.Id)
	end
end

function AdminService:Start()
	if not AdminCommands.existsHere(IS_STUDIO, game.GameId, GameConfig.DevUniverseId) then
		return -- the live experience: no command is ever created
	end
	local existing = TextChatService:FindFirstChild(COMMAND_NAME)
	if existing ~= nil then
		existing:Destroy()
	end
	local command = Instance.new("TextChatCommand")
	command.Name = COMMAND_NAME
	command.PrimaryAlias = AdminCommands.Alias
	command.AutocompleteVisible = false
	-- Newer engine versions document DeliverMessage (false = sink the message and pass the full text to Triggered).
	-- The Studio used on 2026-11-24 doesn't have that member yet; there, Triggered already receives the full message
	-- ("/cg coins 500", checked in Play Solo) and the message isn't posted to the chat (the sender's client got no
	-- MessageReceived for it). Set it when it exists, ignore it otherwise.
	pcall(function()
		(command :: any).DeliverMessage = false
	end)
	command.Triggered:Connect(onTriggered)
	command.Parent = TextChatService

	Players.PlayerRemoving:Connect(function(player)
		lastAt[player] = nil
	end)
	if IS_STUDIO then
		print("[Admin] /cg command ready (Studio)")
	else
		print("[Admin] /cg command ready (DEV universe, owner only)")
	end
end

return AdminService
