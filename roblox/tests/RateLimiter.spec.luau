local expect = require("./lib/expect")
local RateLimiter = require("../src/shared/Logic/RateLimiter")

return function(test)
	test("RateLimiter: allows a burst of 12, then refuses", function()
		local limiter = RateLimiter.new(8, 12)
		for _ = 1, 12 do
			expect(limiter:allow("p", 100)):toBe(true)
		end
		expect(limiter:allow("p", 100)):toBe(false)
	end)

	test("RateLimiter: refills at 8 per second", function()
		local limiter = RateLimiter.new(8, 12)
		for _ = 1, 12 do
			limiter:allow("p", 0)
		end
		-- 0.5 s later: 4 tokens back.
		for _ = 1, 4 do
			expect(limiter:allow("p", 0.5)):toBe(true)
		end
		expect(limiter:allow("p", 0.5)):toBe(false)
	end)

	test("RateLimiter: refill never exceeds the burst size", function()
		local limiter = RateLimiter.new(8, 12)
		limiter:allow("p", 0)
		local allowed = 0
		for _ = 1, 20 do
			if limiter:allow("p", 1000) then
				allowed += 1
			end
		end
		expect(allowed):toBe(12)
	end)

	test("RateLimiter: keys are independent and forget resets a key", function()
		local limiter = RateLimiter.new(1, 1)
		expect(limiter:allow("a", 0)):toBe(true)
		expect(limiter:allow("a", 0)):toBe(false)
		expect(limiter:allow("b", 0)):toBe(true)
		limiter:forget("a")
		expect(limiter:allow("a", 0)):toBe(true)
	end)

	test("RateLimiter: a clock going backwards adds no tokens", function()
		local limiter = RateLimiter.new(8, 2)
		limiter:allow("p", 10)
		limiter:allow("p", 10)
		expect(limiter:allow("p", 5)):toBe(false)
	end)
end
