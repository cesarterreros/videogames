-- Screens.spec.luau - source checks for the client UI: every literal string key exists in en.luau, and each
-- screen reaches only the remotes its row of the batch 4 plan allows (acceptance criteria, tasks 4-9).

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local en = require("../src/shared/Strings/en")

local UI_DIR = "src/client/UI"
local SCREENS_DIR = UI_DIR .. "/Screens"

-- Remotes each screen may use (looked up as ctx.Remotes:WaitForChild("Name")). Screens not listed may use none.
local ALLOWED: { [string]: { [string]: boolean } } = {
	Hud = { ShatterAll = true, SetSetting = true },
	SeedPicker = { Plant = true },
	Shop = { BuySeed = true },
	Upgrades = { BuyUpgrade = true },
	Daily = { ClaimDaily = true },
	Goals = { ClaimGoal = true },
}

-- Every .luau file under a directory (recursive), as paths.
local function luauFiles(dir: string, out: { string }?): { string }
	local result = out or {}
	if not fs.isDir(dir) then
		return result
	end
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			luauFiles(path, result)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(result, path)
		end
	end
	return result
end

return function(test)
	test("UI: every literal Strings.get / Strings.message key exists in en.luau", function()
		local missing = {}
		for _, path in luauFiles(UI_DIR) do
			local source = fs.readFile(path)
			for _, fn in { "get", "message" } do
				for key in string.gmatch(source, "Strings%." .. fn .. '%(%s*"([^"]+)"') do
					if en[key] == nil then
						table.insert(missing, path .. ": " .. key)
					end
				end
			end
		end
		expect(table.concat(missing, ", ")):toBe("")
	end)

	test("UI: screens use only their allowed remotes, looked up by literal name", function()
		local problems = {}
		for _, path in luauFiles(SCREENS_DIR) do
			local source = fs.readFile(path)
			local screen = string.match(path, "([%w_]+)%.luau$") or path
			local allowed = ALLOWED[screen] or {}
			for name in string.gmatch(source, 'Remotes:WaitForChild%(%s*"([%w_]+)"') do
				if not allowed[name] then
					table.insert(problems, screen .. " uses " .. name)
				end
			end
			-- Any other way of reaching a remote (indexing, FindFirstChild, InvokeServer) is not allowed.
			if string.find(source, "Remotes%.[%a_]") or string.find(source, "Remotes:FindFirstChild") then
				table.insert(problems, screen .. ' reaches a remote without WaitForChild("Name")')
			end
			if string.find(source, "InvokeServer", 1, true) then
				table.insert(problems, screen .. " calls InvokeServer")
			end
			local fires = select(2, string.gsub(source, ":FireServer%(", ""))
			if fires > 0 and next(allowed) == nil then
				table.insert(problems, screen .. " fires a remote but may use none")
			end
		end
		expect(table.concat(problems, ", ")):toBe("")
	end)

	test(
		'UI: screen modules don\'t require server code or call game:GetService("ReplicatedStorage") for config',
		function()
			local problems = {}
			for _, path in luauFiles(SCREENS_DIR) do
				local source = fs.readFile(path)
				if string.find(source, "ServerScriptService", 1, true) then
					table.insert(problems, path .. " mentions ServerScriptService")
				end
				-- Screens get config, logic and strings through ctx, never by requiring them.
				if string.find(source, "require%s*[%(\"']") then
					table.insert(problems, path .. " calls require")
				end
			end
			expect(table.concat(problems, ", ")):toBe("")
		end
	)

	test('src: typeof is compared with "Instance" (capital I); "instance" never matches', function()
		local problems = {}
		for _, dir in { "src/client", "src/shared", "src/server/Services" } do
			for _, path in luauFiles(dir) do
				local source = fs.readFile(path)
				if string.find(source, 'typeof%b()%s*[=~]=%s*"instance"') then
					table.insert(problems, path)
				end
			end
		end
		expect(table.concat(problems, ", ")):toBe("")
	end)
end
