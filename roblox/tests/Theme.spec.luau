-- Theme.spec.luau - unit tests for the shared UI theme table and the source contracts its consumers rely on.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Theme = require("../src/client/UI/Theme")
local Seeds = require("../src/shared/Config/Seeds")

-- Parses a hex string and asserts the three channels are 0..255 integers.
local function expectChannels(hex: string)
	local red, green, blue = Theme.rgb(hex)
	for _, channel in { red, green, blue } do
		expect(type(channel)):toBe("number")
		expect(channel >= 0 and channel <= 255):toBeTruthy()
		expect(channel % 1):toBe(0)
	end
	return red, green, blue
end

return function(test)
	test("rgb: hex strings parse to 0..255 channels", function()
		local r, g, b = Theme.rgb("#FFFFFF")
		expect(r):toBe(255)
		expect(g):toBe(255)
		expect(b):toBe(255)

		local br, bg, bb = Theme.rgb("14122b")
		expect(br):toBe(20)
		expect(bg):toBe(18)
		expect(bb):toBe(43)
	end)

	test("rgb: rejecting malformed hex strings errors", function()
		expect(pcall(Theme.rgb, "#FFF")):toBe(false)
		expect(pcall(Theme.rgb, "#GGGGGG")):toBe(false)
		expect(pcall(Theme.rgb, "")):toBe(false)
	end)

	test("colors: every palette entry parses", function()
		local checked = 0
		for name, value in Theme.Colors do
			if name == "Rarity" then
				for _, rarityHex in value do
					expectChannels(rarityHex)
					checked += 1
				end
			else
				expectChannels(value)
				checked += 1
			end
		end
		-- 10 flat colours + 5 rarity colours.
		expect(checked):toBe(15)
	end)

	test("colors: rarity palette covers every seed rarity", function()
		local seen = {}
		for _, seed in Seeds do
			local hex = Theme.Colors.Rarity[seed.Rarity]
			expect(hex).never:toBeNil()
			expectChannels(hex)
			seen[seed.Rarity] = true
		end
		expect(seen.Common):toBe(true)
		expect(seen.Legendary):toBe(true)
	end)

	test("layout: touch target and corner constants", function()
		expect(Theme.MinTouch):toBe(48)
		expect(Theme.Corner):toBe(12)
	end)

	test("source: UI modules keep their contract", function()
		local components = fs.readFile("src/client/UI/Components.luau")
		expect(string.find(components, "UISizeConstraint", 1, true)):toBeTruthy()
		expect(string.find(components, "Theme.MinTouch", 1, true)):toBeTruthy()
		expect(string.find(components, "FireServer", 1, true)):toBeNil()
		-- Font.fromEnum returns a Font datatype, which only FontFace accepts (.Font takes an Enum.Font).
		expect(string.find(components, "%.Font%s*=")):toBeNil()

		local theme = fs.readFile("src/client/UI/Theme.luau")
		expect(string.find(theme, "require%s*[%(\"']")):toBeNil()
	end)
end
