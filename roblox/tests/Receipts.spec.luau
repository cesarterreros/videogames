-- Receipts.spec.luau - unit tests for the pure purchase-history helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Receipts = require("../src/shared/Logic/Receipts")

-- Builds the history "p1".."pN" the trimming tests start from.
local function history(count: number): { string }
	local list = {}
	for index = 1, count do
		table.insert(list, "p" .. index)
	end
	return list
end

return function(test)
	test("isProcessed: true for a recorded id, false for an unknown one", function()
		local list = { "p1", "p2" }
		expect(Receipts.isProcessed(list, "p1")):toBe(true)
		expect(Receipts.isProcessed(list, "p2")):toBe(true)
		expect(Receipts.isProcessed(list, "p3")):toBe(false)
	end)

	test("isProcessed: false on an empty history", function()
		expect(Receipts.isProcessed({}, "p1")):toBe(false)
	end)

	test("record: appends the id at the end", function()
		local list = { "p1", "p2" }
		expect(Receipts.record(list, "p3", 10)):toEqual({ "p1", "p2", "p3" })
	end)

	test("record: returns a new list and leaves the input untouched", function()
		local list = { "p1", "p2" }
		local result = Receipts.record(list, "p3", 10)
		expect(#list):toBe(2)
		expect(list):toEqual({ "p1", "p2" })
		expect(#result):toBe(3)
		expect(result).never:toBe(list)
	end)

	test("record: an id already in the list adds no duplicate", function()
		local list = { "p1", "p2" }
		local result = Receipts.record(list, "p2", 10)
		expect(result):toEqual({ "p1", "p2" })
		expect(#list):toBe(2)
		expect(list):toEqual({ "p1", "p2" })
	end)

	test("record: the 101st id drops only the oldest one", function()
		local list = history(100)
		local result = Receipts.record(list, "p101", 100)
		expect(#result):toBe(100)
		expect(result[1]):toBe("p2")
		expect(result[100]):toBe("p101")
		expect(Receipts.isProcessed(result, "p1")):toBe(false)
		expect(Receipts.isProcessed(result, "p101")):toBe(true)
		-- The source list is still the full, unmodified 100 ids.
		expect(#list):toBe(100)
		expect(list[1]):toBe("p1")
	end)

	test("record: a list longer than max is trimmed down to max", function()
		local list = history(50)
		local result = Receipts.record(list, "p51", 10)
		expect(#result):toBe(10)
		expect(result[1]):toBe("p42")
		expect(result[10]):toBe("p51")
		expect(#list):toBe(50)
	end)

	test("record: a max below one still keeps the newest id", function()
		expect(Receipts.record({ "p1", "p2" }, "p3", 0)):toEqual({ "p3" })
		expect(Receipts.record({ "p1", "p2" }, "p3", -5)):toEqual({ "p3" })
	end)

	test("Receipts module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/Receipts.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
