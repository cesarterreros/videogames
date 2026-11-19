--[[
	run.luau - tiny unit-test runner for Luau code, run with Lune.

	Usage (from the `roblox/` directory):

		lune run tests
		lune run tests/run   -- equivalent (tests/init.luau requires this file via @self)

	Discovers every top-level `tests/*.spec.luau` file (alphabetically), requires
	it, and calls the returned spec function with a `test(name, fn)` callback.
	Prints one line per test and a final summary; exits 1 on any failure.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local TESTS_DIR = "tests"
local SPEC_SUFFIX = ".spec.luau"
local SCRIPT_SUFFIX = ".luau"

-- Collect top-level spec file names (with extension), sorted alphabetically.
local function discoverSpecs(): { string }
	local specs = {}
	for _, name in fs.readDir(TESTS_DIR) do
		-- Ignore directories that happen to end with the spec suffix.
		if name:sub(-#SPEC_SUFFIX) == SPEC_SUFFIX and not fs.isDir(TESTS_DIR .. "/" .. name) then
			table.insert(specs, name)
		end
	end
	table.sort(specs)
	return specs
end

type TestResult = { name: string, ok: boolean, message: string? }

-- Runs a single spec module and returns its results as { name, ok, message } records.
local function runSpec(fileName: string): { TestResult }
	local results: { TestResult } = {}

	-- require() takes the module path without the ".luau" extension: "Smoke.spec".
	local ok, specOrError = pcall(require, "./" .. fileName:sub(1, -#SCRIPT_SUFFIX - 1))
	if not ok then
		-- A module that fails to load counts as a single failed test.
		table.insert(results, { name = fileName .. ": load", ok = false, message = tostring(specOrError) })
		return results
	end
	if type(specOrError) ~= "function" then
		table.insert(results, {
			name = fileName .. ": load",
			ok = false,
			message = "spec module must return a function, got " .. type(specOrError),
		})
		return results
	end

	-- The `test` callback handed to each spec: runs `fn` under pcall.
	local function test(name: string, fn: () -> ())
		local success, err = pcall(fn)
		table.insert(results, {
			name = name,
			ok = success,
			message = if success then nil else tostring(err),
		})
	end

	-- A spec body that errors outside of a `test` call is also a failure.
	local specOk, specErr = pcall(specOrError :: any, test)
	if not specOk then
		table.insert(results, { name = fileName .. ": body", ok = false, message = tostring(specErr) })
	end

	return results
end

local specs = discoverSpecs()

if #specs == 0 then
	print("No spec files found")
	process.exit(1)
end

local passed = 0
local failed = 0

for _, fileName in specs do
	print(fileName)
	for _, result in runSpec(fileName) do
		if result.ok then
			passed += 1
			print("  \u{2713} " .. result.name)
		else
			failed += 1
			print("  \u{2717} " .. result.name .. " \u{2014} " .. tostring(result.message))
		end
	end
end

print(string.format("%d passed, %d failed", passed, failed))

process.exit(if failed > 0 then 1 else 0)
