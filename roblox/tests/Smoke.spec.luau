-- Smoke.spec.luau - sanity checks for the test runner itself.

local expect = require("./lib/expect")

return function(test)
	test("1 + 1 == 2", function()
		expect(1 + 1):toBe(2)
	end)

	test("deep table equality", function()
		local actual = { a = 1, b = { c = "x", d = true } }
		local expected = { a = 1, b = { c = "x", d = true } }
		expect(actual):toEqual(expected)
	end)

	test("never.toBe", function()
		expect(1).never:toBe(2)
	end)
end
