--!strict
-- Renders every plot's crystals: builds models, ticks growth, label text and plant/shatter prompts.
-- The client is only a view: it reacts to pedestal attributes and fires Plant/Shatter; the server decides.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Seeds = require(Shared.Config.Seeds)
local RollsConfig = require(Shared.Config.Rolls)
local GameConfig = require(Shared.Config.Game)
local Growth = require(Shared.Logic.Growth)
local Format = require(Shared.Logic.Format)
local Strings = require(Shared.Strings.Strings)

local StateController = require(script.Parent.StateController)
local CrystalBuilder = require(script.Parent.CrystalBuilder)
local CrystalVisuals = require(script.Parent.CrystalVisuals)

local CrystalRenderer = {}

-- One record per pedestal: the last known server state plus every handle the client owns.
-- stylua: ignore start
type Record = {
	pedestal: BasePart, plot: Model, index: number, plotIndex: number, seedId: string, shape: number,
	mutation: string, plantedAt: number, readyAt: number, model: Model?, light: PointLight?, emitter: ParticleEmitter?,
	label: TextLabel?, labelText: string, prompt: ProximityPrompt?, mode: string?, promptSeedId: string?,
	appliedScale: number, fromScale: number, toScale: number, tickStart: number, lastColor: Color3?,
	cooldownUntil: number, pending: boolean, fakeReady: boolean, baseHeight: number, labelHeight: number,
}
-- stylua: ignore end

-- Crystals farther than this from the camera are not scaled every frame.
local FAR_DISTANCE = 160
-- Smallest scale change worth a ScaleTo, prompt re-enable delay, stress log window and mutation cycle.
local MIN_SCALE_DELTA = 0.003
local PROMPT_COOLDOWN = 1
local STRESS_WINDOW = 2
local STRESS_MUTATIONS = { "Glowing", "Molten", "Prismatic" }
-- Label centre above the crystal's top (the label is 2 studs tall, so 0.5 studs of air), the
-- ripe pulse's peak (scaleFor's 1 + 0.04), and the smallest height change worth moving the label.
local LABEL_CLEARANCE = 1.5
local PULSE_PEAK = 1.04
local MIN_LABEL_DELTA = 0.05

local records: { [BasePart]: Record } = {}
local plantRemote: RemoteEvent? = nil
local shatterRemote: RemoteEvent? = nil
local stress, stressFrames, stressWindowStart = false, 0, 0
local seedById: { [string]: Seeds.Seed } = {}
for _, seed in Seeds do
	seedById[seed.Id] = seed
end

-- Reads an attribute, falling back to `default` when the stored type is wrong.
local function attr(part: Instance, name: string, default: any): any
	local value = part:GetAttribute(name)
	return if type(value) == type(default) then value else default
end

-- Scale a record should have right now: the growth curve, or the overgrowth pulse once ripe.
local function scaleNow(record: Record, now: number): number
	local ready = record.fakeReady or Growth.isReady(now, record.readyAt)
	local over = 0
	if not record.fakeReady then
		over = Growth.overgrowth(now, record.readyAt, RollsConfig.Overgrowth.PerHour, RollsConfig.Overgrowth.Cap)
	end
	return CrystalVisuals.scaleFor(now, record.plantedAt, record.readyAt, ready, over, os.clock())
end

-- Applies a scale only when it visibly changed (the Scale property is never read).
local function applyScale(record: Record, target: number)
	local model = record.model
	if model == nil or math.abs(target - record.appliedScale) <= MIN_SCALE_DELTA then
		return
	end
	model:ScaleTo(target)
	record.appliedScale = target
end

-- Destroys the model (its light and emitter live inside it) and the countdown label.
local function destroyVisuals(record: Record)
	local model = record.model
	record.model, record.light, record.emitter = nil, nil, nil
	record.label, record.labelText = nil, ""
	if model ~= nil then
		model:Destroy()
	end
	local gui = record.pedestal:FindFirstChild("Countdown")
	if gui ~= nil then
		gui:Destroy()
	end
end

-- Builds the model for a seed, shape and mutation and puts it on the pedestal.
local function buildVisual(record: Record, seed: Seeds.Seed, shape: number, mutation: string)
	destroyVisuals(record)
	local pedestal = record.pedestal
	local model = CrystalBuilder.build(seed.ColorHex, shape, seed.Tier)
	model:SetAttribute("BuiltSeedId", seed.Id)
	model:SetAttribute("BuiltShape", shape)
	model:SetAttribute("BuiltMutation", mutation)
	model:PivotTo(CFrame.new(pedestal.Position + Vector3.new(0, pedestal.Size.X / 2, 0)))
	model.Parent = pedestal
	record.model = model
	local ok, parsed = pcall(Color3.fromHex, seed.ColorHex)
	record.lastColor = if ok and typeof(parsed) == "Color3" then parsed else Color3.new(1, 1, 1)
	record.light, record.emitter = CrystalVisuals.applyMutation(model, mutation, seed.Tier, record.lastColor)
	record.appliedScale = 1
	record.baseHeight = model:GetExtentsSize().Y
	record.labelHeight = -1
	local _, label = CrystalVisuals.makeLabel(pedestal)
	record.label, record.labelText = label, ""
end

-- Keeps the label just above the crystal's top: the growth target while growing, and the
-- overgrowth size at the pulse's peak once ripe, so the label doesn't bob with the pulse.
local function placeLabel(record: Record, label: TextLabel, now: number, ready: boolean)
	local gui = label.Parent
	if gui == nil or not gui:IsA("BillboardGui") then
		return
	end
	local scale
	if ready then
		local over = 0
		if not record.fakeReady then
			over = Growth.overgrowth(now, record.readyAt, RollsConfig.Overgrowth.PerHour, RollsConfig.Overgrowth.Cap)
		end
		scale = (1 + over) * PULSE_PEAK
	else
		scale = math.max(record.toScale, record.appliedScale)
	end
	local height = record.pedestal.Size.X / 2 + record.baseHeight * scale + LABEL_CLEARANCE
	if math.abs(height - record.labelHeight) > MIN_LABEL_DELTA then
		CrystalVisuals.placeLabel(gui, record.pedestal, height)
		record.labelHeight = height
	end
end

-- Lowest-tier seed the player owns at least one of, or nil (Seeds is ordered by tier).
local function lowestSeed(): string?
	local state = StateController:Get()
	local bag: any = if state ~= nil then state.SeedBag else nil
	if typeof(bag) ~= "table" then
		return nil
	end
	for _, seed in Seeds do
		local count = bag[seed.Id]
		if type(count) == "number" and count >= 1 then
			return seed.Id
		end
	end
	return nil
end

-- Creates a pedestal prompt with its trigger handler, or returns the existing one.
local function ensurePrompt(record: Record): ProximityPrompt
	local existing = record.prompt
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CrystalPrompt"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Triggered:Connect(function()
		record.cooldownUntil = os.clock() + PROMPT_COOLDOWN
		prompt.Enabled = false
		local plant, shatter, seedId = plantRemote, shatterRemote, record.promptSeedId
		if record.mode == "Plant" and seedId ~= nil and plant ~= nil then
			plant:FireServer(record.index, seedId)
		elseif record.mode == "Shatter" and shatter ~= nil then
			shatter:FireServer(record.index)
		end
	end)
	prompt.Parent = record.pedestal
	record.prompt = prompt
	return prompt
end

-- Recomputes a pedestal's prompt; pedestals outside the local player's plot get none.
local function updatePrompt(record: Record)
	local player = Players.LocalPlayer
	if stress or player == nil or record.plot:GetAttribute("OwnerUserId") ~= player.UserId then
		local old = record.prompt
		record.prompt, record.mode = nil, nil
		if old ~= nil then
			old:Destroy()
		end
		return
	end

	local mode: string? = nil
	local actionText, objectText = "", ""
	if record.pedestal:GetAttribute("Unlocked") == true then
		local seed = seedById[record.seedId]
		if record.seedId == "" or seed == nil then
			local pick = lowestSeed()
			if pick ~= nil then
				mode, actionText, objectText = "Plant", Strings.get("Prompt.Plant"), Strings.get("Seed." .. pick)
				record.promptSeedId = pick
			end
		elseif record.fakeReady or Growth.isReady(workspace:GetServerTimeNow(), record.readyAt) then
			mode, actionText = "Shatter", Strings.get("Prompt.Shatter")
			objectText = Strings.get("Seed." .. seed.Id)
		end
	end

	record.mode = mode
	local prompt: ProximityPrompt? = if mode ~= nil then ensurePrompt(record) else record.prompt
	if prompt == nil then
		return
	end
	if mode ~= nil then
		if prompt.ActionText ~= actionText then
			prompt.ActionText = actionText
		end
		if prompt.ObjectText ~= objectText then
			prompt.ObjectText = objectText
		end
	end
	local enabled = mode ~= nil and os.clock() >= record.cooldownUntil
	if prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
end

-- Reads a pedestal's attributes and brings its visuals, label and prompt up to date.
local function refreshRecord(record: Record)
	local pedestal = record.pedestal
	record.seedId = attr(pedestal, "SeedId", "")
	record.shape = attr(pedestal, "Shape", 0)
	record.mutation = attr(pedestal, "Mutation", "None")
	record.plantedAt = attr(pedestal, "PlantedAt", 0)
	record.readyAt = attr(pedestal, "ReadyAt", 0)
	if stress then
		return
	end

	local seed = seedById[record.seedId]
	if record.seedId == "" or seed == nil then
		destroyVisuals(record)
		updatePrompt(record)
		return
	end

	local model = record.model
	local stale = model == nil
		or model:GetAttribute("BuiltSeedId") ~= seed.Id
		or model:GetAttribute("BuiltShape") ~= record.shape
		or model:GetAttribute("BuiltMutation") ~= record.mutation
	if stale then
		buildVisual(record, seed, record.shape, record.mutation)
	end

	applyScale(record, scaleNow(record, workspace:GetServerTimeNow()))
	-- Restart the per-frame tween from the scale just applied, so a new crystal never eases toward an old target.
	record.fromScale, record.toScale, record.tickStart = record.appliedScale, record.appliedScale, os.clock()
	if record.label ~= nil then
		local now = workspace:GetServerTimeNow()
		placeLabel(record, record.label, now, Growth.isReady(now, record.readyAt))
	end
	updatePrompt(record)
end

-- Refreshes a record, logging instead of failing when an attribute is malformed.
local function refresh(record: Record)
	local ok, err = pcall(refreshRecord, record)
	if not ok then
		warn("[Crystal] " .. tostring(err))
	end
end

-- Coalesces the server's burst of SetAttribute calls into one deferred refresh.
local function schedule(record: Record)
	if record.pending then
		return
	end
	record.pending = true
	task.defer(function()
		record.pending = false
		refresh(record)
	end)
end

-- Studio stress: replaces a record's crystal with a fake, already-ready Ruby.
local function makeFake(record: Record)
	destroyVisuals(record)
	updatePrompt(record)
	local seed = seedById["Ruby"]
	if seed == nil then
		return
	end
	record.fakeReady = true
	local mutation = STRESS_MUTATIONS[(record.index + record.plotIndex) % 3 + 1]
	buildVisual(record, seed, record.index * 7919 + record.plotIndex * 104729, mutation)
	applyScale(record, scaleNow(record, workspace:GetServerTimeNow()))
	if record.label ~= nil then
		CrystalVisuals.setLabel(record.label, Strings.get("Crystal.Ready"), true)
	end
end

-- Toggles stress mode: fake ready crystals everywhere, or the real attributes again.
local function applyStress(on: boolean)
	if on == stress then
		return
	end
	stress = on
	stressFrames, stressWindowStart = 0, os.clock()
	for _, record in pairs(records) do
		if on then
			pcall(makeFake, record)
		else
			pcall(function()
				record.fakeReady = false
				destroyVisuals(record)
				refreshRecord(record)
			end)
		end
	end
end

-- Registers a pedestal and routes its attribute changes through a coalesced refresh.
local function addRecord(plot: Model, plotIndex: number, pedestal: BasePart)
	if records[pedestal] ~= nil then
		return
	end
	-- stylua: ignore start
	local record: Record = {
		pedestal = pedestal, plot = plot, index = attr(pedestal, "Index", 0), plotIndex = plotIndex,
		seedId = "", shape = 0, mutation = "None", plantedAt = 0, readyAt = 0,
		model = nil, light = nil, emitter = nil, label = nil, labelText = "",
		prompt = nil, mode = nil, promptSeedId = nil,
		appliedScale = 1, fromScale = 1, toScale = 1, tickStart = os.clock(),
		lastColor = nil, cooldownUntil = 0, pending = false, fakeReady = false, baseHeight = 0, labelHeight = -1,
	}
	-- stylua: ignore end
	records[pedestal] = record
	pedestal.AttributeChanged:Connect(function()
		schedule(record)
	end)
	refresh(record)
	if stress then
		pcall(makeFake, record)
	end
end

-- Creates records for one plot and watches for new pedestals and owner changes.
local function setupPlot(plot: Model)
	local pedestals = plot:WaitForChild("Pedestals")
	local plotIndex = attr(plot, "PlotIndex", 0)
	for _, child in pedestals:GetChildren() do
		if child:IsA("BasePart") then
			addRecord(plot, plotIndex, child)
		end
	end
	pedestals.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			addRecord(plot, plotIndex, child)
		end
	end)
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		for _, record in pairs(records) do
			if record.plot == plot then
				pcall(updatePrompt, record)
			end
		end
	end)
end

-- Refreshes the prompts of every pedestal in the local player's plot.
local function updateOwnPrompts()
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	for _, record in pairs(records) do
		if record.plot:GetAttribute("OwnerUserId") == player.UserId then
			pcall(updatePrompt, record)
		end
	end
end

-- One render tick: refreshes tween targets, label text and prismatic hue; the heartbeat smooths scale.
local function tick()
	-- Also runs in stress mode, so the fake crystals' labels and prismatic hues cost what real ones do.
	local now = workspace:GetServerTimeNow()
	local ahead = now + GameConfig.RenderTickSeconds
	local player = Players.LocalPlayer
	local myId = if player ~= nil then player.UserId else -1
	for _, record in pairs(records) do
		local model = record.model
		if model ~= nil then
			local ready = record.fakeReady or Growth.isReady(now, record.readyAt)
			if not ready then
				record.fromScale = record.appliedScale
				record.toScale = CrystalVisuals.scaleFor(ahead, record.plantedAt, record.readyAt, false, 0, 0)
				record.tickStart = os.clock()
			end
			local label = record.label
			if label ~= nil then
				local text = if ready then Strings.get("Crystal.Ready") else Format.countdown(record.readyAt - now)
				record.labelText = text
				CrystalVisuals.setLabel(label, text, ready)
				placeLabel(record, label, now, ready)
			end
			if record.mutation == "Prismatic" then
				CrystalVisuals.setPrismaticHue(model, record.light, (os.clock() * 0.08 + record.index * 0.13) % 1)
			end
		end
		if record.plot:GetAttribute("OwnerUserId") == myId then
			pcall(updatePrompt, record)
		end
	end
end

-- Per-frame smoothing: eases visible crystals toward the tick target and pulses the ripe ones.
local function onHeartbeat()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local camPos = camera.CFrame.Position
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local crystals = 0
	for _, record in pairs(records) do
		local model = record.model
		if model ~= nil then
			crystals += 1
			if (record.pedestal.Position - camPos).Magnitude <= FAR_DISTANCE then
				if record.fakeReady or Growth.isReady(now, record.readyAt) then
					applyScale(record, scaleNow(record, now))
				else
					local alpha = math.clamp((clock - record.tickStart) / GameConfig.RenderTickSeconds, 0, 1)
					applyScale(record, record.fromScale + (record.toScale - record.fromScale) * alpha)
				end
			end
		end
	end

	if stress then
		stressFrames += 1
		local window = clock - stressWindowStart
		if window >= STRESS_WINDOW then
			local fps = math.floor(stressFrames / window + 0.5)
			print(("[Stress] fps=%d crystals=%d"):format(fps, crystals))
			stressFrames, stressWindowStart = 0, clock
		end
	end
end

-- Nothing to set up. Must not yield.
function CrystalRenderer:Init() end

function CrystalRenderer:Start()
	local plots = workspace:WaitForChild("Map"):WaitForChild("Plots")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	plantRemote = remotes:WaitForChild("Plant") :: RemoteEvent
	shatterRemote = remotes:WaitForChild("Shatter") :: RemoteEvent

	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") then
			setupPlot(plot)
		end
	end
	plots.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.spawn(setupPlot, child)
		end
	end)
	StateController.Changed:Connect(updateOwnPrompts)

	-- Studio and the DEV universe only (never live): the StressTest attribute swaps every pedestal for a
	-- fake ready crystal. On a phone, set it from the developer console's server command line.
	if RunService:IsStudio() or game.GameId == GameConfig.DevUniverseId then
		workspace:GetAttributeChangedSignal("StressTest"):Connect(function()
			applyStress(workspace:GetAttribute("StressTest") == true)
		end)
		applyStress(workspace:GetAttribute("StressTest") == true)
	end

	task.spawn(function()
		while true do
			task.wait(GameConfig.RenderTickSeconds)
			local ok, err = pcall(tick)
			if not ok then
				warn("[Crystal] " .. tostring(err))
			end
		end
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
end

-- The pedestal with this index in the local player's plot, or nil.
function CrystalRenderer:GetOwnPedestal(index: number): BasePart?
	local player = Players.LocalPlayer
	if player == nil then
		return nil
	end
	for _, record in pairs(records) do
		if record.index == index and record.plot:GetAttribute("OwnerUserId") == player.UserId then
			return record.pedestal
		end
	end
	return nil
end

-- Colour of the latest crystal on that own-plot pedestal (kept after the crystal is cleared).
function CrystalRenderer:GetLastColor(index: number): Color3?
	local player = Players.LocalPlayer
	if player == nil then
		return nil
	end
	for _, record in pairs(records) do
		if record.index == index and record.plot:GetAttribute("OwnerUserId") == player.UserId then
			return record.lastColor
		end
	end
	return nil
end

return CrystalRenderer
