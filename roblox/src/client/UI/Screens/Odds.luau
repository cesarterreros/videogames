--!strict
-- Odds.luau - the odds panel: two side-by-side tables, one for the size bands and one for the mutation
-- bands, plus the "None" remainder. While a Crystal Surge and/or the player's paid Luck Boost is live the
-- mutation chances shown are the player's true odds (the two multiply, capped at x3 like the server roll),
-- in gold with each multiplier appended. The tables are built once in new(); refresh only rewrites texts
-- and colours in place, and it ticks once a second so a surge opening or closing is picked up live.

-- Row layout, in pixels inside each table frame.
local HEADER_H = 24
local ROW_H = 26
local NAME_SCALE = 0.55 -- left column: the band name
local PERCENT_SCALE = 0.45 -- right column: the chance
local NOTE_H = 20

export type Screen = {
	Root: Frame,
	Open: (args: any?) -> (),
	Close: () -> (),
	Update: (snapshot: any) -> (),
	IsOpen: () -> boolean,
}

-- One mutation row: the band name (nil for the "None" remainder) and the percent label it paints.
type MutationRow = {
	Name: string?,
	Percent: TextLabel,
}

local Odds = {}

-- Formats a probability as a percent string without the % sign: whole numbers at 10% and up, one decimal
-- in the 1..10 range, two decimals below that, always with trailing zeros trimmed.
local function pct(p: number): string
	local x = p * 100
	if x ~= x then
		return "0"
	end
	if x >= 10 then
		return string.format("%d", math.floor(x + 0.5))
	elseif x >= 1 then
		local text = string.format("%.1f", x)
		if string.sub(text, -2) == ".0" then
			return string.sub(text, 1, -3)
		end
		return text
	end

	local text = string.format("%.2f", x)
	while string.sub(text, -1) == "0" do
		text = string.sub(text, 1, -2)
	end
	if string.sub(text, -1) == "." then
		text = string.sub(text, 1, -2)
	end
	return text
end

-- Builds the odds panel inside ctx.Gui and returns the standard screen table.
function Odds.new(ctx: any): Screen
	local Theme = ctx.Theme
	local Components = ctx.Components
	local Strings = ctx.Strings
	local COLORS = Theme.Colors

	-- Guards every config read: a partially loaded config must not break the panel.
	local function isTable(value: any): boolean
		return typeof(value) == "table"
	end

	local function num(value: any, fallback: number): number
		if typeof(value) == "number" then
			return value
		end
		return fallback
	end

	local function isArray(value: any): boolean
		return isTable(value) and #value > 0
	end

	local economy = ctx.Config.Economy
	local surgeMinutes = num(if isTable(economy) then economy.SurgeMinutes else nil, 0)
	local surgeMult = num(if isTable(economy) then economy.SurgeMutationMult else nil, 1)

	local root, content = Components.panel({
		Title = Strings.get("Odds.Title"),
		Size = UDim2.fromScale(0.7, 0.86),
		Name = "Odds",
		Parent = ctx.Gui,
		OnClose = function()
			ctx.UI:Close("Odds")
		end,
	})

	-- Builds one table frame and its gold header, returning the frame the rows live in.
	local function buildTable(name: string, headerText: string, xScale: number, xOffset: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Position = UDim2.new(xScale, xOffset, 0, 0)
		frame.Size = UDim2.new(0.5, -6, 1, -24)

		Components.label({
			Name = "Header",
			Text = headerText,
			Size = UDim2.new(1, 0, 0, HEADER_H),
			Position = UDim2.fromOffset(0, 0),
			TextSize = 18,
			Color = COLORS.Gold,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})

		frame.Parent = content
		return frame
	end

	-- One name/percent line at row `index` (0-based) of a table.
	local function buildRow(tableFrame: Frame, nameText: string, index: number): TextLabel
		local y = HEADER_H + index * ROW_H

		Components.label({
			Name = "Name",
			Text = nameText,
			Size = UDim2.new(NAME_SCALE, 0, 0, ROW_H),
			Position = UDim2.fromOffset(0, y),
			TextSize = 16,
			Color = COLORS.Text,
			XAlignment = Enum.TextXAlignment.Left,
			Parent = tableFrame,
		})

		return Components.label({
			Name = "Percent",
			Text = "",
			Size = UDim2.new(PERCENT_SCALE, 0, 0, ROW_H),
			Position = UDim2.new(NAME_SCALE, 0, 0, y),
			TextSize = 16,
			Color = COLORS.Muted,
			XAlignment = Enum.TextXAlignment.Right,
			Parent = tableFrame,
		})
	end

	-- Left table: the four size bands. Their chances never change, so the texts are set once here.
	local sizeTable = buildTable("Sizes", Strings.get("Odds.Sizes"), 0, 0)
	local sizes = ctx.Config.Rolls.Size
	if isArray(sizes) then
		for index, band in sizes do
			if isTable(band) then
				local sizeKey = "Size." .. tostring(band.Name)
				local percent = buildRow(sizeTable, Strings.get(sizeKey), index - 1)
				percent.Text = Strings.get("Odds.Chance", { percent = pct(num(band.Chance, 0)) })
			end
		end
	end

	-- Right table: "None" (the remainder) first, then one row per mutation band.
	local mutationTable = buildTable("Mutations", Strings.get("Odds.Mutations"), 0.5, 6)
	local mutationRows: { MutationRow } = {}

	local nonePercent = buildRow(mutationTable, Strings.get("Mutation.None"), 0)
	table.insert(mutationRows, { Name = nil, Percent = nonePercent })

	local mutations = ctx.Config.Rolls.Mutation
	if isArray(mutations) then
		for index, band in mutations do
			if isTable(band) then
				local name = if typeof(band.Name) == "string" then band.Name else ""
				local mutationKey = "Mutation." .. name
				local percent = buildRow(mutationTable, Strings.get(mutationKey), index)
				table.insert(mutationRows, { Name = name, Percent = percent })
			end
		end
	end

	-- Footnote under both tables: it says the odds are the base ones, or that a boost is live.
	local noteLabel = Components.label({
		Name = "Note",
		Text = Strings.get("Odds.Note"),
		Size = UDim2.new(1, 0, 0, NOTE_H),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		TextSize = 14,
		Color = COLORS.Muted,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})

	-- Rewrites the mutation table and the footnote for the current surge + Luck Boost state; never closes
	-- the panel.
	local function refresh()
		local now = ctx.Now()
		local surgeActive = false
		if typeof(now) == "number" then
			surgeActive = ctx.Logic.Surge.isActive(now, surgeMinutes)
		end

		-- The player's own Luck Boost (from the snapshot) multiplies with the surge, capped like the server roll.
		local snapshot = ctx.State:Get()
		local monetization = if isTable(snapshot) and isTable(snapshot.Monetization) then snapshot.Monetization else {}
		local luckEndsAt = num(monetization.LuckBoostEndsAt, 0)
		local luckConfig = if isTable(ctx.Config.Monetization) then ctx.Config.Monetization.LuckBoost else nil
		local luckMult = if isTable(luckConfig) then num(luckConfig.Mult, 1) else 1
		local maxTotal = if isTable(luckConfig) then num(luckConfig.MaxTotalMult, 1) else 1
		local luckActive = typeof(now) == "number" and now < luckEndsAt
		local mult = 1
		if typeof(now) == "number" then
			mult = ctx.Logic.LuckBoost.chanceMult(now, luckEndsAt, surgeActive, luckMult, surgeMult, maxTotal)
		end
		local boosted = mult > 1
		local parts = {}
		if surgeActive and surgeMult > 1 then
			table.insert(parts, Strings.get("Odds.SurgeBoost", { mult = surgeMult }))
		end
		if luckActive and luckMult > 1 then
			table.insert(parts, Strings.get("Odds.LuckBoost", { mult = luckMult }))
		end
		local boostText: string
		if #parts == 2 then
			-- batch 6: both boosts live, one combined label; "(max)" when the cap cut the product short.
			local bothKey = if mult < surgeMult * luckMult then "Odds.BothBoostMax" else "Odds.BothBoost"
			boostText = Strings.get(bothKey, { mult = mult })
		else
			boostText = table.concat(parts, " ")
		end

		-- "None" is whatever is left once the (surge-scaled) mutation chances are taken out.
		local spent = 0
		if isArray(mutations) then
			for _, band in mutations do
				if isTable(band) then
					spent += num(band.Chance, 0) * mult
				end
			end
		end

		for _, row in mutationRows do
			local chance: number
			if row.Name == nil then
				chance = math.max(0, 1 - spent)
			else
				chance = 0
				if isArray(mutations) then
					for _, band in mutations do
						if isTable(band) and band.Name == row.Name then
							chance = num(band.Chance, 0) * mult
							break
						end
					end
				end
			end

			local text = Strings.get("Odds.Chance", { percent = pct(chance) })
			if boosted and row.Name ~= nil then
				text = text .. " " .. boostText
				row.Percent.TextColor3 = Theme.color(COLORS.Gold)
			else
				row.Percent.TextColor3 = Theme.color(COLORS.Muted)
			end
			row.Percent.Text = text
		end

		-- The footnote explains the base odds, or says these are the boosted ones while a boost is live.
		if boosted then
			noteLabel.Text = Strings.get("Odds.BoostedNote")
			noteLabel.TextColor3 = Theme.color(COLORS.Gold)
		else
			noteLabel.Text = Strings.get("Odds.Note")
			noteLabel.TextColor3 = Theme.color(COLORS.Muted)
		end
	end

	local screen: Screen = {
		Root = root,
		Open = function(_args: any?)
			refresh()
			root.Visible = true
		end,
		Close = function()
			root.Visible = false
		end,
		Update = function(_snapshot: any)
			refresh()
		end,
		IsOpen = function(): boolean
			return root.Visible
		end,
	}

	refresh()

	-- Tick the table once a second while it is open, so a surge starting or ending shows up live.
	task.spawn(function()
		while true do
			task.wait(1)
			if root.Visible then
				refresh()
			end
		end
	end)

	return screen
end

return Odds
