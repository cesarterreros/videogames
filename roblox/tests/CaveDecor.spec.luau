-- CaveDecor.spec.luau - unit tests for the pure cave decoration layout, driven by a seeded PRNG.

local fs = require("@lune/fs")
local expect = require("./lib/expect")
local CaveDecor = require("../src/shared/Logic/CaveDecor")

-- How many different seeds the layout rules are checked against.
local SEEDS = 200

-- xorshift32: a tiny deterministic PRNG so the suite always draws the same caves.
-- (Never math.random or os.time, so failures are reproducible.)
local function makeRng(seed: number): () -> number
	local state = seed % 4294967296
	if state == 0 then
		state = 2463534242
	end
	return function(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / 4294967296
	end
end

-- Ground-plane distance between two layout points.
local function distance(ax: number, az: number, bx: number, bz: number): number
	local dx = ax - bx
	local dz = az - bz
	return math.sqrt(dx * dx + dz * dz)
end

-- Runs the layout for a given seed and returns it, so every test uses the same helper.
local function layoutFor(seed: number)
	return CaveDecor.layout(makeRng(seed))
end

return function(test)
	test("stalagmites: 8..12 per cave for 200 seeds", function()
		local bad = {}
		for seed = 1, SEEDS do
			local count = #layoutFor(seed).Stalagmites
			if count < 8 or count > 12 then
				table.insert(bad, seed .. ": " .. count)
			end
		end
		expect(table.concat(bad, ", ")):toBe("")
	end)

	test("stalagmites: inside the interior bounds x [-30, 30], z [-18, 20]", function()
		local bad = 0
		for seed = 1, SEEDS do
			for _, rock in layoutFor(seed).Stalagmites do
				if rock.X < -30 or rock.X > 30 or rock.Z < -18 or rock.Z > 20 then
					bad += 1
				end
			end
		end
		expect(bad):toBe(0)
	end)

	test("stalagmites: at least 5 studs from every pedestal spot", function()
		local bad = 0
		for seed = 1, SEEDS do
			for _, rock in layoutFor(seed).Stalagmites do
				for _, spot in CaveDecor.PedestalSpots do
					if distance(rock.X, rock.Z, spot[1], spot[2]) < 5 then
						bad += 1
					end
				end
			end
		end
		expect(bad):toBe(0)
	end)

	test("stalagmites: at least 6 studs from the spawn point (-16, -15)", function()
		local bad = 0
		for seed = 1, SEEDS do
			for _, rock in layoutFor(seed).Stalagmites do
				if distance(rock.X, rock.Z, -16, -15) < 6 then
					bad += 1
				end
			end
		end
		expect(bad):toBe(0)
	end)

	test("stalagmites: none in the entrance lane (|x| < 10 and z < -10)", function()
		local bad = 0
		for seed = 1, SEEDS do
			for _, rock in layoutFor(seed).Stalagmites do
				if math.abs(rock.X) < 10 and rock.Z < -10 then
					bad += 1
				end
			end
		end
		expect(bad):toBe(0)
	end)

	test("stalagmites: pairwise at least 4 studs apart, sizes and angles in range", function()
		local tooClose = 0
		local outOfRange = 0
		for seed = 1, SEEDS do
			local rocks = layoutFor(seed).Stalagmites
			for i = 1, #rocks do
				local a = rocks[i]
				if a.Width < 1.5 or a.Width > 3 or a.Height < 3 or a.Height > 7 then
					outOfRange += 1
				end
				if a.Yaw < 0 or a.Yaw >= 360 then
					outOfRange += 1
				end
				if a.Tilt < -5 or a.Tilt > 5 then
					outOfRange += 1
				end
				for j = i + 1, #rocks do
					local b = rocks[j]
					if distance(a.X, a.Z, b.X, b.Z) < 4 then
						tooClose += 1
					end
				end
			end
		end
		expect(tooClose):toBe(0)
		expect(outOfRange):toBe(0)
	end)

	test("clusters: exactly 3, walls Left/Right/Back in that order", function()
		for seed = 1, SEEDS do
			local clusters = layoutFor(seed).Clusters
			expect(#clusters):toBe(3)
			expect(clusters[1].Wall):toBe("Left")
			expect(clusters[2].Wall):toBe("Right")
			expect(clusters[3].Wall):toBe("Back")
		end
	end)

	test("clusters: Along, Y, prism counts, prism sizes and ColorIndex in range", function()
		local bad = {}
		local function note(message: string)
			if #bad < 10 then
				table.insert(bad, message)
			end
		end
		for seed = 1, SEEDS do
			for _, cluster in layoutFor(seed).Clusters do
				-- Side walls run along z, the back wall along x.
				local limit = if cluster.Wall == "Back" then 24 else 16
				if cluster.Along < -limit or cluster.Along > limit then
					note(seed .. " " .. cluster.Wall .. " Along " .. cluster.Along)
				end
				if cluster.Y < 6 or cluster.Y > 11 then
					note(seed .. " " .. cluster.Wall .. " Y " .. cluster.Y)
				end
				if cluster.ColorIndex < 1 or cluster.ColorIndex > 3 or cluster.ColorIndex % 1 ~= 0 then
					note(seed .. " " .. cluster.Wall .. " ColorIndex " .. cluster.ColorIndex)
				end
				local count = #cluster.Prisms
				if count < 3 or count > 4 then
					note(seed .. " " .. cluster.Wall .. " prisms " .. count)
				end
				for _, prism in cluster.Prisms do
					if prism.Length < 1.5 or prism.Length > 3.5 then
						note(seed .. " prism Length " .. prism.Length)
					end
					if prism.Width < 0.5 or prism.Width > 1 then
						note(seed .. " prism Width " .. prism.Width)
					end
					if prism.Pitch < 20 or prism.Pitch > 60 then
						note(seed .. " prism Pitch " .. prism.Pitch)
					end
					if prism.Yaw < -30 or prism.Yaw > 30 then
						note(seed .. " prism Yaw " .. prism.Yaw)
					end
				end
			end
		end
		expect(table.concat(bad, "; ")):toBe("")
	end)

	test("determinism: the same seed produces an identical layout", function()
		for seed = 1, 25 do
			local a = layoutFor(seed)
			local b = layoutFor(seed)
			expect(#a.Stalagmites):toBe(#b.Stalagmites)
			for index = 1, #a.Stalagmites do
				local rockA, rockB = a.Stalagmites[index], b.Stalagmites[index]
				expect(rockA.X):toBe(rockB.X)
				expect(rockA.Z):toBe(rockB.Z)
				expect(rockA.Width):toBe(rockB.Width)
				expect(rockA.Height):toBe(rockB.Height)
				expect(rockA.Yaw):toBe(rockB.Yaw)
				expect(rockA.Tilt):toBe(rockB.Tilt)
			end
			expect(#a.Clusters):toBe(#b.Clusters)
			for index = 1, #a.Clusters do
				local clusterA, clusterB = a.Clusters[index], b.Clusters[index]
				expect(clusterA.Wall):toBe(clusterB.Wall)
				expect(clusterA.Along):toBe(clusterB.Along)
				expect(clusterA.Y):toBe(clusterB.Y)
				expect(clusterA.ColorIndex):toBe(clusterB.ColorIndex)
				expect(#clusterA.Prisms):toBe(#clusterB.Prisms)
				for prismIndex = 1, #clusterA.Prisms do
					local prismA, prismB = clusterA.Prisms[prismIndex], clusterB.Prisms[prismIndex]
					expect(prismA.Length):toBe(prismB.Length)
					expect(prismA.Width):toBe(prismB.Width)
					expect(prismA.Pitch):toBe(prismB.Pitch)
					expect(prismA.Yaw):toBe(prismB.Yaw)
				end
			end
		end
	end)

	test("determinism: different seeds give different layouts", function()
		local first = layoutFor(1)
		local second = layoutFor(2)
		local same = #first.Stalagmites == #second.Stalagmites
		if same then
			for index = 1, #first.Stalagmites do
				if first.Stalagmites[index].X ~= second.Stalagmites[index].X then
					same = false
				end
			end
		end
		expect(same):toBe(false)
	end)

	test("PedestalSpots matches MapService: 13 entries", function()
		expect(#CaveDecor.PedestalSpots):toBe(13)
		local seen = {}
		for _, spot in CaveDecor.PedestalSpots do
			expect(#spot):toBe(2)
			local key = tostring(spot[1]) .. "," .. tostring(spot[2])
			expect(seen[key]):toBeNil()
			seen[key] = true
		end
		expect(seen["-16,-6"]):toBe(true)
		expect(seen["8,2"]):toBe(true)
		expect(seen["8,10"]):toBe(true)
	end)

	test("CaveDecor module contains no require call", function()
		local source = fs.readFile("src/shared/Logic/CaveDecor.luau")
		expect(string.find(source, "require%s*[%(\"']")):toBeNil()
	end)
end
