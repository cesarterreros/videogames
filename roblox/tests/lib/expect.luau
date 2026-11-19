--[[
	expect.luau - tiny assertion library for the Lune unit-test runner.

	Pure module: no requires. Usage:

		local expect = require("./lib/expect")
		expect(1 + 1):toBe(2)
		expect({ a = 1 }):toEqual({ a = 1 })
		expect(function() error("boom") end):toThrow()
		expect(someValue).never:toBe(otherValue)

	Every failing assertion raises an error with `error(msg, 2/3)` so the
	reported message points at the caller's line.
]]

-- Returns a human-readable, non-throwing representation of any value.
local function describe(value)
	local ok, text = pcall(tostring, value)
	return ok and text or ("<a " .. type(value) .. " value>")
end

-- Recursive deep equality: tables compare key-by-key in both directions,
-- everything else falls back to raw `==`.
local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in pairs(a) do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- Builds an assertion object. `invert` flips pass/fail for `.never`.
local function makeAssertions(actual, invert)
	local assertions = {}

	-- Builds the failure text; inverted (`.never`) assertions report a pass as a failure.
	local function failMessage(text: string): string
		if invert then
			return "expected assertion to fail, but it passed (" .. text .. ")"
		end
		return text
	end

	-- Raw equality (==).
	function assertions:toBe(expected)
		if (actual == expected) ~= invert then
			return
		end
		error(failMessage("expected " .. describe(expected) .. ", got " .. describe(actual)), 2)
	end

	-- Deep equality for tables; == for non-tables.
	function assertions:toEqual(expected)
		if deepEqual(actual, expected) ~= invert then
			return
		end
		error(failMessage("expected deep equal to " .. describe(expected) .. ", got " .. describe(actual)), 2)
	end

	-- Numeric proximity within `eps` (default 1e-9).
	function assertions:toBeNear(expected, eps)
		eps = eps or 1e-9
		if (math.abs(actual - expected) <= eps) ~= invert then
			return
		end
		local text = "expected "
			.. describe(actual)
			.. " to be within "
			.. describe(eps)
			.. " of "
			.. describe(expected)
		error(failMessage(text), 2)
	end

	-- Truthiness check (only nil and false are falsy).
	function assertions:toBeTruthy()
		if (not not actual) ~= invert then
			return
		end
		error(failMessage("expected truthy value, got " .. describe(actual)), 2)
	end

	-- Falsiness check (nil or false).
	function assertions:toBeFalsy()
		if (not actual) ~= invert then
			return
		end
		error(failMessage("expected falsy value, got " .. describe(actual)), 2)
	end

	-- Explicit nil check.
	function assertions:toBeNil()
		if (actual == nil) ~= invert then
			return
		end
		error(failMessage("expected nil, got " .. describe(actual)), 2)
	end

	-- `actual` must be a function; passes only when calling it raises.
	function assertions:toThrow()
		if type(actual) ~= "function" then
			error("expected a function, got " .. type(actual), 2)
		end
		local threw = not (pcall(actual))
		if threw ~= invert then
			return
		end
		if threw then
			error("expected function to throw, but it returned normally", 2)
		else
			error("expected function not to throw, but it did", 2)
		end
	end

	return assertions
end

-- `expect(actual)` returns the assertion object plus an inverted `.never` view.
return function(actual)
	local positive = makeAssertions(actual, false)
	positive.never = makeAssertions(actual, true)
	return positive
end
