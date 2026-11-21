-- Goals.spec.luau - unit tests for the pure daily-goal helpers, driven by seeded rng stubs.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Goals = require("../src/shared/Logic/Goals")

-- The shipping goal pool, copied from Config/Goals so this spec stands alone.
local POOL = {
	{ Id = "Shatter20", Target = 20 },
	{ Id = "PlantUncommon5", Target = 5 },
	{ Id = "FindMutation", Target = 1 },
	{ Id = "Earn5000", Target = 5000 },
	{ Id = "BuyUpgrade", Target = 1 },
	{ Id = "ShatterBig", Target = 1 },
}

local TODAY = "2026-11-21"
local TOMORROW = "2026-11-22"

-- xorshift32: a tiny deterministic PRNG so the suite always draws the same goals.
local function makeRng(seed: number): () -> number
	local state = seed % 4294967296
	if state == 0 then
		state = 2463534242
	end
	return function(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / 4294967296
	end
end

-- A stub rng that always returns the same value.
local function constantRng(value: number): () -> number
	return function(): number
		return value
	end
end

-- An empty board, so every test starts from a known date.
local function emptyBoard()
	return { Date = "", Goals = {}, BonusClaimed = false }
end

-- A board holding three unclaimed goals, for the track and canClaim cases.
local function threeGoals()
	return {
		Date = TODAY,
		Goals = {
			{ Id = "Shatter20", Progress = 0, Claimed = false },
			{ Id = "Earn5000", Progress = 0, Claimed = false },
			{ Id = "FindMutation", Progress = 0, Claimed = false },
		},
		BonusClaimed = false,
	}
end

-- True when every goal Id is unique and exists in `pool`.
local function distinctAndKnown(goals, pool): boolean
	local seen = {}
	for _, goal in goals do
		if seen[goal.Id] then
			return false
		end
		seen[goal.Id] = true
		local known = false
		for _, entry in pool do
			if entry.Id == goal.Id then
				known = true
				break
			end
		end
		if not known then
			return false
		end
	end
	return true
end

-- The pool flattened to one string, so a test can prove ensureToday left it untouched.
local function fingerprint(pool): string
	local parts = {}
	for _, entry in pool do
		table.insert(parts, entry.Id .. ":" .. tostring(entry.Target))
	end
	return table.concat(parts, ",")
end

-- How many goals still carry a non-zero progress or a claimed flag.
local function dirtyCount(goals): number
	local dirty = 0
	for _, goal in goals do
		if goal.Progress ~= 0 or goal.Claimed then
			dirty += 1
		end
	end
	return dirty
end

-- How many drawn goal tables are actually entries of the pool (always expected to be zero).
local function sharedCount(goals, pool): number
	local shared = 0
	for _, goal in goals do
		for _, entry in pool do
			if goal == entry then
				shared += 1
			end
		end
	end
	return shared
end

return function(test)
	test("ensureToday: an empty board is filled with a fresh draw", function()
		local board = emptyBoard()
		local filled, rerolled = Goals.ensureToday(board, TODAY, POOL, 3, makeRng(1))
		expect(rerolled):toBe(true)
		expect(filled):toBe(board)
		expect(board.Date):toBe(TODAY)
		expect(board.BonusClaimed):toBe(false)
		expect(#board.Goals):toBe(3)
		expect(distinctAndKnown(board.Goals, POOL)):toBe(true)
		expect(dirtyCount(board.Goals)):toBe(0)
		expect(sharedCount(board.Goals, POOL)):toBe(0)
	end)

	test("ensureToday: 200 different seeds always give 3 distinct pool goals", function()
		local bad = 0
		for seed = 1, 200 do
			local board = emptyBoard()
			Goals.ensureToday(board, TODAY, POOL, 3, makeRng(seed))
			if #board.Goals ~= 3 or not distinctAndKnown(board.Goals, POOL) then
				bad += 1
			end
		end
		expect(bad):toBe(0)
	end)

	test("ensureToday: the extreme rng draws still give 3 distinct pool goals", function()
		local lowBoard = emptyBoard()
		Goals.ensureToday(lowBoard, TODAY, POOL, 3, constantRng(0))
		expect(#lowBoard.Goals):toBe(3)
		expect(distinctAndKnown(lowBoard.Goals, POOL)):toBe(true)

		local highBoard = emptyBoard()
		Goals.ensureToday(highBoard, TODAY, POOL, 3, constantRng(0.9999999))
		expect(#highBoard.Goals):toBe(3)
		expect(distinctAndKnown(highBoard.Goals, POOL)):toBe(true)
	end)

	test("ensureToday: the same day keeps the board and its progress", function()
		local board = emptyBoard()
		Goals.ensureToday(board, TODAY, POOL, 3, makeRng(1))
		board.Goals[1].Progress = 7
		local goalsBefore = board.Goals
		local firstId = board.Goals[1].Id

		local filled, rerolled = Goals.ensureToday(board, TODAY, POOL, 3, makeRng(2))
		expect(rerolled):toBe(false)
		expect(filled):toBe(board)
		expect(filled.Goals):toBe(goalsBefore)
		expect(board.Goals[1].Progress):toBe(7)
		expect(board.Goals[1].Id):toBe(firstId)
	end)

	test("ensureToday: a new day rerolls every goal and resets the bonus", function()
		local board = emptyBoard()
		Goals.ensureToday(board, TODAY, POOL, 3, makeRng(1))
		board.Goals[1].Progress = 19
		board.Goals[1].Claimed = true
		board.Goals[2].Claimed = true
		board.BonusClaimed = true

		local filled, rerolled = Goals.ensureToday(board, TOMORROW, POOL, 3, makeRng(1))
		expect(rerolled):toBe(true)
		expect(filled):toBe(board)
		expect(board.Date):toBe(TOMORROW)
		expect(board.BonusClaimed):toBe(false)
		expect(#board.Goals):toBe(3)
		expect(dirtyCount(board.Goals)):toBe(0)
		expect(distinctAndKnown(board.Goals, POOL)):toBe(true)
	end)

	test("ensureToday: mutates the given table and leaves the pool untouched", function()
		local before = fingerprint(POOL)
		local board = emptyBoard()
		local filled, rerolled = Goals.ensureToday(board, TODAY, POOL, 3, makeRng(9))
		expect(filled):toBe(board)
		expect(rerolled):toBe(true)
		expect(fingerprint(POOL)):toBe(before)
		expect(#POOL):toBe(6)
	end)

	test("ensureToday: a count above the pool size is clamped to the pool", function()
		local board = emptyBoard()
		Goals.ensureToday(board, TODAY, POOL, 10, makeRng(5))
		expect(#board.Goals):toBe(#POOL)
		expect(distinctAndKnown(board.Goals, POOL)):toBe(true)
	end)

	test("track: adds to the matching goal and reports its index", function()
		local board = threeGoals()
		local changed = Goals.track(board, "Shatter", 1)
		expect(#changed):toBe(1)
		expect(changed[1]):toBe(1)
		expect(board.Goals[1].Progress):toBe(1)
		expect(board.Goals[2].Progress):toBe(0)
		expect(board.Goals[3].Progress):toBe(0)
	end)

	test("track: progress is not capped at the target", function()
		local board = threeGoals()
		local changed = Goals.track(board, "Coins", 6000)
		expect(#changed):toBe(1)
		expect(changed[1]):toBe(2)
		expect(board.Goals[2].Progress):toBe(6000)
	end)

	test("track: events with no matching goal do nothing", function()
		local board = threeGoals()
		expect(#Goals.track(board, "Upgrade", 1)):toBe(0)
		expect(#Goals.track(board, "Bogus", 1)):toBe(0)
		expect(#Goals.track(board, "Shatter", 0)):toBe(0)
		expect(#Goals.track(board, "Shatter", -3)):toBe(0)
		expect(board.Goals[1].Progress):toBe(0)
	end)

	test("track: a claimed goal is left alone", function()
		local board = threeGoals()
		board.Goals[1].Progress = 20
		board.Goals[1].Claimed = true
		local changed = Goals.track(board, "Shatter", 5)
		expect(#changed):toBe(0)
		expect(board.Goals[1].Progress):toBe(20)
	end)

	test("canClaim: the target must be reached exactly or beaten", function()
		local board = threeGoals()
		board.Goals[1].Progress = 19
		expect(Goals.canClaim(board, 1, POOL)):toBe(false)
		board.Goals[1].Progress = 20
		expect(Goals.canClaim(board, 1, POOL)):toBe(true)
		board.Goals[1].Progress = 25
		expect(Goals.canClaim(board, 1, POOL)):toBe(true)
	end)

	test("canClaim: a claimed goal is refused", function()
		local board = threeGoals()
		board.Goals[1].Progress = 30
		board.Goals[1].Claimed = true
		expect(Goals.canClaim(board, 1, POOL)):toBe(false)
	end)

	test("canClaim: missing indexes and unknown Ids are refused", function()
		local board = threeGoals()
		expect(Goals.canClaim(board, 4, POOL)):toBe(false)
		expect(Goals.canClaim(board, 0, POOL)):toBe(false)

		local unknown = threeGoals()
		unknown.Goals[2].Id = "Bogus"
		unknown.Goals[2].Progress = 99999
		expect(Goals.canClaim(unknown, 2, POOL)):toBe(false)
	end)

	test("canClaimBonus: only a fully claimed day pays out", function()
		local board = threeGoals()
		board.Goals[1].Claimed = true
		board.Goals[2].Claimed = true
		expect(Goals.canClaimBonus(board)):toBe(false)

		board.Goals[3].Claimed = true
		expect(Goals.canClaimBonus(board)):toBe(true)

		board.BonusClaimed = true
		expect(Goals.canClaimBonus(board)):toBe(false)
	end)

	test("canClaimBonus: an empty board never pays out", function()
		local board = emptyBoard()
		expect(Goals.canClaimBonus(board)):toBe(false)
	end)

	test("Goals module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/Goals.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
