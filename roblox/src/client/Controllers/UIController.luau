--!strict
-- UIController.luau - owns the client's single ScreenGui, builds every screen from UI/Screens, and routes
-- between them: which panel is open (at most one), the dimmed backdrop behind it, results, toasts and the
-- tutorial's HUD lock. It also feeds every snapshot from StateController into each screen's Update.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared.Strings.Strings)
local Seeds = require(Shared.Config.Seeds)
local Rolls = require(Shared.Config.Rolls)
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Config.Progression)
local Game = require(Shared.Config.Game)
local Sounds = require(Shared.Config.Sounds)
local Format = require(Shared.Logic.Format)
local LogicEconomy = require(Shared.Logic.Economy)
local Surge = require(Shared.Logic.Surge)
local Codex = require(Shared.Logic.Codex)
local Goals = require(Shared.Logic.Goals)
local Growth = require(Shared.Logic.Growth)
local MonetizationConfig = require(Shared.Config.Monetization)
local InstantGrow = require(Shared.Logic.InstantGrow)
local AdCaps = require(Shared.Logic.AdCaps)
local LuckBoost = require(Shared.Logic.LuckBoost)
local WeekId = require(Shared.Logic.WeekId)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
local StateController = require(script.Parent.StateController)
local SoundController = require(script.Parent.SoundController)
local PurchaseController = require(script.Parent.PurchaseController)

local Screens = script.Parent.Parent.UI.Screens

-- Order the screens are built in: the HUD first (the panels and the brightness slot live above it), the
-- always-visible layers last.
local SCREEN_ORDER: { string } = {
	"Hud",
	"SeedPicker",
	"Shop",
	"Upgrades",
	"Codex",
	"Daily",
	"Goals",
	"Odds",
	"Store",
	"CrystalMenu",
	"OfferPopup",
	"Result",
	"Toasts",
}

-- The modal panels: at most one is open and the backdrop sits behind it.
local PANELS: { [string]: boolean } = {
	SeedPicker = true,
	Shop = true,
	Upgrades = true,
	Codex = true,
	Daily = true,
	Goals = true,
	Odds = true,
	Store = true,
	CrystalMenu = true,
	OfferPopup = true,
}

-- HUD button name -> the panel a press opens, used only while the tutorial locks the HUD.
local LOCK_MAP: { [string]: string } = {
	Shop = "Shop",
	Upgrades = "Upgrades",
	Codex = "Codex",
	Daily = "Daily",
	Goals = "Goals",
	Odds = "Odds",
	Surge = "Odds",
}

local PANEL_Z = 10
local HUD_Z = 1
local RESULT_Z = 40
local TOASTS_Z = 50

local BACKDROP_TRANSPARENCY = 0.6

export type Screen = {
	Root: Frame?,
	Buttons: { [string]: GuiButton }?,
	Open: ((args: any?) -> ())?,
	Close: (() -> ())?,
	Update: ((snapshot: any) -> ())?,
	Push: ((text: string, gold: boolean?) -> ())?,
}

local UIController = {}

local screens: { [string]: Screen } = {}
local gui: ScreenGui? = nil
local backdrop: TextButton? = nil
local openPanel: string? = nil
local isLockedState: boolean = false
local allowedName: string? = nil
local firstSnapshotDone: boolean = false
local isReadyState: boolean = false

local panelOpened = Instance.new("BindableEvent")
local panelClosed = Instance.new("BindableEvent")
local readyEvent = Instance.new("BindableEvent")

-- Fire with the panel's name whenever a panel opens or closes.
UIController.PanelOpened = panelOpened.Event
UIController.PanelClosed = panelClosed.Event
-- Fires once, when Start has built every screen.
UIController.Ready = readyEvent.Event

local function isPanel(name: string): boolean
	return PANELS[name] == true
end

-- Stacking order by screen name; panels share one level, the result card and the toasts sit above them.
local function zIndexOf(name: string): number?
	if name == "Hud" then
		return HUD_Z
	end
	if name == "Result" then
		return RESULT_Z
	end
	if name == "Toasts" then
		return TOASTS_Z
	end
	if isPanel(name) then
		return PANEL_Z
	end
	return nil
end

-- The panels Open may show right now: planting is always part of the flow, plus whatever the tutorial's
-- allowed HUD button opens.
local function panelAllowed(name: string): boolean
	if not isLockedState then
		return true
	end
	if name == "SeedPicker" then
		return true
	end
	if typeof(allowedName) == "string" then
		return LOCK_MAP[allowedName :: string] == name
	end
	return false
end

-- Nothing to set up. Must not yield.
function UIController:Init() end

-- Builds the ScreenGui and every screen, then wires state, remotes and the daily auto-open.
function UIController:Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CrystalGroveUI"
	screenGui.ResetOnSpawn = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.IgnoreGuiInset = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 5
	gui = screenGui

	local ctx: any = {
		Gui = screenGui,
		Player = player,
		Strings = Strings,
		Theme = Theme,
		Components = Components,
		Remotes = ReplicatedStorage:WaitForChild("Remotes"),
		State = StateController,
		Sounds = SoundController,
		UI = UIController,
		Config = {
			Seeds = Seeds,
			Rolls = Rolls,
			Economy = Economy,
			Progression = Progression,
			Game = Game,
			Sounds = Sounds,
			Monetization = MonetizationConfig,
		},
		Logic = {
			Format = Format,
			Economy = LogicEconomy,
			Surge = Surge,
			Codex = Codex,
			Goals = Goals,
			Growth = Growth,
			WeekId = WeekId,
			InstantGrow = InstantGrow,
			AdCaps = AdCaps,
			LuckBoost = LuckBoost,
		},
		-- Batch 5: the only way screens reach purchases, prices and ads (change G).
		Purchase = PurchaseController,
		Now = function(): number
			return workspace:GetServerTimeNow()
		end,
	}

	Components.setClickSound(function()
		SoundController:Play("Click")
	end)

	-- A screen that fails to build is skipped: the rest of the UI still works.
	for _, name in SCREEN_ORDER do
		local ok, created = pcall(function(): any
			return require(Screens:WaitForChild(name)).new(ctx)
		end)
		if ok and typeof(created) == "table" then
			screens[name] = created :: Screen
		else
			warn("[UI] " .. name .. " failed: " .. (if ok then "did not return a screen table" else tostring(created)))
		end
	end

	for _, name in SCREEN_ORDER do
		local screen = screens[name]
		local zIndex = zIndexOf(name)
		if screen ~= nil and zIndex ~= nil then
			local root = screen.Root
			if root ~= nil then
				root.ZIndex = zIndex
			end
		end
	end

	-- Tapping the dimmed area behind an open panel closes it.
	local backdropButton = Instance.new("TextButton")
	backdropButton.Name = "Backdrop"
	backdropButton.Size = UDim2.fromScale(1, 1)
	backdropButton.Position = UDim2.fromScale(0, 0)
	backdropButton.Text = ""
	backdropButton.AutoButtonColor = false
	backdropButton.BackgroundColor3 = Color3.new(0, 0, 0)
	backdropButton.BackgroundTransparency = BACKDROP_TRANSPARENCY
	backdropButton.ZIndex = 9
	backdropButton.Visible = false
	backdropButton.Activated:Connect(function()
		UIController:CloseAll()
	end)
	backdropButton.Parent = screenGui
	backdrop = backdropButton

	-- Everything is built; attach the gui last so it appears complete.
	screenGui.Parent = playerGui

	local function onSnapshot(snapshot: any)
		for _, screen in screens do
			pcall(screen.Update, snapshot)
		end

		-- Only the first snapshot of the session can open the daily panel by itself.
		if firstSnapshotDone or typeof(snapshot) ~= "table" then
			return
		end
		firstSnapshotDone = true

		local data: { [string]: any } = snapshot
		local tutorial = data.Tutorial
		if typeof(tutorial) ~= "table" or tutorial.Done ~= true then
			return
		end
		local streak = data.Streak
		local lastClaim: any = if typeof(streak) == "table" then streak.LastClaimDate else nil
		if lastClaim == WeekId.dateString(workspace:GetServerTimeNow()) then
			return
		end
		UIController:Open("Daily")
	end

	StateController.Changed:Connect(onSnapshot)
	local existing = StateController:Get()
	if existing ~= nil then
		onSnapshot(existing)
	end

	local remotes = ctx.Remotes
	local shatterResult = remotes:WaitForChild("ShatterResult") :: RemoteEvent
	shatterResult.OnClientEvent:Connect(function(payload: any)
		local screen = screens.Result
		if screen ~= nil then
			pcall(screen.Open, payload)
		end
	end)

	-- Batch 5, change N: the session's one offer waits for a clear screen (no result card, no panel open, the
	-- tutorial done), for up to OFFER_WAIT_SECONDS; if the screen never clears, it is dropped for this session.
	local OFFER_WAIT_SECONDS = 30
	local offer = remotes:WaitForChild("Offer") :: RemoteEvent
	offer.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		task.spawn(function()
			local deadline = os.clock() + OFFER_WAIT_SECONDS
			while os.clock() < deadline do
				local snapshot = StateController:Get()
				local tutorialDone = typeof(snapshot) == "table"
					and typeof(snapshot.Tutorial) == "table"
					and snapshot.Tutorial.Done == true
				local result: any = screens.Result
				local resultShowing = result ~= nil and result.IsOpen ~= nil and result.IsOpen() == true
				if tutorialDone and openPanel == nil and not resultShowing then
					UIController:Open("OfferPopup", payload)
					return
				end
				task.wait(0.5)
			end
		end)
	end)

	local function messageHandler(gold: boolean)
		return function(key: any, params: any)
			if typeof(key) ~= "string" then
				return
			end
			local text = Strings.message(key, if typeof(params) == "table" then params else nil)
			UIController:Toast(text, gold)
		end
	end

	local toast = remotes:WaitForChild("Toast") :: RemoteEvent
	toast.OnClientEvent:Connect(messageHandler(false))

	local announce = remotes:WaitForChild("Announce") :: RemoteEvent
	announce.OnClientEvent:Connect(messageHandler(true))

	isReadyState = true
	-- Hub stalls (MapService): a stall prompt opens the panel named by its stall's OpensPanel attribute.
	-- PromptTriggered fires on the client only for the local player's own prompt use.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local stall = prompt:FindFirstAncestorWhichIsA("Model")
		local panel = if stall ~= nil then stall:GetAttribute("OpensPanel") else nil
		if typeof(panel) == "string" then
			UIController:Open(panel)
		end
	end)

	readyEvent:Fire()
end

-- Shows a screen. Panels replace the open one and respect the tutorial lock; the other screens (Result,
-- Toasts, Hud) are always allowed to open themselves.
function UIController:Open(name: string, args: any?)
	local screen = screens[name]
	if screen == nil then
		return
	end

	if not isPanel(name) then
		pcall(screen.Open, args)
		return
	end

	if not panelAllowed(name) then
		return
	end

	-- Through Close, so listeners also get PanelClosed for the panel being replaced.
	if openPanel ~= nil and openPanel ~= name then
		UIController:Close(openPanel :: string)
	end

	pcall(screen.Open, args)
	openPanel = name

	local backdropButton = backdrop
	if backdropButton ~= nil then
		backdropButton.Visible = true
	end

	panelOpened:Fire(name)
end

-- Hides the panel if it is the open one. Panels call this from their close button.
function UIController:Close(name: string)
	if openPanel ~= name then
		return
	end

	local screen = screens[name]
	if screen ~= nil then
		pcall(screen.Close)
	end
	openPanel = nil

	local backdropButton = backdrop
	if backdropButton ~= nil then
		backdropButton.Visible = false
	end

	panelClosed:Fire(name)
end

-- Hides whichever panel is open.
function UIController:CloseAll()
	local name = openPanel
	if name ~= nil then
		UIController:Close(name :: string)
	end
end

-- Drops one finished line of text on the toast stack.
function UIController:Toast(text: string, gold: boolean?)
	local toasts = screens.Toasts
	if toasts == nil then
		return
	end
	pcall(toasts.Push, text, gold)
end

-- The screen table by name, or nil when it failed to build.
function UIController:Get(name: string): Screen?
	return screens[name]
end

-- The name of the open panel, or nil.
function UIController:OpenPanel(): string?
	return openPanel
end

-- Locks or unlocks the tutorial-lockable HUD buttons. While locked, only the panel the allowed button opens
-- (and planting) may be shown. The music and brightness buttons are not part of Buttons and stay usable.
function UIController:SetLocked(value: boolean, allowedButton: string?)
	isLockedState = value
	allowedName = allowedButton

	local hud = screens.Hud
	if hud == nil then
		return
	end
	local buttons = hud.Buttons
	if buttons == nil then
		return
	end

	for buttonName, button in buttons do
		Components.setEnabled(button, not value or buttonName == allowedButton)
	end
end

function UIController:IsLocked(): boolean
	return isLockedState
end

function UIController:IsReady(): boolean
	return isReadyState
end

-- Waits for Start to finish building the UI; returns at once when it already has.
function UIController:WaitUntilReady()
	if isReadyState then
		return
	end
	readyEvent.Event:Wait()
end

-- Exposed for callers that need the gui itself (nil until Start has run).
function UIController:Gui(): ScreenGui?
	return gui
end

return UIController
