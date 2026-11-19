--!strict
-- Hands every player one of the six cave plots built by MapService: the lowest free plot on profile
-- load, the player's display name painted on that plot's sign, the character moved into the cave on
-- every spawn, and the plot released (sign cleared, pedestals back to locked) when the player leaves.
-- MapService:Init must run before PlotService:Init, since the plots are read from the workspace.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared.Strings.Strings)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)

local PlotService = {}

-- Every plot has 13 pedestals; only the documented attributes are reset when a plot is freed.
local MAX_PEDESTALS = 13
-- Seconds to wait for a fresh character's HumanoidRootPart before giving up on the move.
local SPAWN_WAIT_TIMEOUT = 10
-- The spawn marker sits on the plot floor, so lift the character a little above it.
local SPAWN_LIFT = 3

local plotOf: { [Player]: Model } = {}
-- Cached at Init time, in ascending PlotIndex order.
local plotList: { Model } = {}

local assignedEvent = Instance.new("BindableEvent")

-- Fires (player, plot) right after a plot has been assigned to that player.
PlotService.PlotAssigned = assignedEvent.Event

-- Writes the owner's name on the plot's sign plate, ignoring a plot without the expected hierarchy.
local function setSignText(plot: Model, text: string)
	local sign = plot:FindFirstChild("Sign")
	if sign == nil then
		return
	end
	local gui = sign:FindFirstChild("SignGui")
	if gui == nil then
		return
	end
	local label = gui:FindFirstChild("OwnerName")
	if label ~= nil and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- The lowest-index plot that nobody owns yet, or nil when every plot is taken.
local function findFreePlot(): Model?
	for _, plot in plotList do
		if plot:GetAttribute("OwnerUserId") == 0 then
			return plot
		end
	end
	return nil
end

-- Pivots a character onto its owner's cave spawn point once it actually exists in the world.
local function moveToCave(player: Player, character: Model)
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", SPAWN_WAIT_TIMEOUT)
		if root == nil then
			return
		end

		-- One frame of grace so the default spawn placement has finished before we move the character.
		task.wait()

		local plot = plotOf[player]
		if plot == nil or character.Parent == nil then
			return
		end

		local spawnPoint = plot:FindFirstChild("SpawnPoint")
		if spawnPoint == nil or not spawnPoint:IsA("BasePart") then
			return
		end

		character:PivotTo(spawnPoint.CFrame + Vector3.new(0, SPAWN_LIFT, 0))
	end)
end

-- Gives the player the lowest free plot: claims the attributes, paints the sign and fires PlotAssigned.
local function assignPlot(player: Player)
	-- The player may have left while their profile was loading, and only one plot per player.
	if player.Parent ~= Players or plotOf[player] ~= nil then
		return
	end

	local plot = findFreePlot()
	if plot == nil then
		player:Kick(Strings.get("Error.NoPlot"))
		return
	end

	plot:SetAttribute("OwnerUserId", player.UserId)
	setSignText(plot, player.DisplayName)
	plotOf[player] = plot

	assignedEvent:Fire(player, plot)

	-- The character may already have spawned before the profile finished loading.
	local character = player.Character
	if character ~= nil then
		moveToCave(player, character)
	end
end

-- Puts one pedestal back to its unowned state: locked look, no seed, no timer. Index and Gold stay.
local function resetPedestal(pedestal: BasePart)
	pedestal:SetAttribute("Unlocked", false)
	pedestal:SetAttribute("SeedId", "")
	pedestal:SetAttribute("PlantedAt", 0)
	pedestal:SetAttribute("ReadyAt", 0)
	pedestal:SetAttribute("Mutation", "None")
	pedestal:SetAttribute("Shape", 0)
	MapService.setPedestalLook(pedestal, false)

	-- Defensive: a prompt left behind would keep pointing at a pedestal its new owner can't use yet.
	for _, child in pedestal:GetChildren() do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end
end

-- Frees the player's plot when they leave, so the next player can take it.
local function releasePlot(player: Player)
	local plot = plotOf[player]
	if plot == nil then
		return
	end

	plot:SetAttribute("OwnerUserId", 0)
	setSignText(plot, "")

	local pedestals = plot:FindFirstChild("Pedestals")
	if pedestals ~= nil then
		for _, child in pedestals:GetChildren() do
			if child:IsA("BasePart") then
				resetPedestal(child)
			end
		end
	end

	plotOf[player] = nil
end

-- Sends the player into their cave on every spawn, including the one they may already have.
local function hookCharacter(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		moveToCave(player, character)
	end)

	local character = player.Character
	if character ~= nil then
		moveToCave(player, character)
	end
end

-- Caches the plots MapService already built. Must not yield: the Map folder is expected to exist.
function PlotService:Init()
	local map = workspace:FindFirstChild("Map")
	assert(map ~= nil, "[PlotService] workspace.Map is missing – MapService:Init must run first")

	local plotsFolder = map:FindFirstChild("Plots")
	assert(plotsFolder ~= nil, "[PlotService] workspace.Map.Plots is missing")

	local byIndex: { [number]: Model } = {}
	local highestIndex = 0
	for _, child in plotsFolder:GetChildren() do
		if child:IsA("Model") then
			local plotIndex = child:GetAttribute("PlotIndex")
			if typeof(plotIndex) == "number" then
				byIndex[plotIndex] = child
				highestIndex = math.max(highestIndex, plotIndex)
			end
		end
	end
	assert(highestIndex > 0, "[PlotService] no plot models found in workspace.Map.Plots")

	local list: { Model } = {}
	for index = 1, highestIndex do
		local plot = byIndex[index]
		assert(plot ~= nil, "[PlotService] workspace.Map.Plots is missing Plot_" .. index)
		list[index] = plot
	end
	plotList = list
end

-- Connects the data, join and leave signals and catches up with anyone who got here first.
function PlotService:Start()
	DataService.ProfileLoaded:Connect(function(player: Player)
		assignPlot(player)
	end)

	-- Players whose profile loaded before the connection above existed (possible in Studio).
	for _, player in Players:GetPlayers() do
		if DataService:GetData(player) ~= nil then
			assignPlot(player)
		end
	end

	Players.PlayerAdded:Connect(hookCharacter)
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end

	Players.PlayerRemoving:Connect(releasePlot)
end

-- The player's plot, or nil while their profile loads and after they leave.
function PlotService:GetPlot(player: Player): Model?
	return plotOf[player]
end

-- Pedestal number `index` (1..13) of the player's plot, or nil if they have no plot or the slot is gone.
function PlotService:GetPedestal(player: Player, index: number): BasePart?
	-- Also rejects NaN and every non-integer value.
	if index ~= index or index % 1 ~= 0 or index < 1 or index > MAX_PEDESTALS then
		return nil
	end

	local plot = plotOf[player]
	if plot == nil then
		return nil
	end

	local pedestals = plot:FindFirstChild("Pedestals")
	if pedestals == nil then
		return nil
	end

	local pedestal = pedestals:FindFirstChild("Pedestal_" .. index)
	if pedestal == nil or not pedestal:IsA("BasePart") then
		return nil
	end

	return pedestal
end

return PlotService
