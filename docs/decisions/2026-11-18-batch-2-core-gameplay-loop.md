# Specification: Batch 2, core gameplay loop (map, caves, plant, grow, shatter)

Status: approved 2026-11-18. Not started; implemented in a separate session (see Progress).

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
