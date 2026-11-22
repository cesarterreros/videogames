--!strict
-- Toasts.luau - the non-blocking toast stack: short finished lines of text dropped just under the top of the
-- screen, newest at the bottom. Each row sits for two and a half seconds, then fades away. Nothing here blocks
-- input (the root and the stack are Active = false), the screen keeps no remotes and it never looks up a
-- Strings key: callers hand it finished text through Push.

local TweenService = game:GetService("TweenService")

-- Pixel layout.
local ROW_W = 340
local ROW_H = 30
local GAP = 4 -- gap between neighbouring rows
local MAX_ROWS = 3
local STACK_TOP = 52 -- distance of the stack from the top of the safe area
local MAX_TEXT_SIZE = 18 -- cap for the scaled row text

-- Timing.
local LIFE_SECONDS = 2.5
local FADE_SECONDS = 0.25

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
	Push: (text: string, gold: boolean?) -> (),
}

local Toasts = {}

-- Builds the toast layer inside ctx.Gui and returns the standard screen table plus Push.
function Toasts.new(ctx: any): Screen
	local Theme = ctx.Theme
	local Components = ctx.Components
	local COLORS = Theme.Colors

	-- 1. Root and stack: transparent, non-interactive, above the panels (ZIndex 50), always visible.
	local root = Instance.new("Frame")
	root.Name = "Toasts"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.ZIndex = 50
	root.Visible = true

	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.AnchorPoint = Vector2.new(0.5, 0)
	stack.Position = UDim2.new(0.5, 0, 0, STACK_TOP)
	stack.Size = UDim2.new(0, ROW_W, 0, MAX_ROWS * ROW_H + (MAX_ROWS - 1) * GAP)
	stack.BackgroundTransparency = 1
	stack.Active = false
	stack.ZIndex = 50

	local stackLayout = Instance.new("UIListLayout")
	stackLayout.FillDirection = Enum.FillDirection.Vertical
	stackLayout.Padding = UDim.new(0, GAP)
	stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stackLayout.Parent = stack

	stack.Parent = root

	-- Rows currently on screen, oldest first. LayoutOrder grows with every push so new rows land at the
	-- bottom of the stack under the vertical list layout.
	local rows: { Frame } = {}
	local nextOrder = 0

	local function forget(row: Frame)
		for index, existing in rows do
			if existing == row then
				table.remove(rows, index)
				return
			end
		end
	end

	-- Fades the row background, its label text and both borders (the row outline and the label's glyph
	-- outline) to fully transparent, then destroys the row.
	local function fadeRow(row: Frame)
		if row.Parent == nil then
			return
		end
		local info = TweenInfo.new(FADE_SECONDS)
		TweenService:Create(row, info, { BackgroundTransparency = 1 }):Play()

		local rowStroke = row:FindFirstChildOfClass("UIStroke")
		if rowStroke then
			TweenService:Create(rowStroke, info, { Transparency = 1 }):Play()
		end

		for _, child in row:GetChildren() do
			if child:IsA("TextLabel") then
				TweenService:Create(child, info, { TextTransparency = 1 }):Play()
			end
			local labelStroke = child:FindFirstChildOfClass("UIStroke")
			if labelStroke then
				TweenService:Create(labelStroke, info, { Transparency = 1 }):Play()
			end
		end

		task.delay(FADE_SECONDS, function()
			forget(row)
			if row.Parent ~= nil then
				row:Destroy()
			end
		end)
	end

	-- Adds one row at the bottom of the stack. Empty or non-string text is ignored.
	local function push(text: string, gold: boolean?)
		if type(text) ~= "string" or #text == 0 then
			return
		end
		local isGold = gold == true

		local row = Instance.new("Frame")
		row.Name = "Toast"
		row.Size = UDim2.fromOffset(ROW_W, ROW_H)
		row.BackgroundColor3 = Theme.color(COLORS.Panel)
		row.BackgroundTransparency = 0.1
		row.BorderSizePixel = 0
		row.Active = false
		row.ZIndex = 50
		row.LayoutOrder = nextOrder
		nextOrder += 1

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.Corner)
		corner.Parent = row

		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = Theme.color(if isGold then COLORS.Gold else COLORS.Stroke)
		stroke.Parent = row

		-- Components.label scales its text and hangs a UITextSizeConstraint on it; cap that at 18.
		local label = Components.label({
			Name = "Text",
			Text = text,
			Size = UDim2.new(1, -12, 1, 0),
			Position = UDim2.new(0, 6, 0, 0),
			Color = if isGold then COLORS.Gold else COLORS.Text,
			Parent = row,
		})
		label.ZIndex = 51
		local textSize = label:FindFirstChildOfClass("UITextSizeConstraint")
		if textSize then
			textSize.MaxTextSize = MAX_TEXT_SIZE
		end

		-- A 4th row pushes the oldest off the stack at once.
		if #rows >= MAX_ROWS then
			local oldest = rows[1]
			table.remove(rows, 1)
			if oldest then
				oldest:Destroy()
			end
		end

		row.Parent = stack
		table.insert(rows, row)

		task.delay(LIFE_SECONDS, function()
			fadeRow(row)
		end)
	end

	-- Open takes either a table with a Text (and an optional Gold) field or a plain string.
	local function open(args: any?)
		if typeof(args) == "table" then
			local payload: any = args
			local text = payload.Text
			if type(text) == "string" then
				push(text, payload.Gold == true)
			end
			return
		end
		if type(args) == "string" then
			push(args :: string, false)
		end
	end

	local screen: Screen = {
		Root = root,
		Push = push,
		Open = open,
		Close = function()
			for _, row in rows do
				row:Destroy()
			end
			table.clear(rows)
		end,
		Update = function(_snapshot: any) end,
		IsOpen = function(): boolean
			return #rows > 0
		end,
	}

	-- Everything is built, so attach the layer last.
	root.Parent = ctx.Gui

	return screen
end

return Toasts
