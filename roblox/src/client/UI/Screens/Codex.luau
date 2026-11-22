--!strict
-- Codex.luau - the crystal codex panel: one row per seed, one cell per mutation variant. A discovered
-- variant lights its cell up in the seed's colour (with the variant's initial), an undiscovered one is a
-- dark silhouette. A row that has all four variants shows the coin bonus it earns.
-- Rows are built once in new(); Update only repaints cells and texts in place.

-- Column layout, in pixels inside the content frame.
local NAME_W = 110 -- seed name column
local CELL_W = 64 -- one variant cell
local CELL_H = 36
local GAP = 6 -- gap between columns
local BONUS_W = 60 -- row bonus column
local ROW_H = 40
local ROW_PAD = 6
local HINT_H = 20
local HEADER_Y = 24
local HEADER_H = 22
local LIST_Y = 50
local CELL_Y = 2 -- cell offset inside a 40 px row, so a 36 px cell sits centred
local SCROLLBAR = 6

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

-- One variant cell: its frame, its outline and the initial shown once the variant is found.
type Cell = {
	Frame: Frame,
	Stroke: UIStroke,
	Letter: TextLabel,
}

-- One seed row: the seed config, its four cells (by variant name) and the completion bonus label.
type Row = {
	Seed: any,
	Cells: { [string]: Cell },
	Bonus: TextLabel,
}

local CodexScreen = {}

-- Builds the codex panel inside ctx.Gui and returns the standard screen table.
function CodexScreen.new(ctx: any): Screen
	local Theme = ctx.Theme
	local Components = ctx.Components
	local Strings = ctx.Strings
	local COLORS = Theme.Colors

	-- Guards every snapshot read: the server may send partial state while a profile is loading.
	local function isTable(value: any): boolean
		return typeof(value) == "table"
	end

	local variants: { string } = ctx.Logic.Codex.Variants

	-- How much a finished row is worth, as a whole percent.
	local progression = ctx.Config.Progression
	local bonusValue = 0
	if isTable(progression) and typeof(progression.CodexBonus) == "number" then
		bonusValue = progression.CodexBonus
	end
	local bonusPercent = math.floor(bonusValue * 100 + 0.5)

	-- Outline colour of a discovered cell: the variant's signature colour, stroke for "None".
	local STROKE_HEX = {
		None = COLORS.Stroke,
		Glowing = COLORS.Gold,
		Molten = COLORS.Bad,
		Prismatic = COLORS.Rarity.Epic,
	}

	-- Left edge of variant column `index` (1-based).
	local function columnX(index: number): number
		return NAME_W + GAP + (index - 1) * (CELL_W + GAP)
	end

	local BONUS_X = NAME_W + GAP + #variants * (CELL_W + GAP)

	local root, content = Components.panel({
		Title = Strings.get("Codex.Title"),
		Size = UDim2.fromScale(0.78, 0.9),
		Name = "Codex",
		Parent = ctx.Gui,
		OnClose = function()
			ctx.UI:Close("Codex")
		end,
	})

	-- Hint line: what completing a row is worth.
	Components.label({
		Name = "Hint",
		Text = Strings.get("Codex.Hint", { percent = bonusPercent }),
		Size = UDim2.new(1, 0, 0, HINT_H),
		Position = UDim2.fromOffset(0, 0),
		TextSize = 15,
		Color = COLORS.Muted,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})

	-- Header row: variant names over their columns; the name and bonus columns stay unlabelled.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Position = UDim2.fromOffset(0, HEADER_Y)
	header.Size = UDim2.new(1, 0, 0, HEADER_H)

	for index, variant in variants do
		local mutationKey = "Mutation." .. variant
		Components.label({
			Name = "Header_" .. variant,
			Text = Strings.get(mutationKey),
			Size = UDim2.fromOffset(CELL_W, HEADER_H),
			Position = UDim2.fromOffset(columnX(index), 0),
			TextSize = 14,
			Color = COLORS.Muted,
			Parent = header,
		})
	end

	header.Parent = content

	-- Scrolling body, one row per seed.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Seeds"
	scroll.Position = UDim2.fromOffset(0, LIST_Y)
	scroll.Size = UDim2.new(1, 0, 1, -LIST_Y)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = SCROLLBAR
	scroll.ScrollBarImageColor3 = Theme.color(COLORS.Muted)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, ROW_PAD)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local rows: { Row } = {}

	-- Builds one seed row: name, one cell per variant and the completion bonus label.
	local function buildRow(seed: any): Row
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = "Row_" .. tostring(seed.Id)
		rowFrame.BackgroundTransparency = 1
		rowFrame.BorderSizePixel = 0
		rowFrame.Size = UDim2.new(1, -SCROLLBAR - 4, 0, ROW_H)
		rowFrame.LayoutOrder = if typeof(seed.Tier) == "number" then seed.Tier else 0

		local seedKey = "Seed." .. tostring(seed.Id)
		Components.label({
			Name = "Name",
			Text = Strings.get(seedKey),
			Size = UDim2.fromOffset(NAME_W, ROW_H),
			Position = UDim2.fromOffset(0, 0),
			TextSize = 15,
			Color = COLORS.Text,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = rowFrame,
		})

		local cells: { [string]: Cell } = {}
		for index, variant in variants do
			local frame = Instance.new("Frame")
			frame.Name = "Cell_" .. variant
			frame.BorderSizePixel = 0
			frame.Position = UDim2.fromOffset(columnX(index), CELL_Y)
			frame.Size = UDim2.fromOffset(CELL_W, CELL_H)
			frame.BackgroundColor3 = Theme.color(COLORS.Bg) -- dark silhouette until found

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = frame

			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Thickness = 2
			stroke.Color = Theme.color(COLORS.Stroke)
			stroke.Parent = frame

			-- Variant initial ("G", "M", "P"); hidden for "None" and for undiscovered cells.
			local letter = Components.label({
				Name = "Letter",
				Text = if variant == "None" then "" else string.sub(variant, 1, 1),
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0, 0),
				TextSize = 18,
				Color = COLORS.Bg,
				Parent = frame,
			})
			letter.Visible = false

			frame.Parent = rowFrame
			cells[variant] = { Frame = frame, Stroke = stroke, Letter = letter }
		end

		local bonus = Components.label({
			Name = "Bonus",
			Text = "",
			Size = UDim2.fromOffset(BONUS_W, ROW_H),
			Position = UDim2.fromOffset(BONUS_X, 0),
			TextSize = 15,
			Color = COLORS.Good,
			XAlignment = Enum.TextXAlignment.Right,
			Parent = rowFrame,
		})

		rowFrame.Parent = scroll
		return { Seed = seed, Cells = cells, Bonus = bonus }
	end

	local seeds = ctx.Config.Seeds
	if isTable(seeds) then
		for _, seed in seeds do
			if isTable(seed) then
				table.insert(rows, buildRow(seed))
			end
		end
	end

	scroll.Parent = content

	-- Repaints every row from a snapshot; never rebuilds and never closes the panel.
	local function refresh(snapshot: any)
		local state = if isTable(snapshot) then snapshot else {}
		local codex = if isTable(state.Codex) then state.Codex else {}
		local rowBonusText = Strings.get("Codex.RowBonus", { percent = bonusPercent })

		for _, row in rows do
			local seed = row.Seed
			local entry = codex[seed.Id]
			local found = if isTable(entry) then entry else {}
			local colorHex = if typeof(seed.ColorHex) == "string" then seed.ColorHex else COLORS.PanelLight
			local crystalColor = Theme.color(colorHex)

			for _, variant in variants do
				local cell = row.Cells[variant]
				if cell == nil then
					continue
				end

				if found[variant] == true then
					cell.Frame.BackgroundColor3 = crystalColor
					local strokeHex = STROKE_HEX[variant]
					cell.Stroke.Color = Theme.color(if typeof(strokeHex) == "string" then strokeHex else COLORS.Stroke)
					cell.Letter.Visible = variant ~= "None"
				else
					cell.Frame.BackgroundColor3 = Theme.color(COLORS.Bg)
					cell.Stroke.Color = Theme.color(COLORS.Stroke)
					cell.Letter.Visible = false
				end
			end

			row.Bonus.Text = if ctx.Logic.Codex.isComplete(codex, seed.Id) then rowBonusText else ""
		end
	end

	local screen: Screen = {
		Root = root,
		Open = function(_args: any?)
			refresh(ctx.State:Get())
			root.Visible = true
		end,
		Close = function()
			root.Visible = false
		end,
		Update = function(snapshot: any)
			refresh(snapshot)
		end,
		IsOpen = function(): boolean
			return root.Visible
		end,
	}

	-- Everything starts as an undiscovered silhouette until the first snapshot arrives.
	refresh(nil)

	return screen
end

return CodexScreen
