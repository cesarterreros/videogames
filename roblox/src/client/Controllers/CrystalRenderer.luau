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
local Graphics = require(Shared.Config.Graphics)
local Growth = require(Shared.Logic.Growth)
local Format = require(Shared.Logic.Format)
local Strings = require(Shared.Strings.Strings)

local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
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
	ring: BasePart?, labelLow: boolean,
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
-- The HUD's top row (screen pixels from the top of the safe area) that an own-plot label must stay out of,
-- and how far below it the label's normal spot must be before the label climbs back up (hysteresis).
local TOP_BAND_PX = 130
local TOP_BAND_HYSTERESIS = 30

-- Current graphics profile, re-read whenever the client's SavedQualityLevel changes.
local profile: Graphics.Profile = Graphics.profile(0)
local profileNameNow = Graphics.profileName(0)

local records: { [BasePart]: Record } = {}
local shatterRemote: RemoteEvent? = nil
local stress, stressFrames, stressWindowStart = false, 0, 0
local seedById: { [string]: Seeds.Seed } = {}
for _, seed in Seeds do
	seedById[seed.Id] = seed
end

-- Reads a pedestal's attribute, falling back to `default` when the stored type is wrong.
local function attr(part: Instance, name: string, default: any): any
	local value = part:GetAttribute(name)
	return if type(value) == type(default) then value else default
end

-- The client's graphics level (0 = Automatic). UserSettings can be missing or locked down in some
-- environments, so every step is guarded and any failure falls back to Automatic.
local function readSavedLevel(): any
	local settingsOk, settings = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)
	if not settingsOk or settings == nil then
		return 0
	end
	local valueOk, saved = pcall(function()
		return settings.SavedQualityLevel
	end)
	if not valueOk or saved == nil then
		return 0
	end
	local level = if typeof(saved) == "EnumItem" then saved.Value else saved
	return if type(level) == "number" then level else 0
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

-- Destroys the model (its light and emitter live inside it), the ready ring and the countdown label.
local function destroyVisuals(record: Record)
	local model = record.model
	record.model, record.light, record.emitter = nil, nil, nil
	record.label, record.labelText = nil, ""
	record.labelLow = false
	local ring = record.ring
	record.ring = nil
	if ring ~= nil then
		ring:Destroy()
	end
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
	local model = CrystalBuilder.build(seed.ColorHex, shape, seed.Tier, profile.GlassShell)
	model:SetAttribute("BuiltSeedId", seed.Id)
	model:SetAttribute("BuiltShape", shape)
	model:SetAttribute("BuiltMutation", mutation)
	model:SetAttribute("BuiltTier", seed.Tier)
	model:PivotTo(CFrame.new(pedestal.Position + Vector3.new(0, pedestal.Size.X / 2, 0)))
	model.Parent = pedestal
	record.model = model
	local ok, parsed = pcall(Color3.fromHex, seed.ColorHex)
	local color = if ok and typeof(parsed) == "Color3" then parsed else Color3.new(1, 1, 1)
	record.lastColor = color
	record.light, record.emitter = CrystalVisuals.applyMutation(model, mutation, seed.Tier, color, profile)
	record.appliedScale = 1
	record.baseHeight = model:GetExtentsSize().Y
	record.labelHeight = -1
	local _, label = CrystalVisuals.makeLabel(pedestal)
	record.label, record.labelText = label, ""
end

-- Height the label normally sits at: just above the crystal's top. While growing that is the tween
-- target, once ripe the overgrowth size at the pulse's peak, so the label doesn't bob with the pulse.
local function labelHeightFor(record: Record, now: number, ready: boolean): number
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
	return record.pedestal.Size.X / 2 + record.baseHeight * scale + LABEL_CLEARANCE
end

-- Keeps the label just above the crystal's top, unless low mode owns its offset (see keepLabelClear).
local function placeLabel(record: Record, label: TextLabel, now: number, ready: boolean)
	if record.labelLow then
		return
	end
	local gui = label.Parent
	if gui == nil or not gui:IsA("BillboardGui") then
		return
	end
	local height = labelHeightFor(record, now, ready)
	if math.abs(height - record.labelHeight) > MIN_LABEL_DELTA then
		CrystalVisuals.placeLabel(gui, record.pedestal, height)
		record.labelHeight = height
	end
end

-- Keeps an own-plot label clear of the HUD's top row: at some camera angles the normal label spot lands
-- behind the top button grids, so it drops to just above the pedestal and is pulled toward the camera.
-- Only comes back once the normal spot is safely below the band (hysteresis), so it never flickers.
local function keepLabelClear(record: Record, label: TextLabel, now: number, ready: boolean, myId: number)
	if record.plot:GetAttribute("OwnerUserId") ~= myId then
		return
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local gui = label.Parent
	if gui == nil or not gui:IsA("BillboardGui") then
		return
	end
	local normalY = record.pedestal.Position + Vector3.new(0, labelHeightFor(record, now, ready), 0)
	local point, onScreen = camera:WorldToScreenPoint(normalY)
	if record.labelLow then
		if not onScreen or point.Y < TOP_BAND_PX + TOP_BAND_HYSTERESIS then
			return
		end
		record.labelLow = false
		gui.StudsOffset = Vector3.new(0, 0, 0)
		record.labelHeight = -1
		placeLabel(record, label, now, ready)
		return
	end
	if onScreen and point.Y < TOP_BAND_PX then
		record.labelLow = true
		record.labelHeight = -1
		CrystalVisuals.placeLabel(gui, record.pedestal, record.pedestal.Size.X / 2 + 1)
		-- Camera-relative (StudsOffset is in the camera's space), so the label draws in front of the crystal.
		gui.StudsOffset = Vector3.new(0, 0, 3)
	end
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
		local shatter = shatterRemote
		if record.mode == "Plant" then
			-- Batch 4: pick the seed in the seed picker instead of planting the cheapest one.
			UIController:Open("SeedPicker", record.index)
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
			-- Shown even with an empty bag: the picker then offers the Shop.
			mode, actionText, objectText = "Plant", Strings.get("Prompt.Plant"), ""
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

-- Re-reads the client's graphics level and restyles every crystal in place. A change in the profile's
-- GlassShell flag needs a rebuild (the shells are parts, not a toggle); anything else is re-applying the
-- light and the particles, which also keeps the "at most one light per crystal" budget.
local function applyGraphicsProfile()
	local name = Graphics.profileName(readSavedLevel())
	if name == profileNameNow then
		return
	end
	local oldShell = profile.GlassShell
	profileNameNow, profile = name, Graphics.profile(name)
	if RunService:IsStudio() then
		print("[Graphics] profile=" .. name)
	end
	for _, record in pairs(records) do
		local model = record.model
		if model ~= nil then
			local ok, err = pcall(function()
				if profile.GlassShell ~= oldShell then
					if stress then
						makeFake(record)
					else
						destroyVisuals(record)
						refresh(record)
					end
					return
				end
				-- Stress crystals are fakes, so ask the model what it was built with, not the pedestal.
				local builtMutation = model:GetAttribute("BuiltMutation")
				local builtTier = model:GetAttribute("BuiltTier")
				record.light, record.emitter = CrystalVisuals.applyMutation(
					model,
					if type(builtMutation) == "string" then builtMutation else record.mutation,
					if type(builtTier) == "number" then builtTier else 1,
					record.lastColor or Color3.new(1, 1, 1),
					profile
				)
			end)
			if not ok then
				warn("[Graphics] " .. tostring(err))
			end
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
		ring = nil, labelLow = false,
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
			-- The ripe glow ring hangs off the pedestal, so a crystal's ScaleTo can never stretch it.
			if ready then
				if record.ring == nil then
					record.ring = CrystalVisuals.makeReadyRing(record.pedestal, record.lastColor or Color3.new(1, 1, 1))
				end
			elseif record.ring ~= nil then
				record.ring:Destroy()
				record.ring = nil
			end
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
				keepLabelClear(record, label, now, ready, myId)
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
				local ring = record.ring
				if ring ~= nil then
					CrystalVisuals.pulseRing(ring, clock)
				end
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
	-- Batch 6: the graphics profile follows the client's graphics level (Full by default; Low at levels 1-3).
	applyGraphicsProfile()
	if RunService:IsStudio() then
		print("[Graphics] profile=" .. profileNameNow)
	end
	pcall(function()
		UserSettings()
			:GetService("UserGameSettings")
			:GetPropertyChangedSignal("SavedQualityLevel")
			:Connect(applyGraphicsProfile)
	end)

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
