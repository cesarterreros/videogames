-- CoinFly.spec.luau - unit tests for the pure coin-fly helpers (icon count and coin shares).

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local CoinFly = require("../src/shared/Logic/CoinFly")

-- Sum, smallest and largest entry of a share list.
local function stats(shares: { number }): (number, number, number)
	local sum = 0
	local smallest = math.huge
	local largest = -math.huge
	for _, share in shares do
		sum += share
		smallest = math.min(smallest, share)
		largest = math.max(largest, share)
	end
	return sum, smallest, largest
end

return function(test)
	test("iconCount: no coins or negative coins fly nothing", function()
		expect(CoinFly.iconCount(0)):toBe(0)
		expect(CoinFly.iconCount(-5)):toBe(0)
	end)

	test("iconCount: one coin is the minimum of six icons", function()
		expect(CoinFly.iconCount(1)):toBe(6)
	end)

	test("iconCount: fifteen coins is seven icons", function()
		expect(CoinFly.iconCount(15)):toBe(7)
	end)

	test("iconCount: a million coins is the maximum of twelve icons", function()
		expect(CoinFly.iconCount(1e6)):toBe(12)
	end)

	test("iconCount: never above twelve icons", function()
		for _, coins in { 1, 15, 100, 1e3, 1e6, 1e9, 1e12 } do
			expect(CoinFly.iconCount(coins) <= 12):toBeTruthy()
		end
		expect(CoinFly.iconCount(1e12)):toBe(12)
	end)

	test("split: fifteen coins over seven icons", function()
		local shares = CoinFly.split(15, 7)
		expect(#shares):toBe(7)
		local sum, smallest, largest = stats(shares)
		expect(sum):toBe(15)
		expect(smallest >= 0):toBeTruthy()
		expect(largest - smallest <= 1):toBeTruthy()
		expect(shares[1]):toBe(3)
	end)

	test("split: five coins over twelve icons leaves seven empty", function()
		local shares = CoinFly.split(5, 12)
		expect(#shares):toBe(12)
		local sum, smallest, largest = stats(shares)
		expect(sum):toBe(5)
		expect(smallest):toBe(0)
		expect(largest):toBe(1)
		local zeros = 0
		for _, share in shares do
			if share == 0 then
				zeros += 1
			end
		end
		expect(zeros):toBe(7)
	end)

	test("split: no coins or no icons is empty", function()
		expect(#CoinFly.split(0, 6)):toBe(0)
		expect(#CoinFly.split(10, 0)):toBe(0)
	end)

	test("CoinFly module contains no require", function()
		local source = fs.readFile("src/shared/Logic/CoinFly.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
