-- Graphics.spec.luau - unit tests for the pure graphics quality profiles.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local Graphics = require("../src/shared/Config/Graphics")

local PROFILE_NAMES = { "Full", "Low" }

return function(test)
	test("profiles: both present, with the four fields and the right types", function()
		for _, name in PROFILE_NAMES do
			local profile = Graphics.Profiles[name]
			expect(type(profile)):toBe("table")
			expect(type(profile.LightsMinTier)):toBe("number")
			expect(type(profile.MutationLights)):toBe("boolean")
			expect(type(profile.ParticleRate)):toBe("number")
			expect(type(profile.GlassShell)):toBe("boolean")
		end
	end)

	test("profiles: LightsMinTier is a whole tier in 1..10 and Low glows no earlier than Full", function()
		for _, name in PROFILE_NAMES do
			local tier = Graphics.Profiles[name].LightsMinTier
			expect(tier % 1):toBe(0)
			expect(tier >= 1):toBeTruthy()
			expect(tier <= 10):toBeTruthy()
		end
		expect(Graphics.Profiles.Low.LightsMinTier >= Graphics.Profiles.Full.LightsMinTier):toBeTruthy()
	end)

	test("profiles: ParticleRate is above 0 and at most 1", function()
		for _, name in PROFILE_NAMES do
			local rate = Graphics.Profiles[name].ParticleRate
			expect(rate > 0):toBeTruthy()
			expect(rate <= 1):toBeTruthy()
		end
	end)

	test("profileName: Automatic and levels 4..10 keep Full, levels 1..3 take Low", function()
		expect(Graphics.profileName(0)):toBe("Full")
		expect(Graphics.profileName(1)):toBe("Low")
		expect(Graphics.profileName(3)):toBe("Low")
		expect(Graphics.profileName(4)):toBe("Full")
		expect(Graphics.profileName(10)):toBe("Full")
		expect(Graphics.profileName("x")):toBe("Full")
		expect(Graphics.profileName(0 / 0)):toBe("Full")
		expect(Graphics.profileName(nil)):toBe("Full")
	end)

	test("profile: returns the matching profile table", function()
		expect(Graphics.profile(2)):toBe(Graphics.Profiles.Low)
		expect(Graphics.profile(0)):toBe(Graphics.Profiles.Full)
		expect(Graphics.profile(10)):toBe(Graphics.Profiles.Full)
	end)

	test("Graphics config contains no require", function()
		local source = fs.readFile("src/shared/Config/Graphics.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
