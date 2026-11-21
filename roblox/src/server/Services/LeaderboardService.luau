--!strict
-- The global weekly "Biggest Crystal This Week" leaderboard and its board in the hub.
-- Writes: a shatter that beats the player's weekly best is queued; every LeaderboardFlushSeconds the queue is
-- written to the OrderedDataStore BiggestCrystal_<WeekId> (value = carats × 100, keeping the larger value).
-- Reads: every LeaderboardRefreshSeconds the top rows are read and written into the board's SurfaceGui text,
-- which replicates to everyone. Every DataStore and UserService call is wrapped in pcall.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.Game)
local WeekId = require(Shared.Logic.WeekId)
local Format = require(Shared.Logic.Format)
local Strings = require(Shared.Strings.Strings)

local LeaderboardService = {}

local IS_STUDIO = RunService:IsStudio()

-- Skip a write while either budget is at or below this (ordered UpdateAsync uses a read and a write).
-- Reads aren't budget-checked: the docs say the OrderedList budget reads 0 (Decision 4).
local MIN_BUDGET = 2
local SHUTDOWN_FLUSH_SECONDS = 10

-- Board layout (studs and canvas pixels).
local BOARD_SIZE = Vector3.new(16, 10, 0.5)
local BOARD_RADIUS = 34 -- inside the hub rim (40), between the paths to plots 1 and 2
local BOARD_ANGLE = math.rad(30)
local BOARD_BOTTOM = 2.2 -- studs above the hub floor (top at y = 0.2)
local SPAWN_POSITION = Vector3.new(0, 0, 22) -- MapService's HubSpawn; the board faces it
local PIXELS_PER_STUD = 50
local TITLE_HEIGHT = 70
local ROW_HEIGHT = 40

-- pending[weekId][userId] = best value (carats × 100) waiting to be written.
local pending: { [string]: { [number]: number } } = {}
local flushing = false
local rowLabels: { TextLabel } = {}
local nameCache: { [number]: string } = {} -- userId -> DisplayName, kept for the server's lifetime

local function storeFor(weekId: string): OrderedDataStore
	return DataStoreService:GetOrderedDataStore(GameConfig.LeaderboardStorePrefix .. weekId)
end

local function writeBudgetOk(): boolean
	return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedWrite) > MIN_BUDGET
		and DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedRead) > MIN_BUDGET
end

-- Queues a weekly-best candidate. Only for real players (UserId > 0, not Studio test players) and never for
-- instant-grown crystals. The week is the one in which the crystal was shattered.
function LeaderboardService:Submit(player: Player, carats: number, instantGrown: boolean?)
	if instantGrown == true or player.UserId <= 0 then
		return
	end
	local value = math.floor(carats * 100 + 1e-6)
	if value <= 0 then
		return
	end
	local week = WeekId.fromUnix(os.time())
	local queue = pending[week]
	if queue == nil then
		queue = {}
		pending[week] = queue
	end
	local queued = queue[player.UserId]
	if queued == nil or value > queued then
		queue[player.UserId] = value
	end
end

-- Puts a value back in the queue after a failed or skipped write, keeping the larger one.
local function requeue(week: string, userId: number, value: number)
	local queue = pending[week]
	if queue == nil then
		queue = {}
		pending[week] = queue
	end
	local queued = queue[userId]
	if queued == nil or value > queued then
		queue[userId] = value
	end
end

-- Writes everything queued. Entries are taken out of the queue before each call, so new submissions made
-- while a call yields are kept; anything that fails or is skipped for budget goes back for the next cycle.
local function flush()
	if flushing then
		return
	end
	flushing = true
	local work = pending
	pending = {}
	for week, queue in work do
		local store = storeFor(week)
		for userId, value in queue do
			if not writeBudgetOk() then
				requeue(week, userId, value)
				continue
			end
			local ok, err = pcall(function()
				store:UpdateAsync(tostring(userId), function(old: any): number?
					if type(old) == "number" and old >= value then
						return nil -- keep the larger stored value; nil cancels the write
					end
					return value
				end)
			end)
			if not ok then
				requeue(week, userId, value)
				if IS_STUDIO then
					warn("[Leaderboard] write failed for " .. userId .. ": " .. tostring(err))
				end
			end
		end
	end
	flushing = false
end

-- DisplayNames for these user IDs, from the cache or one UserService call. Failed lookups aren't cached,
-- so they are retried on the next refresh.
local function resolveNames(userIds: { number })
	local missing = {}
	for _, userId in userIds do
		if nameCache[userId] == nil then
			local player = Players:GetPlayerByUserId(userId)
			if player ~= nil then
				nameCache[userId] = player.DisplayName
			else
				table.insert(missing, userId)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		-- Results can come back in any order and leave out invalid IDs, so match by Id.
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" and type(info.DisplayName) == "string" then
				nameCache[info.Id] = info.DisplayName
			end
		end
	elseif IS_STUDIO then
		warn("[Leaderboard] name lookup failed: " .. tostring(infos))
	end
end

local function rowText(rank: number, name: string?, value: number?): string
	if name == nil or value == nil then
		return ("#%d  %s"):format(rank, Strings.get("Board.Empty"))
	end
	return ("#%d  %s  %s"):format(rank, name, Format.carats(value / 100))
end

-- Reads the current week's top rows and writes them onto the board. A failed read keeps the last content.
local function refresh()
	local ok, page = pcall(function()
		local pages = storeFor(WeekId.fromUnix(os.time())):GetSortedAsync(false, GameConfig.LeaderboardRows)
		return pages:GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		if IS_STUDIO then
			warn("[Leaderboard] read failed: " .. tostring(page))
		end
		return
	end

	local entries: { { userId: number, value: number } } = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId ~= nil and type(item.value) == "number" then
			table.insert(entries, { userId = userId, value = item.value })
		end
	end
	local ids = {}
	for _, entry in entries do
		table.insert(ids, entry.userId)
	end
	resolveNames(ids)

	for rank, label in rowLabels do
		local entry = entries[rank]
		if entry == nil then
			label.Text = rowText(rank, nil, nil)
		else
			label.Text = rowText(rank, nameCache[entry.userId] or "…", entry.value)
		end
	end
	if IS_STUDIO then
		print(("[Leaderboard] board refreshed: %d entries"):format(#entries))
	end
end

local function makeLabel(parent: Instance, name: string, y: number, height: number, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(30, y)
	label.Size = UDim2.new(1, -60, 0, height)
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = Color3.fromRGB(235, 240, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end

-- The 16 × 10-stud board inside the hub, its front facing the spawn pad. Text ignores scene lighting
-- (LightInfluence 0), so it stays readable at every cave brightness level.
local function buildBoard()
	local map = workspace:FindFirstChild("Map")
	local hub = if map ~= nil then map:FindFirstChild("Hub") else nil
	assert(hub ~= nil, "[LeaderboardService] workspace.Map.Hub missing: MapService must Init first")
	local position = Vector3.new(
		math.sin(BOARD_ANGLE) * BOARD_RADIUS,
		BOARD_BOTTOM + BOARD_SIZE.Y / 2,
		math.cos(BOARD_ANGLE) * BOARD_RADIUS
	)

	local board = Instance.new("Part")
	board.Name = "LeaderboardBoard"
	board.Anchored = true
	board.Size = BOARD_SIZE
	board.CFrame = CFrame.lookAt(position, Vector3.new(SPAWN_POSITION.X, position.Y, SPAWN_POSITION.Z))
	board.Material = Enum.Material.SmoothPlastic
	board.Color = Color3.fromRGB(28, 30, 48)
	board.TopSurface = Enum.SurfaceType.Smooth
	board.BottomSurface = Enum.SurfaceType.Smooth

	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Parent = board

	local title = makeLabel(gui, "Title", 14, TITLE_HEIGHT - 14, 44)
	title.Text = Strings.get("Board.Title")
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextColor3 = Color3.fromRGB(255, 215, 120)

	for rank = 1, GameConfig.LeaderboardRows do
		local row = makeLabel(gui, "Row_" .. rank, TITLE_HEIGHT + (rank - 1) * ROW_HEIGHT, ROW_HEIGHT, 30)
		row.Text = rowText(rank, nil, nil)
		rowLabels[rank] = row
	end

	board.Parent = hub
end

function LeaderboardService:Init()
	-- MapService:Init has already built workspace.Map (Main.server order); must not yield.
	buildBoard()
end

function LeaderboardService:Start()
	task.spawn(function()
		while true do
			task.wait(GameConfig.LeaderboardFlushSeconds)
			flush()
		end
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(GameConfig.LeaderboardRefreshSeconds)
		end
	end)

	-- On shutdown, write what's queued, for at most SHUTDOWN_FLUSH_SECONDS.
	game:BindToClose(function()
		local done = false
		task.spawn(function()
			flushing = false -- a flush cut off by shutdown mustn't block this one
			flush()
			done = true
		end)
		local started = os.clock()
		while not done and os.clock() - started < SHUTDOWN_FLUSH_SECONDS do
			task.wait(0.1)
		end
	end)
end

return LeaderboardService
