-- Format.spec.luau - unit tests for the pure number/text formatting helpers.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Format = require("../src/shared/Logic/Format")

return function(test)
	test("compact: below 1000 is an integer string", function()
		expect(Format.compact(0)):toBe("0")
		expect(Format.compact(999)):toBe("999")
		expect(Format.compact(1)):toBe("1")
		expect(Format.compact(12.7)):toBe("12")
		expect(Format.compact(999.99)):toBe("999")
	end)

	test("compact: thousands with K suffix", function()
		expect(Format.compact(1000)):toBe("1K")
		expect(Format.compact(12400)):toBe("12.4K")
		expect(Format.compact(999999)):toBe("999.9K")
	end)

	test("compact: truncates instead of rounding", function()
		expect(Format.compact(12499)):toBe("12.4K")
		expect(Format.compact(1999)):toBe("1.9K")
	end)

	test("compact: millions, billions and trillions", function()
		expect(Format.compact(3100000)):toBe("3.1M")
		expect(Format.compact(2.5e9)):toBe("2.5B")
		expect(Format.compact(1e12)):toBe("1T")
		expect(Format.compact(4.56e15)):toBe("4560T")
	end)

	test("compact: negatives are formatted by absolute value", function()
		expect(Format.compact(-12400)):toBe("-12.4K")
		expect(Format.compact(-999)):toBe("-999")
		expect(Format.compact(-1000)):toBe("-1K")
	end)

	test("compact: never shows more than the value holds", function()
		for _, value in { 1000, 1500, 12499, 999999, 2500000, 1.2345e9 } do
			local text = Format.compact(value)
			local numberPart = string.match(text, "^[%d%.]+") or "0"
			local suffix = string.sub(text, #numberPart + 1)
			local multiplier = ({ K = 1e3, M = 1e6, B = 1e9, T = 1e12 })[suffix] or 1
			expect(tonumber(numberPart) * multiplier <= value):toBeTruthy()
		end
	end)

	test("carats: one rounded decimal with ct suffix", function()
		expect(Format.carats(14.234)):toBe("14.2 ct")
		expect(Format.carats(1)):toBe("1.0 ct")
		expect(Format.carats(0.05)):toBe("0.1 ct")
		expect(Format.carats(0)):toBe("0.0 ct")
		expect(Format.carats(2.5)):toBe("2.5 ct")
		expect(Format.carats(9.96)):toBe("10.0 ct")
	end)

	test("interpolate: replaces known names", function()
		expect(Format.interpolate("+{coins} coins", { coins = "12.4K" })):toBe("+12.4K coins")
		expect(Format.interpolate("{a}{b}", { a = 1, b = 2 })):toBe("12")
		expect(Format.interpolate("x={value}", { value = 3.5 })):toBe("x=3.5")
	end)

	test("interpolate: unknown or missing params are left unchanged", function()
		expect(Format.interpolate("{a}{b}", { a = 1 })):toBe("1{b}")
		expect(Format.interpolate("no placeholders", { a = 1 })):toBe("no placeholders")
	end)

	test("interpolate: nil params returns the template unchanged", function()
		expect(Format.interpolate("+{coins} coins")):toBe("+{coins} coins")
		expect(Format.interpolate("+{coins} coins", nil)):toBe("+{coins} coins")
	end)

	test("interpolate: placeholder names may contain underscores", function()
		expect(Format.interpolate("{max_coins}!", { max_coins = 5 })):toBe("5!")
	end)

	test("countdown: rounds up, pads seconds, adds hours only when needed", function()
		expect(Format.countdown(20)):toBe("0:20")
		expect(Format.countdown(17.2)):toBe("0:18")
		expect(Format.countdown(0.01)):toBe("0:01")
		expect(Format.countdown(0)):toBe("0:00")
		expect(Format.countdown(-5)):toBe("0:00")
		expect(Format.countdown(62)):toBe("1:02")
		expect(Format.countdown(3599)):toBe("59:59")
		expect(Format.countdown(3600)):toBe("1:00:00")
		expect(Format.countdown(3725)):toBe("1:02:05")
		expect(Format.countdown(28800)):toBe("8:00:00")
	end)

	test("Format module contains no require", function()
		local source = fs.readFile("src/shared/Logic/Format.luau")
		expect(string.find(source, "require", 1, true)):toBeNil()
	end)

	test("tidySpaces: an empty parameter leaves no double space", function()
		local text = Format.interpolate("New in Codex: {mutation} {seed}", { mutation = "", seed = "Quartz" })
		expect(Format.tidySpaces(text)):toBe("New in Codex: Quartz")
		expect(Format.tidySpaces("  a   b  ")):toBe("a b")
		expect(Format.tidySpaces("Player1 found a Colossal Prismatic Quartz!")):toBe(
			"Player1 found a Colossal Prismatic Quartz!"
		)
	end)
end
