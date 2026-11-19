--!strict
-- Analytics: thin server-side wrapper around Roblox's AnalyticsService.
-- Keeps gameplay code decoupled from the raw service and guarantees analytics failures never break gameplay.
--
-- Respect Roblox's per-experience limits when calling these helpers:
--   * 5 currency types
--   * 20 transaction types
--   * 100 item SKUs
--   * 10 funnels
--   * funnel steps must be in the range 1..100

local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local Analytics = {}

-- Runs fn inside a pcall. Failures only warn in Studio, and never propagate to the caller.
local function safeCall(methodName: string, fn: () -> ())
	local ok: boolean, err: any = pcall(fn)
	if not ok and RunService:IsStudio() then
		warn("[Analytics] " .. methodName .. " failed: " .. tostring(err))
	end
end

-- No yielding here: this service only forwards calls, so there is nothing to wire up.
function Analytics:Init() end

-- Nothing to schedule; kept for the standard service lifecycle.
function Analytics:Start() end

-- Logs an arbitrary custom event (value defaults to 1, as AnalyticsService requires a positive value).
function Analytics:Custom(player: Player, eventName: string, value: number?, customFields: { [string]: any }?)
	if player == nil or player.Parent == nil then
		return
	end

	safeCall("Custom", function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1, customFields)
	end)
end

-- Logs an economy transaction. Roblox requires amount > 0 and endingBalance >= 0, so invalid calls are skipped.
function Analytics:Economy(
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?,
	customFields: { [string]: any }?
)
	if player == nil or player.Parent == nil then
		return
	end
	if amount <= 0 or endingBalance < 0 then
		return
	end

	safeCall("Economy", function()
		AnalyticsService:LogEconomyEvent(
			player,
			flowType,
			currencyType,
			amount,
			endingBalance,
			transactionType,
			itemSku or "",
			customFields
		)
	end)
end

-- Logs a single step of the built-in onboarding funnel.
function Analytics:Onboarding(player: Player, step: number, stepName: string, customFields: { [string]: any }?)
	if player == nil or player.Parent == nil then
		return
	end

	safeCall("Onboarding", function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, customFields)
	end)
end

-- Logs a single step of a custom funnel (max 10 funnels per experience, steps 1..100).
function Analytics:Funnel(
	player: Player,
	funnelName: string,
	funnelSessionId: string,
	step: number,
	stepName: string,
	customFields: { [string]: any }?
)
	if player == nil or player.Parent == nil then
		return
	end

	safeCall("Funnel", function()
		AnalyticsService:LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customFields)
	end)
end

-- Logs progression along a named path (e.g. "WeaponSkill") with a start/complete/fail status.
function Analytics:Progression(
	player: Player,
	pathName: string,
	status: Enum.AnalyticsProgressionType,
	level: number,
	levelName: string,
	customFields: { [string]: any }?
)
	if player == nil or player.Parent == nil then
		return
	end

	safeCall("Progression", function()
		AnalyticsService:LogProgressionEvent(player, pathName, status, level, levelName, customFields)
	end)
end

return Analytics
