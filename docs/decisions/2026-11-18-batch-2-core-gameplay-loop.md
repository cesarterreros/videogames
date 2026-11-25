# Specification: Batch 2, core gameplay loop (map, caves, plant, grow, shatter)

Status: approved 2026-11-18. Built and verified 2026-11-18 (Studio Play Solo, 2-player local server, Device Simulator, phone stress test and session lock on the published DEV experience). See Outcome.

## Summary

- **What:** the core loop: the map, your own cave, planting a seed on a pedestal, crystals growing (also offline), and shattering for coins.
- **Decided:** a Studio-only top-up to 5 Quartz; "Plant" uses the lowest seed until batch 4's picker; an in-world countdown label and floating "+coins".
- **Result:** done 2026-11-18. **93 tests pass.** Checked in Play Solo, a 2-player server, the Device Simulator and on your phone: stress mode with 78 crystals ran at **57–60 FPS**, and the session lock passed PC → phone.
- **Noticed:** the caves were very dark, which led to the [cave brightness](2026-11-18-cave-brightness-setting.md) record.

## Context

Batch 1 ([record](2026-11-18-batch-1-project-data-setup.md)) is done and committed (`db27909` on `batch-1-setup`):
- **Save data:** profiles load, save and survive rejoining.
- **Remotes:** all 16 remotes exist behind the security layer.
- **Tests:** 64 pass.

There is still nothing to *do* in the game. This batch builds the core loop from the [MVP spec](2026-11-18-crystal-grove-mvp.md): your own cave, planting a seed on a pedestal, watching the crystal grow (also while you're offline), and shattering it for coins. It follows the [architecture](2026-11-18-crystal-grove-architecture.md), build order item 8.

### Outside facts checked (2026-11-18)

- **`Model:ScaleTo(scale)`** ([Model reference](https://create.roblox.com/docs/reference/engine/classes/Model.md)): scales a model around its pivot. The scale must be positive and non-zero. The original sizes are cached after the first call, so repeated scaling doesn't drift. Use `GetScale()` to read it back; the `Scale` property is Studio-only and errors in scripts.
- **`workspace:GetServerTimeNow()`** ([Workspace reference](https://create.roblox.com/docs/reference/engine/classes/Workspace.md)): returns the server's estimated Unix time on every client. It never goes backwards, and the docs say it is **not secure enough for timed rewards**. So it is used only to *display* countdowns and growth. The server decides "ready" with `os.time()`.

## Behaviour

### The world
- **Map:** a dark, flat world with a round **hub** (40-stud radius) in the middle and **6 caves** in a ring around it, 120 studs from the centre and 60° apart.
  - **Hub:** a large decorative glowing "Heart Crystal" and the only spawn pad.
  - **Each cave:** a 64 × 44-stud stone room, open towards the hub, with a low rock ceiling at the edges and a sign above the entrance.
- **Pedestals:** 13 stone pedestals per cave, each a 4-stud cylinder, 8 studs apart:
  - **Rows 1–2:** 2 rows of 5 for pedestals 1–10.
  - **Row 3:** pedestals 11–13 (the Extra Pedestals pass), with gold edges.
  - **Locked pedestals:** shown dim. That means pedestals above your `UnlockedPedestals` (3 at the start), and pedestals 11–13 in this batch.
- **Lighting:** night-time ambience (dark blue) with Bloom, so Neon crystals glow. Fine-tuning comes in batch 6.

### Joining
- **Your cave:** you get the first free cave (1–6). Its sign shows your display name, and its plot is marked as yours.
- **Spawning:** you appear at the hub spawn, and as soon as your profile has loaded you are moved into **your own cave**, in front of pedestal 1. Respawning (after a reset) also puts you in your cave.
- **Crystals still growing:** any crystals you planted before reappear at the right size and keep their countdowns, because growth is based on server timestamps. A crystal whose time ran out while you were away is **ready** when you arrive.
- **Leaving:** your cave is emptied and freed for the next player. Your crystals stay in your saved data.

### Planting (on a phone: tap the prompt; on PC: press E)
- **Plant prompt:** standing within 10 studs of an **empty, unlocked pedestal in your own cave** shows a prompt: **"Plant"** with the seed name (for example "Quartz").
- **Which seed:** in this batch the prompt plants **the lowest-tier seed in your bag**. The seed picker (choosing which seed) comes in batch 4 and uses the same `Plant` remote.
- **What you see:**
  - The seed count drops by 1.
  - A small crystal appears and grows smoothly to full size over its grow time, for example 20 s for Quartz.
  - A label above it counts down ("0:17").
- **Other caves:** you never see prompts in other players' caves.

### Growing and ready
- **While growing:** the crystal scales up from 15% to 100% with an ease-out curve. Its colour is the seed's `ColorHex`.
- **Mutations are visible while growing:**
  - **Glowing:** a soft light and sparkles.
  - **Molten:** an orange-red tint and ember particles.
  - **Prismatic:** a slowly cycling rainbow colour and sparkles.
  - **Size stays hidden** until the shatter.
- **When the timer ends:** the label shows **"READY!"**, the crystal pulses gently, and the prompt changes to **"Shatter"**.
- **Overgrowth:** a ready crystal that is left alone keeps growing visibly: +10% per hour, up to +50% after 5 hours.

### Shattering
- **The action:** using the "Shatter" prompt on a ready crystal in your own cave breaks it:
  - 6–10 glowing shards fly out and fade within 1 second.
  - A floating "+15" rises from the pedestal.
  - **Huge** and **Colossal** crystals add a short camera shake.
- **Coins:** `floor(base value × size roll × mutation multiplier × (1 + overgrowth))`. For example, a Normal Quartz with a 1.2 size roll and no mutation gives 18 coins.
- **Size:** carats = base carats × size roll × (1 + overgrowth). Your **weekly best** is updated in your profile when you beat it. The global leaderboard board comes in batch 3.
- **After the shatter:** the pedestal is empty again, and the coin total is sent to you.
- **Shatter All:** the `ShatterAll` remote shatters every ready crystal in your cave at once. Its button comes in batch 4. In this batch it can only be triggered from the command bar for testing.

### Edge cases
- **Planting with no seeds:** no prompt action happens. The server would reject it anyway.
- **Shattering a crystal that isn't ready:** rejected; nothing changes.
- **Planting on an occupied, locked or someone else's pedestal:** rejected; nothing changes.
- **Two quick taps on Shatter:** only the first counts. The pedestal is emptied before the coins are granted, inside one server step, so it can't pay twice.
- **More than 6 players:** can't happen, because the server size is 6. If no cave is free (an error case), the player is kicked with `Error.NoPlot`.
- **Clock differences:** the client's countdown may be up to about a second off from the server. If you tap "Shatter" a moment early, the server rejects it, and the prompt appears again as soon as the server agrees.

## Not included

- **Shop, buying seeds, pedestal and lamp upgrades, seed-tier unlocks, Codex, daily streak, daily goals, friend bonus, Crystal Surge:** batch 3. So in normal play you can plant your 1 free Quartz once (see Decision 1 for testing).
- **Writing to the global weekly leaderboard and the hub board:** batch 3. This batch only updates `WeeklyBest` in your profile.
- **All screen UI:** the HUD, coin counter, seed picker, result popup, Shatter All button and tap-from-a-distance on crystals. These are batch 4. This batch's only on-screen text is the in-world countdown label and the floating "+coins".
- **Tutorial, sounds, music, server announcements:** batch 4.
- **Passes, Instant Grow and Luck Boost:** batch 5. The growth and roll functions already take the multipliers as arguments, but nothing passes them yet.
- **Final lighting, cave decoration and the performance tuning pass:** batch 6.

## Design

**Stored data:** no schema change. Batch 2 uses the existing version 1 fields: `SeedBag`, `Pedestals`, `Coins`, `Stats`, `WeeklyBest` and `UnlockedPedestals`.

### Shared contract (fixed before parallel work)

```lua
-- World layout built by MapService (server). Names are exact.
workspace.Map                                   -- Folder
  Hub                                           -- Model: floor disc, HeartCrystal, SpawnLocation "HubSpawn"
  Plots                                         -- Folder
    Plot_1 .. Plot_6                            -- Model, attributes: PlotIndex:number, OwnerUserId:number (0 = free)
      Floor, Walls (Model), Sign (Part with SurfaceGui "SignGui" > TextLabel "OwnerName")
      SpawnPoint                                -- Part, Anchored, Transparency 1, CanCollide false (player is moved here)
      Pedestals                                 -- Folder
        Pedestal_1 .. Pedestal_13               -- Part (Cylinder), Anchored. Attributes (set by CrystalService):
          Index:number, Unlocked:boolean, Gold:boolean (11–13),
          SeedId:string ("" = empty), PlantedAt:number, ReadyAt:number,
          Mutation:string ("None"|"Glowing"|"Molten"|"Prismatic"), Shape:number
        -- SizeRoll is NEVER an attribute (secret until shatter).
-- The client parents its locally built crystal model under each pedestal as "Crystal" (client-only instance).

-- Logic (pure, NO requires)
Growth.growSeconds(baseSeconds: number, lampLevel: number, lampStep: number, speedMult: number?): number
  -- base × (1 − lampLevel × lampStep) × (speedMult or 1), at least 1 second (math.max(1, ...)), not rounded
Growth.progress(now: number, plantedAt: number, readyAt: number): number   -- clamped 0..1; readyAt <= plantedAt → 1
Growth.isReady(now: number, readyAt: number): boolean                       -- now >= readyAt
Growth.overgrowth(now: number, readyAt: number, perHour: number, cap: number): number  -- 0..cap, continuous
Growth.shatterValue(baseValue, baseCarats, sizeRoll, mutationMult, overgrowth, coinMult: number?)
  : (coins: number, carats: number)  -- coins = floor(baseValue*sizeRoll*mutationMult*(1+og)*(coinMult or 1)); carats = baseCarats*sizeRoll*(1+og)
Rolls.size(rng: () -> number, sizeTable): (roll: number, tierName: string)
  -- pick a tier by Chance with one rng() draw, then Min + (Max−Min)*rng()
Rolls.mutation(rng: () -> number, mutationTable, chanceMult: number?): (name: string, mult: number)
  -- each Chance × (chanceMult or 1), checked rarest-first; "None", 1 if none hit; chances scaled so their sum ≤ 1
Rolls.shape(rng: () -> number): number   -- integer 1..2147483646
Rolls.sizeTierName(sizeRoll: number, sizeTable): string   -- tier whose [Min, Max) contains the roll (Colossal includes 8.0)

-- Server services
PlotService:GetPlot(player): Model?            -- the player's Plot_n, nil if none
PlotService:GetPedestal(player, index): BasePart?
PlotService.PlotAssigned: signal (player, plot)
CrystalService handles remotes Plant(index, seedId), Shatter(index), ShatterAll()
  ShatterResult payload (to the owner only):
  { pedestal: number, coins: number, carats: number, mutation: string, sizeTier: string,
    newBest: boolean, instantGrown: boolean }

-- Client controllers
CrystalBuilder.build(seedColorHex: string, shape: number, tier: number): Model   -- pure-ish builder, pivot at the base
CrystalRenderer: watches every Pedestal_n attribute, builds/scales/animates crystals, shows the countdown label,
                 and creates ProximityPrompts ONLY for the local player's own plot
EffectsController: listens to ShatterResult and plays the burst, "+coins" and camera shake
```

### How it works
- **Server timeline for a plant:**
  1. Validate: the pedestal is in your plot, unlocked and empty, and the seed count is at least 1.
  2. Take the seed from the bag.
  3. Roll the size (kept secret), the mutation and the shape.
  4. Store the crystal in `Pedestals["n"]` with `PlantedAt = os.time()` and `ReadyAt = PlantedAt + growSeconds`.
  5. Copy the public fields to the pedestal's attributes.
  6. Send `StateSync`.
- **Shatter:**
  1. Validate: the crystal is yours and `os.time() >= ReadyAt`.
  2. Remove it from `Pedestals` **first**.
  3. Compute the overgrowth, coins and carats.
  4. Add the coins and update `Stats` and `WeeklyBest` (using `WeekId.fromUnix(os.time())`).
  5. Clear the attributes.
  6. Send `ShatterResult`, then `StateSync`.
- **Random numbers:** one server `Random.new()` instance; `rng = function() return random:NextNumber() end`.
- **Rendering:** the client checks growing crystals **4 times a second** (not every frame) and tweens the scale between checks. That keeps 78 crystals cheap. Ready crystals pulse from one shared Heartbeat loop. PointLights are created only for tier 7+ crystals or crystals with a mutation, as the MVP performance budget says.
- **Moving the player to their cave:** on `CharacterAdded`, once the profile is loaded and a plot assigned, `character:PivotTo(SpawnPoint.CFrame + Vector3.new(0, 3, 0))`.

### Files

| File (under `roblox/` unless rooted) | Location in Roblox | Change |
|---|---|---|
| `/.gitattributes` | — | New: `* text=auto eol=lf`, with `*.rbxm`, `*.rbxl` and `*.png` marked binary; existing files renormalized |
| `src/shared/Logic/Growth.luau`, `Rolls.luau` | Shared.Logic | New (pure) |
| `tests/Growth.spec.luau`, `tests/Rolls.spec.luau` | — | New |
| `src/server/Services/MapService.luau` | Server.Services | New: builds `workspace.Map` and sets Lighting |
| `src/server/Services/PlotService.luau` | Server.Services | New: assigns and frees plots, signs, moves characters |
| `src/server/Services/CrystalService.luau` | Server.Services | New: Plant, Shatter and ShatterAll handlers, attribute sync |
| `src/server/Main.server.luau` | Server | Order becomes Analytics → RemoteService → DataService → MapService → PlotService → CrystalService |
| `src/client/Controllers/CrystalBuilder.luau` | Client.Controllers | New |
| `src/client/Controllers/CrystalRenderer.luau` | Client.Controllers | New |
| `src/client/Controllers/EffectsController.luau` | Client.Controllers | New |
| `src/client/Main.client.luau` | Client | Order becomes StateController → CrystalRenderer → EffectsController |
| `src/shared/Strings/en.luau` | Shared.Strings | New keys: `Prompt.Plant` "Plant", `Prompt.Shatter` "Shatter", `Crystal.Ready` "READY!", `Error.NoPlot` "No free cave on this server. Please rejoin.", `Seed.<Id>` names for all 10 seeds ("Quartz", "Amethyst", "Citrine", "Rose Quartz", "Emerald", "Sapphire", "Ruby", "Moonstone", "Starfire Opal", "Voidheart") |
| `src/shared/Config/Game.luau` | Shared.Config | New: `DevStudioSeedTopUp = 5` (see Decision 1) and `RenderTickSeconds = 0.25` |

**In Studio (you):** delete the template **Baseplate** and **SpawnLocation** from Workspace, then **File → Save to Roblox**. The map supplies its own floor and spawn.

## Task breakdown and model assignment

| # | Task | Model | Why this model | Depends on |
|---|---|---|---|---|
| 0 | Save this record (approved) | Orchestrator | — | — |
| 1 | `.gitattributes` and `git add --renormalize .`; Strings and Game config additions | Orchestrator | Tiny, needs git judgment | 0 |
| 2 | `Logic/Growth`, `Logic/Rolls` + specs (1,000,000 seeded rolls) | DeepSeek Flash | Pure functions with an exact contract | 1 |
| 3 | `Services/MapService` | DeepSeek Flash | Standard geometry code from the exact layout | 1 |
| 4 | `Services/PlotService` | DeepSeek Flash | Small service, contract fixed | 3 |
| 5 | `Services/CrystalService` + `Main.server` order | Orchestrator | Coins and validation are security-critical (project rule) | 2, 4 |
| 6 | `Controllers/CrystalBuilder` | DeepSeek Flash | Procedural model building | 1 |
| 7 | `Controllers/CrystalRenderer` | DeepSeek Flash (Pro if Flash is cut off twice) | Largest client file; attribute watching, prompts, animation | 2, 6 |
| 8 | `Controllers/EffectsController` + `Main.client` order | DeepSeek Flash | Standard effects code | 7 |
| 9 | **Performance proof:** a Studio-only stress mode (client command bar: `workspace:SetAttribute("StressTest", true)`) renders Epic crystals with mutations on all 78 pedestals; read the FPS in the emulator and on your phone | Orchestrator + you | Judgment on the numbers | 7 |
| 10 | Review every diff, StyLua, tests, `rojo build`, Studio checks with you, record findings and outcome | Orchestrator | Review and integration | 2–9 |

DeepSeek runs one job at a time in this workspace, so tasks 2, 3, 4, 6, 7 and 8 run one after another. Each job is told to write each file in one go, because a batch 1 job ran out of turns while making many small edits.

Escalation:
- **Review failures:** a delegated task that fails review goes back once with the specific defects, then to DeepSeek Pro. The orchestrator finishes small fixes itself.
- **If the performance proof (task 9) runs below 30 FPS on your phone**, follow the MVP fallback order:
  1. PointLights only on Legendary crystals.
  2. Halve the particle rates.
  3. Drop the Glass shell (Neon only).

  The result is recorded as findings before batch 3.

### Acceptance criteria

- **Task 1:** `git status` is clean after renormalizing; `stylua --check` passes on a fresh checkout; the new strings exist.
- **Task 2:**
  - Every contract function exists with exact signatures and no `require`.
  - Tests: lamp level 5 gives 75% of the base time; `speedMult` 0.5 halves it; the result is never below 1 second; progress is clamped; overgrowth is 0 before ready, 0.10 after 1 hour, and capped at 0.50 after 10 hours; `shatterValue` matches hand-computed examples.
  - With 1,000,000 seeded rolls, each size tier and mutation lands within ±10% of its stated chance, and size rolls stay inside their tier's range.
  - `chanceMult` 2 doubles the mutation rates, and the chances never add up to more than 1.
- **Task 3:**
  - The map matches the contract names and counts: 6 plots, 13 pedestals each, 1 `HubSpawn`.
  - Everything is anchored. The map is built once, at `Init`, and Lighting is set.
- **Task 4:**
  - Plots are assigned on `ProfileLoaded` (lowest free index), and the sign shows the display name.
  - Plots are freed on leave: `OwnerUserId = 0`, the sign is cleared, and the pedestal attributes are reset.
  - The character is moved into the cave on every spawn. A kick with `Error.NoPlot` happens only when no plot is free.
- **Task 5:**
  - Every rule in "How it works" is followed. Handlers act only on the caller's own plot.
  - The crystal is removed before coins are granted.
  - `SizeRoll` never appears in attributes or `StateSync`.
  - Crystals are restored to attributes on join.
  - In Studio only, a bag with fewer than 5 Quartz is topped up to 5 on load (Decision 1).
- **Task 6:** a crystal has 3–7 prisms (Neon core + Glass shell), the same `shape` always gives the same look, and the pivot sits at the base.
- **Task 7:**
  - Crystals appear, grow, pulse when ready and show overgrowth, for every plot.
  - Prompts appear only in the local player's plot, and they fire `Plant` or `Shatter` with the right index.
  - The label counts down using `GetServerTimeNow`.
  - Stress mode works only in Studio.
- **Task 8:** the burst, "+coins" and shake behave as described; temporary parts are cleaned up within 1.5 s.
- **Task 10:** all tests pass (64 existing + the new ones), StyLua is clean, `rojo build` succeeds, and the checks below pass.

## Verification

- **Automated tests** (`lune run tests` from `roblox/`): `Growth.spec` and `Rolls.spec`, plus the existing 64.
- **Backup first:** not needed. There is no schema change, and only dev data exists.
- **Studio Play Solo (dev experience):**
  1. Join → you are moved into a cave whose sign shows your name; 3 pedestals look unlocked, 10 dim.
  2. Plant a Quartz → the countdown runs from about 0:20, the crystal grows, and then "READY!" appears and it pulses.
  3. Shatter → shards, a "+N" with N at least 15 (15–21 for a Normal size, more for Big or larger or with a mutation), and the Output `[State]` shows the coins increased by N.
  4. Plant, then Stop before it's ready, wait 30 s, then Play → the crystal is shown ready.
- **Studio local server with 2 players:**
  1. They get different caves with their own names.
  2. Player A sees no prompts in B's cave.
  3. From A's client command bar, `Remotes.Shatter:FireServer(1)` while B has a ready crystal on pedestal 1 → rejected, and B's crystal stays.
  4. Both see each other's crystals grow.
  5. Also: the `[Remote] rejected …` screenshot left open from batch 1.
- **Device emulator (phone, landscape):** the prompts can be tapped; the countdown label is readable.
- **Stress proof:** `StressTest` on → FPS in Studio's emulator and on your phone (published dev experience) is recorded in the findings. The target is at least 30 FPS on the phone.
- **Phone session lock** (left open from batch 1): join on PC, then on your phone with the same account → `sessions` goes up by exactly 1, and your crystals are still there.

## Decisions for you before approval

1. **Studio-only seed top-up:** in Studio (never live), your bag is topped up to 5 Quartz on load, so you can test the loop before the shop exists. It writes to your **dev** data only. Alternative: test with the single free Quartz and wait for batch 3. **Recommended: top-up.**
2. **Planting picks your lowest-tier seed** until the seed picker arrives in batch 4. Alternative: the highest tier. **Recommended: lowest**, the cheaper seed to lose while testing.
3. **The in-world countdown label and floating "+coins" are built in this batch,** even though screen UI waits for batch 4. Without them the loop can't be tested by eye. Alternative: Output prints only. **Recommended: build them.** They're world elements, not HUD.

## Decisions (confirmed by the user 2026-11-18)

1. **Studio-only seed top-up to 5 Quartz on load.** Rejected: testing with the single free Quartz.
2. **"Plant" uses the lowest-tier seed in the bag** until the batch 4 seed picker. Rejected: highest tier.
3. **The in-world countdown label and floating "+coins" are built in this batch.** Rejected: Output prints only.

## Progress (2026-11-18)

- You asked for every batch plan to be written before any implementation, so that each batch can be built in **its own new session** to save context. Batch 2 is implemented in a fresh session that starts with the steps in [README.md → Starting a new session](README.md#starting-a-new-session).
- **Before task 1, read:** this record; [README.md](README.md); the batch 1 record's **Task 1 findings**, **Progress** and **Outcome**; and the code files this plan changes (`Main.server.luau`, `Main.client.luau`, `Strings/en.luau`, `Config/Game.luau`), plus `Services/DataService.luau` and `Services/RemoteService.luau` for the APIs used (`DataService.ProfileLoaded`, `:GetData`, `:SyncState`, `RemoteService:On`, `:Fire`).

### Implementation progress (2026-11-18, implementation session)

**Code for tasks 1–8 is written and reviewed. Tasks 9 (stress proof) and 10 (Studio checks) need you in Studio.** Branch: `batch-2-core-loop` (from `batch-1-setup`).

| Task | Files | Written by | Review |
|---|---|---|---|
| 1 | `/.gitattributes`, `Strings/en`, `Config/Game` | Orchestrator | `git add --renormalize .` changed nothing (every file was already LF) |
| 2 | `Logic/Growth`, `Logic/Rolls`, `tests/Growth.spec`, `tests/Rolls.spec` | DeepSeek Flash | Accepted first time (17 + 11 tests; seeded xorshift32, 1,000,000 rolls per distribution) |
| 3 | `Services/MapService` | DeepSeek Flash | Accepted; orchestrator fixed one wrong comment and added `MapService.setPedestalLook` |
| 4 | `Services/PlotService` | DeepSeek Flash | Accepted first time |
| 5 | `Services/CrystalService`, `Main.server` order | Orchestrator | Self-review added a catch-up loop in `Start` (PlotService's own catch-up can fire `PlotAssigned` before CrystalService connects) |
| 6 | `Controllers/CrystalBuilder` | DeepSeek Flash | Accepted first time (tilt direction checked by hand: tops lean outward) |
| 7 | `Controllers/CrystalRenderer`, `Controllers/CrystalVisuals` | DeepSeek Flash, **cut off once** (one response too long, nothing written); retried with the file split in two | Orchestrator fixed 2 defects: a new crystal could ease toward the previous crystal's scale for up to 0.25 s; stress mode skipped the 4 Hz tick, so Prismatic hues didn't cycle under load |
| 8 | `Controllers/EffectsController`, `Main.client` order | DeepSeek Flash; order by orchestrator | Accepted; removed one unused require |

**Changes from the plan:**
- **New file `Controllers/CrystalVisuals.luau`:** mutation lights and particles, the countdown label and the scale curve, split out of `CrystalRenderer` so each DeepSeek write fit in one response.
- **New pure helper `Format.countdown(seconds)`** ("0:17", "1:02:05", rounded up) with 1 test, so the label text is unit-tested.
- **`MapService.setPedestalLook(pedestal, unlocked)`:** one place for the dim/bright pedestal colour, used by PlotService (reset on leave) and CrystalService (unlock state on join).
- **`Growth.shatterValue` floors `x + 1e-9`**, so float products such as 17.9999999 don't lose a coin. Tested.
- **Carats are rounded to 2 decimals** before the weekly-best comparison and in `ShatterResult` (the leaderboard stores carats × 100).
- **A planted seed with count 0 is removed from `SeedBag`** instead of kept as 0.
- **Prisms are blocks, not true hexagons:** each prism is a Neon block core plus a Glass block shell turned 22.5° against it, which reads as many-sided. Roblox has no hexagonal part, and real hexagons would need 6+ parts per prism.
- **Client effects:** temporary parts live in a client-only `workspace.ClientEffects` folder.

**Checks run:**
- `lune run tests`: **93 passed, 0 failed** (64 existing + 29 new).
- `stylua --check` (src without Vendor, tests): clean.
- `rojo build`: succeeds.
- **No check in Studio yet.** Nothing in tasks 3–8 has run in Roblox.

### Studio verification (2026-11-18, verification session)

Run with the Roblox Studio MCP in Play Solo on "Crystal Grove DEV", after reconnecting the Rojo plugin (the old connection was open but hadn't synced any batch 2 file).

**Play Solo checks:**

| # | Check | Result |
|---|---|---|
| 1 | Moved into a cave with your name; 3 pedestals bright, 10 dim | **Passed.** Plot_1, sign shows the display name, character 2 studs from `SpawnPoint`; pedestals 1–3 `Unlocked=true` and bright, 4–13 dim; Plot_2–6 `OwnerUserId=0`. Prompts exist only on your 3 unlocked pedestals. |
| 2 | Plant → countdown from about 0:20, grows, "READY!" and pulse | **Passed after a fix** (see Findings). `ReadyAt − PlantedAt = 20`, label read "0:19" right after planting, the prompt hides while growing, the crystal grew, and "READY!" appeared with a pulse (bounding-box height 3.50 → 3.79 studs over 0.9 s). |
| 3 | Shatter → shards, "+N" (N ≥ 15), `[State]` coins up by N | **Passed.** `[Shatter] pedestal=1 +15 coins 1.05 ct None Normal`, `[State]` coins 0 → 15; a second run gave a "+15" label and coins 15 → 30. The crystal is removed, the prompt goes back to "Plant", and the effect parts were gone within about 1.25 s (inside 1.5 s). |
| 4 | Plant, Stop before ready, wait 30 s, Play → shown ready | **Passed.** After Play the pedestal kept its `ReadyAt`, the crystal showed "READY!", and the prompt was "Shatter". |

The Studio top-up worked (`Quartz 1 -> 5`, and `3 -> 5` on the next join).

**Stress test (Studio, PC):** `StressTest` on → 78 crystals, 920 crystal parts, 78 PointLights, 78 emitters. **60 FPS** before and after (worst frame about 22 ms) from the player camera in the cave, and 60 FPS from a scripted high camera. It's **not confirmed** that all 78 crystals were on screen in that second reading: the screenshot didn't show the scripted camera, and the cave walls block the view. The PC number isn't the target. **The phone reading (target ≥ 30 FPS) is still open.**

**Findings:**
- **Fixed: the countdown/"READY!" label sat 7.5 studs beside the pedestal.** `BillboardGui.StudsOffsetWorldSpace` is measured along the adornee's own axes, and pedestals are cylinders rolled 90° on Z (their up vector is world −X). `CrystalVisuals.makeLabel` now converts world-up with `pedestal.CFrame:VectorToObjectSpace(...)`. A screenshot confirmed the label above the crystal. Tests (93/93), StyLua and `rojo build` still pass.
- **The caves are very dark.** Pedestals and the character are barely visible outside the crystals' glow (Lighting `ClockTime=0`, low Ambient). This is a look decision for you, not a defect.
- **`ContentId: rbxassetid://203785492 failed … Asset type does not match` (3× on every join)** comes from outside our code: no instance in Workspace, Lighting, the player, ReplicatedStorage or SoundService references it, and the ID isn't in `src`. Probably the avatar or Studio itself. Left alone.

**Local server, 2 players** (Test → Start Test Session → Server and Clients, then Test → Add Clients; checked through the MCP in each client window):

| # | Check | Result |
|---|---|---|
| 1 | Different caves with their own names | **Passed.** Player1 → Plot_1, Player2 → Plot_2; each sign shows its own name; both characters 2 studs from their `SpawnPoint`. |
| 2 | A sees no prompts in B's cave | **Passed.** Player1's client has prompts only on Plot_1 pedestals 1–3; Player2's only on Plot_2 pedestals 1–3. |
| 3 | A fires `Shatter(1)` while B has a ready crystal on pedestal 1 → rejected, B's crystal stays | **Passed.** Player2's crystal kept `SeedId=Quartz`, its `ReadyAt` and its model. No log line: the handler only reads the caller's own data, so the request meant "Player1's pedestal 1" (empty) and did nothing. A client can't address another player's cave at all. |
| 4 | Both see each other's crystals grow | **Passed.** Player1 saw Player2's crystal grow 3.00 → 3.53 studs with the countdown; Player2 saw Player1's grow 1.70 → 2.81. |
| 5 | `[Remote] rejected …` lines (open from batch 1) | **Passed.** `rejected Shatter … expected number, got string`, `… above 13`, `rejected Plant … too many arguments (3 > 2)`, `rejected Shatter … not a finite number`. |

Test note: in an unfocused client window, ProximityPrompts don't show (`PromptShown` never fires), so `InputHoldBegin` can't trigger them. Those plants were sent as `Remotes.Plant:FireServer(index, "Quartz")`, the same call the prompt makes. Prompt triggering itself was already checked in Play Solo.

**Device Simulator (phone, landscape; Play Solo, viewport 685×338, touch input):**
- **Prompts can be tapped: passed.** You tapped Plant and Shatter by hand ("easy to hit"); the server logged 2 plant/shatter loops on pedestal 3 (+15, +19; coins 30 → 64). The prompt's tap area is 72×72 points.
- **Countdown readable: passed after a change.** Readable at 4 × 1.2 studs but small (about 19 px tall on the phone), so the label is now **6.5 × 2 studs** (you confirmed "right size") and sits **8.5 studs** above the pedestal centre (was 7.5) to clear larger crystals.
- Test note: my simulated clicks couldn't do this. With VS Code focused, the Studio viewport stopped redrawing and the prompt wasn't drawn.

**Fixed: the label now follows the crystal's top** (your decision, 2026-11-18). A fixed 7.5–8.5-stud offset couldn't fit both ends: crystal height is `3 + tier × 0.3` studs, overgrowth scales it up to 1.5× (× 1.04 pulse), and an overgrown tier-10 crystal reached 10.8 studs above the pedestal centre, past the label's bottom edge. Now:
- `CrystalRenderer` records each model's height at scale 1 when it's built. On every 4 Hz tick (and right after a refresh) it places the label at pedestal top + height × scale + 1.5 studs. For a ripe crystal the scale is `(1 + overgrowth) × 1.04`, the pulse's peak, so the label doesn't bob. The label is only moved when its height changes by more than 0.05 studs.
- `CrystalVisuals.placeLabel(gui, pedestal, height)` holds the axis conversion. `makeLabel` starts the label at 8.5 studs until the first placement.
- Measured in Studio (gap = label bottom − crystal top): overgrown Voidheart (tier 10, ripe 10 h, set as display-only attributes) **+1.34** (was −3.31); ripe Quartz +0.85 to +1.18; growing Quartz +0.69 to +0.91 at each of 7 samples. A screenshot shows both labels above their crystals.
- Stress on/off made no difference (14.9 FPS both ways). That run was capped at about 15 FPS because Studio's window wasn't focused, so it says nothing about absolute performance. The 60 FPS PC reading above was taken earlier, before this change.

Tests 93/93, StyLua and `rojo build` pass after these changes.

**Plan change (confirmed by you 2026-11-18): stress mode also runs in the DEV universe.** As planned it worked only in Studio (`RunService:IsStudio()`), so the phone reading the plan asks for was impossible. The client now also accepts `StressTest` when `game.GameId == GameConfig.DevUniverseId` (new constant `10777641396`, the "Crystal Grove DEV" universe), never in the live universe. To switch it on from a phone: chat `/console` → Server command line → `workspace:SetAttribute("StressTest", true)`. The attribute replicates to your client, which prints `[Stress] fps=N crystals=78` every 2 s in the Client log. Rejected: phone FPS with only your own 3 crystals; Device Simulator reading only. Tests 93/93, StyLua and `rojo build` pass.

**Published DEV experience, phone (portrait), 2026-11-18:**
- **Stress proof: passed.** `StressTest` switched on from the phone's developer console (Server command line). 30 `[Stress]` readings over 60 s: **57–60 FPS with 78 crystals** (target ≥ 30). Client memory 664–771 MB. No MVP fallback needed (PointLights, particle rates and Glass shells stay as built).
- **Phone screenshots:** the "READY!" label sits above the crystal, and the Quartz/Shatter prompt shows and works.
- **Session lock (open from batch 1): passed.** DataStore read from Studio (read-only): `Sessions` 11 → 12 after the PC join, then **12 → 13** after the phone join, which dropped the PC session ("Same account launched experience from different device", error 276). The profile was locked by the phone's server and saved normally: coins 116 → 137 → 173 from your shatters, and the pedestal 1 crystal persisted.

**All batch 2 checks are done.**

## Outcome (2026-11-18)

- **Built as specified**, with these differences (details in **Implementation progress** and **Studio verification** above):
  - **New file** [CrystalVisuals.luau](../../roblox/src/client/Controllers/CrystalVisuals.luau), split out of `CrystalRenderer` so each delegated write fit in one response. **New helpers:** `Format.countdown` and `MapService.setPedestalLook`.
  - **Prisms are blocks** (a Neon core inside a Glass shell turned 22.5°), not true hexagons.
  - **The countdown label** is 6.5 × 2 studs (you chose the size in the phone simulator) and follows the crystal's top. It was planned as a fixed label 7.5 studs up; that fixed offset was buggy (sideways on the rolled cylinder pedestals) and too low for overgrown high-tier crystals.
  - **Stress mode also runs in the DEV universe** (`GameConfig.DevUniverseId`), never live, so it could be measured on a real phone (your decision, 2026-11-18).
- **Who did what:**
  - **DeepSeek Flash** wrote tasks 2, 3, 4, 6, 7 and 8. Accepted first time: 2, 4, 6 and 8 (one unused require removed). Task 3: a comment fixed and one helper added. Task 7 was cut off once (one response too long, nothing written) and succeeded after the file was split. Review fixed 2 defects: a new crystal easing toward the old crystal's scale, and Prismatic hues not cycling under stress.
  - **The orchestrator** wrote tasks 1 and 5: `CrystalService`, which holds the coin and validation rules. In the verification session it also wrote the label fixes and the DEV-universe gate.
  - Nothing went to DeepSeek Pro.
- **Tests:** `lune run tests` gives **93 passed, 0 failed** (64 existing + 29 new). `stylua --check` is clean, and `rojo build` succeeds with no warnings.
- **Each place checked:**

  | Where | What | Result |
  |---|---|---|
  | Studio Play Solo (dev experience) | Join, plant, grow, ready, shatter; Stop, wait 30 s, Play | All 4 passed. Coins 0 → 15 → 30 matched the logged "+15" shatters. The crystal was restored ready after the restart. |
  | Studio local server, 2 players | Separate caves and names; no prompts in the other cave; cross-cave `Shatter(1)`; both see growth; `[Remote] rejected …` lines | All passed. Player2's crystal kept `SeedId`, `ReadyAt` and its model. There were 4 rejection lines with reasons, which closes the batch 1 leftover. |
  | Studio Device Simulator (phone, landscape) | Tap the prompts; read the countdown | You planted and shattered by hand (2 loops, coins 30 → 64) and called the prompt "easy to hit". The label passed after the resize. |
  | Studio, PC | Stress mode (78 crystals) | 60 FPS. |
  | Published DEV experience, your phone | Stress mode (78 crystals) | **57–60 FPS** across 30 readings (target ≥ 30). No MVP fallback needed. |
  | Published DEV experience, PC then phone | Session lock (batch 1 leftover) | `Sessions` 11 → 12 → **13**, exactly +1 per join. The phone's join dropped the PC session. Coins and the pedestal 1 crystal saved normally. |

- **Not verified:**
  - **Studio emulator FPS under stress.** It read 14.9 FPS with and without stress, because Studio caps its frame rate when its window isn't focused. The real-phone reading replaces it.
  - **The PC overview reading** (60 FPS from a high camera): it isn't confirmed that all 78 crystals were on screen.
  - **The "+N" label on screen.** It was confirmed only from logs and instance checks; the screenshot ran after the effect had already cleaned up.
  - **`StudsOffsetWorldSpace` axis behaviour** (official-docs rule): it was established by measurement in Studio (the label moved 7.5 studs along the pedestal's local Y = world −X), not from the official docs page.
- **Known limits:**
  - In unfocused Studio test windows, ProximityPrompts don't show, so the 2-player plants were sent as the same `Plant` call the prompt makes.
  - "Plant" still uses the lowest-tier seed until the batch 4 seed picker.
- **Leftovers:**
  - **Dev data:** in the dev DataStore your profile has `Sessions=13`, 173 coins and a Quartz crystal on pedestal 1. The 2-player test created test profiles `Player_-1` and `Player_-2`.
  - **Dev-only tools that stay by design:** the Studio-only seed top-up, and stress mode (Studio + DEV universe).
  - **Session leftovers:** the Rojo server started in this session is still running. `test.rbxlx` is in the session scratchpad, outside the repo. Nothing temporary is in the repo.
- **Noticed, not changed:**
  - **The caves are very dark** (Lighting `ClockTime=0`, low Ambient): pedestals and avatars are barely visible outside crystal glow. This is a look decision for a later batch.
  - **`rbxassetid://203785492 … Asset type does not match`** appears 3× per join. It comes from Studio or the avatar, not our code (the same finding as batch 1).
  - **The Rojo server from the earlier session stopped by itself** partway through verification, and Studio silently kept the old copy of one file. After any sync problem, check the script's length or content in Studio before trusting a test.
