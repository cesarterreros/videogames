# Specification: Cave brightness you can tune, and a brightness setting for players

Status: approved 2026-11-18; re-approved 2026-11-21 with the task 1 values and lighter cave surfaces (Decision 4).

## Context

In batch 2's verification you saw that **the caves are very dark**: outside the crystals' glow, the pedestals and avatars are barely visible ([batch 2 record → Studio verification](2026-11-18-batch-2-core-gameplay-loop.md)). You asked to control the darkness before batch 3, both as the developer and as a player setting (your choice, 2026-11-18).

**Today:**
- **One server-side function sets the lighting:** `setupLighting` in [MapService.luau:464](../../roblox/src/server/Services/MapService.luau#L464). It sets `ClockTime = 0` (midnight), `Brightness = 1`, `Ambient = RGB(24, 26, 48)`, `OutdoorAmbient = RGB(34, 38, 70)`, fog to 600 studs, and a Bloom effect (a soft glow around bright parts such as the Neon crystals). Ambient is the light that reaches every surface even where no lamp shines; today it is close to black.
- **Saved settings:** the profile has `Settings = { AutoShatter = false, Music = true }` ([ProfileTemplate.luau:34](../../roblox/src/shared/Logic/ProfileTemplate.luau#L34)). The whole profile, `Settings` included, already reaches the client in every `StateSync`.
- **The only settings remote** is `SetSetting(key: "AutoShatter" | "Music", value: boolean)`. Its value is a yes/no, so it can't carry a three-way choice. It has no server handler yet; batch 4 plans `SettingsService` for Music.
- **There is no screen UI yet.** The HUD arrives in batch 4.

### Outside facts checked (2026-11-18)

- **Lighting properties** ([Lighting reference](https://create.roblox.com/docs/reference/engine/classes/Lighting), [Lighting guide](https://create.roblox.com/docs/environment/lighting)):
  - `Ambient` "sets a hue for the entirety of a game"; `Brightness` "sets the intensity of illumination".
  - `ExposureCompensation` works like camera exposure: lower is darker, higher is brighter.
  - The pages give no ranges for these values.
- **Whether a client-side Lighting change stays on that one client:** none of these pages says so: the Lighting reference, the Lighting guide, [Client-server runtime](https://create.roblox.com/docs/projects/client-server) or [Security tactics](https://create.roblox.com/docs/scripting/security/security-tactics). The player setting depends on it, so **task 1 proves it** with 2 players before any code is written.

## Behaviour

### Three brightness levels

| Level | Look | Who gets it |
|---|---|---|
| **Dark** | Today's look: near-black caves, crystals glow strongly | Players who choose it |
| **Normal** | Pedestals, walls and avatars clearly visible; crystals still glow | **Everyone by default**, including existing profiles |
| **Bright** | Caves easy to read even on a dim phone screen; glow less dramatic | Players who choose it |

You chose the values in task 1 from Studio screenshots (see Design → "Chosen values"). Lighting alone couldn't brighten the near-black cave surfaces, so the surfaces are also about 2.5× lighter for everyone (Decision 4). Dark keeps today's lighting and still looks close to today.

### For you (developer)

- **Where:** all three levels and the default level are numbers in one file, `Config/Lighting.luau`.
- **Tuning live:** during a Studio Play, change `Lighting.Ambient`, `OutdoorAmbient`, `Brightness` or `ExposureCompensation` on the client in the Properties panel. You see the result at once. Copy the numbers you like into `Config/Lighting.luau`. The game only re-applies a level when the player changes it, so it won't overwrite your experiments.
- **Changing the default** is one line: `Default = "Normal"`.

### For players

- **Where:** a round button at the top right of the screen, under the Roblox top-bar area, showing **☀**. Minimum 48 × 48 points, so it's easy to tap on a phone.
- **On tap:** it cycles **Normal → Bright → Dark → Normal**. The cave changes at once, and a small label under the button shows the level name ("Bright") for 1.5 s.
- **Saved:** the choice is stored in the player's profile and is applied on every later join, on any device.
- **Only you see it:** your brightness changes only your own screen. Other players keep theirs (proved in task 1).

### Edge cases

- **Join before the profile loads:** the server's default (Normal) shows until the profile arrives, then the saved level is applied. This takes under a second normally.
- **Profiles saved before this change** have no brightness value. Loading fills in `Normal`.
- **A broken or unknown stored value** (anything other than the 3 names) is repaired to `Normal` on load.
- **Fast tapping:** each tap changes the screen at once. The server saves at most what the rate limit allows (8 per second, burst 12, the default). The last accepted value wins.
- **If the save is rejected or lost:** the screen keeps the tapped level for this session. The next `StateSync` shows the saved level again.

## Not included

- **A slider** (any value between Dark and Bright). Three levels are simpler to tap and to test.
- **Lamps or torches inside the caves.** The levels only change global lighting. Extra light parts cost performance on phones; maybe in batch 6's art pass.
- **Changing fog, bloom or time of day per level.**
- **A settings menu.** It's one button. Batch 4's HUD absorbs it (see "Changes to later plans").
- **Per-cave lighting** (a different look per cave).

## Design

**Server:** sets the default level once at start, from config, and saves the player's choice through a new remote.
**Client:** applies the player's level to its own `Lighting`, and draws the button.

### How it works

1. `MapService.setupLighting` reads `Config/Lighting.luau` and applies `Presets[Default]` instead of hard-coded numbers. Fog, bloom and `ClockTime` stay as they are. `MapService` also builds the cave surfaces in the lighter colours below (Decision 4).
2. The client's `LightingController` listens to `StateController.Changed`. When `Settings.Brightness` differs from what it last applied, it writes that preset's 4 values to its own `Lighting`.
3. `BrightnessButton` (client) cycles to the next level and calls `LightingController.apply(level)` at once, so the change shows immediately. Then it fires `SetBrightness(level)`.
4. `SettingsService` (server, new) handles `SetBrightness`: the argument was already validated by `RemoteService` against the 3 names. It sets `data.Settings.Brightness` and calls `DataService:SyncState(player)`.

The server never reads the brightness for game rules. It is cosmetic, so the server-authority rule isn't affected; the server only stores it.

### Chosen values (task 1, approved 2026-11-21)

| Level | Ambient | OutdoorAmbient | Brightness | ExposureCompensation |
|---|---|---|---|---|
| Dark | 24, 26, 48 (today) | 34, 38, 70 (today) | 1 | 0 |
| Normal | 120, 124, 165 | 130, 136, 180 | 2 | 0.6 |
| Bright | 165, 168, 200 | 175, 180, 215 | 2 | 0.8 |

The first proposal (Normal 70, 74, 110 · 80, 86, 130 · 1.5 · 0.3; Bright = today's Normal) was too dark; see Findings → Task 1(b).

**Cave surface colours** (Decision 4), in `MapService`:

| Surface | Where in `MapService` | Old | New |
|---|---|---|---|
| Ground (Slate) | `Ground` part | 18, 18, 26 | 50, 50, 66 |
| Cave floors and paths (Slate) | `Floor` in each plot, `Path_N` | 28, 28, 40 | 70, 70, 92 |
| Hub floor (Slate) | hub `Floor` | 34, 34, 52 | 80, 80, 104 |
| Walls, ceilings, lintels, hub base (Rock) | `ROCK_COLOR` | 46, 44, 58 | 105, 100, 125 |
| Locked pedestals (Slate) | `PEDESTAL_LOCKED_COLOR` | 40, 40, 50 | 80, 80, 95 |

Unlocked pedestals (120, 120, 140), signs and Neon parts stay as they are.

### Stored data

This is the first change to stored data since batch 1. The recommended approach is in Decision 2.

| Change | Purpose |
|---|---|
| `Settings.Brightness: "Dark" \| "Normal" \| "Bright"`, default `"Normal"`, added to the profile template | The player's saved level |
| `Migration.sanitize`: any other value → `"Normal"` | Repairs broken data |

Profiles saved earlier get the field automatically: `profile:Reconcile()` and `Migration.fillMissing` both copy missing template fields, including those inside `Settings`.

### Shared contract

```
-- Config/Lighting.luau (pure data, no requires)
export type Preset = { Ambient: Color3, OutdoorAmbient: Color3, Brightness: number, ExposureCompensation: number }
Lighting.Levels = { "Normal", "Bright", "Dark" }  -- tap order
Lighting.Presets = { Dark = Preset, Normal = Preset, Bright = Preset }
Lighting.Default = "Normal"

-- Net/Remotes.luau (new entry; the remote count goes from 16 to 17)
SetBrightness = { Kind = "Event", Direction = "ToServer", Args = { { kind = "enum", values = { "Dark", "Normal", "Bright" } } } }

-- Client: LightingController
LightingController.apply(level: string)   -- writes the preset to Lighting; ignores unknown names
LightingController.Start()                -- follows Settings.Brightness from StateController

-- Strings/en.luau (new keys)
"Brightness.Dark" = "Dark", "Brightness.Normal" = "Normal", "Brightness.Bright" = "Bright"
```

`Color3` can't be built under Lune (the test runner), so `Config/Lighting.luau` stores colours as `{ r, g, b }` tables (0–255). `LightingController` and `MapService` convert them with `Color3.fromRGB`. The type above is written in that form in the code.

### Files

| File | Change |
|---|---|
| `roblox/src/shared/Config/Lighting.luau` | New: 3 presets, tap order, default |
| `roblox/tests/Config.spec.luau` | New cases: every preset has all 4 fields; colours are whole numbers 0–255; `Default` and every `Levels` entry is a preset; `Levels` names each preset exactly once |
| `roblox/src/shared/Logic/ProfileTemplate.luau` | `Settings.Brightness = "Normal"` |
| `roblox/src/shared/Logic/Migration.luau` | `sanitize`: repair an unknown `Settings.Brightness` |
| `roblox/tests/Profile.spec.luau` (or `Migration.spec`) | Old profile without the field → `"Normal"`; `"Purple"` → `"Normal"` and reported as an issue; `"Dark"` kept |
| `roblox/src/shared/Net/Remotes.luau` | `SetBrightness` entry |
| `roblox/src/server/Services/SettingsService.luau` | New: the `SetBrightness` handler |
| `roblox/src/server/Main.server.luau` | Start `SettingsService` after `DataService` |
| `roblox/src/server/Services/MapService.luau` | `setupLighting` reads the default preset; the 5 lighter surface colours |
| `roblox/src/client/Controllers/LightingController.luau` | New |
| `roblox/src/client/Controllers/BrightnessButton.luau` | New: ScreenGui button, cycle, name label |
| `roblox/src/client/Main.client.luau` | Start both controllers after `StateController` |
| `roblox/src/shared/Strings/en.luau` | The 3 level names |

### Changes to later plans

- **Batch 4:** `SettingsService` already exists, so batch 4 adds its `SetSetting("Music")` handler to it rather than creating the file. The ☀ button moves into the HUD's top-right cluster next to 🔊.
- **Batch 6:** the lighting art pass tunes the presets in `Config/Lighting.luau` instead of `MapService`, and the cave surface colours in `MapService`. If it changes the surfaces, it re-checks all 3 levels.

## Task breakdown and model assignment

| # | Task | Model | Why this model | Depends on |
|---|---|---|---|---|
| 0 | Save this record (approved) | Orchestrator | — | — |
| 1 | **Proof and tuning:** (a) in a 2-player local server, change `Lighting.Ambient` on Player1's client → Player2's and the server's values stay unchanged; (b) screenshots of your cave at each proposed level, in the phone simulator; you pick or adjust the values | Orchestrator + you | Judgment; values are your call | 0 |
| 2 | `Config/Lighting.luau` + `Config.spec` cases | Haiku | Small, fully specified data file and tests | 1 |
| 3 | Template field, `sanitize` repair, migration tests | Orchestrator | Stored data (project rule: data-critical code stays with the orchestrator) | 1 |
| 4 | `SetBrightness` remote, `SettingsService`, `Main.server` order, `MapService` default | Orchestrator | Remote validation and save path | 2, 3 |
| 5 | `LightingController`, `BrightnessButton`, strings, `Main.client` order | DeepSeek Flash | Standard client code against a fixed contract | 2 |
| 6 | Review, StyLua, tests, `rojo build`, Studio and phone checks, record findings and outcome | Orchestrator + you | Review and integration | 2–5 |

Tasks 2 and 3 can run in parallel. Task 5 runs after task 2, and can overlap with task 4.

Escalation: a delegated task that fails review goes back once with the specific defects, then to DeepSeek Pro (task 5) or Sonnet (task 2). **If task 1(a) shows a client's Lighting change reaching other players**, the player setting can't be per-player that way. The plan then shrinks to the developer part only (config + default), and the player button is re-planned.

### Acceptance criteria

- **Task 1:** written findings: the Player2/server values before and after; one screenshot per level; your chosen values.
- **Task 2:** the shared-contract shape exactly; no `require`; the new tests pass.
- **Task 3:** the template default is `"Normal"`; `sanitize` repairs unknown values and reports them; existing tests still pass; the new tests cover the old profile, a broken value and a valid value.
- **Task 4:** `SetBrightness` only accepts the 3 names (anything else → `[Remote] rejected` in Studio); the handler changes only the caller's `Settings.Brightness` and then syncs; `MapService` has no hard-coded Ambient or Brightness numbers left; its 5 surface colours match the "Cave surface colours" table.
- **Task 5:**
  - The button is at least 48 × 48 and respects the top-bar safe area.
  - A tap cycles in `Levels` order, applies at once and fires the remote once.
  - The label shows the level name for 1.5 s.
  - `LightingController` re-applies only when the saved level changes.
  - Unknown names are ignored. Strings come from `Strings.get`.
- **Task 6:** all tests pass (93 existing + the new ones), StyLua is clean, `rojo build` succeeds, and the checks below pass.

## Verification

- **Automated tests** (`lune run tests` from `roblox/`): the new `Config.spec` lighting cases and the migration cases.
- **Backup first:** see Decision 2. Only dev profiles exist; the game isn't live.
- **Studio Play Solo:**
  1. First join → Normal level: the client's `Lighting.Ambient` equals the Normal preset, and the pedestals and walls are visible.
  2. Tap ☀ three times → Bright, Dark, Normal, each applied at once with its name label.
  3. Leave on Bright, Stop, Play → Bright is applied after load.
- **Studio local server, 2 players:** Player1 picks Dark → Player2's screen stays Normal. From Player1's command bar, `Remotes.SetBrightness:FireServer("Purple")` → `[Remote] rejected SetBrightness …`, and nothing is saved.
- **Device Simulator (phone, landscape):** the button is easy to tap and isn't hidden by the Roblox top bar; the label is readable.
- **Published DEV experience, your phone:** pick Bright on the phone → join on PC → Bright is applied there too. Stress mode FPS stays at least 30 at each level.

## Decisions for you before approval

1. **Default level for everyone:** **Normal** (brighter than today). Alternative: keep today's look (Dark) as the default and let players brighten it. **Recommended: Normal**, since the dark default hid the pedestals and avatars in every test.
2. **How to add the saved field:** add `Settings.Brightness` to the **version 1** template without a version bump. The loader already fills missing fields, and only dev test profiles exist, so no backup is needed. Alternative: bump the schema to **version 2** with a migration step and a dev-profile export first. That follows the README's migration rule literally, but it is extra work with no live players. **Recommended: version 1, no bump.** Version bumps start with the first change after launch.
3. **Button now or with the HUD:** build the ☀ button **now**, as its own small screen button, and move it into the HUD in batch 4. Alternative: build only the saved setting and the client controller now, and add the button in batch 4. Until then, players couldn't change it; only you could, through the command bar. **Recommended: now**, so you and your testers can use it from batch 3 on.

## Decisions (confirmed by the user 2026-11-18)

1. **Default level: Normal** (brighter than today). Rejected: keeping today's Dark look as the default.
2. **`Settings.Brightness` is added to the version 1 template with no version bump**, and with no backup (only dev test profiles exist). Rejected: a version 2 migration with a dev-profile export first.
3. **The ☀ button is built now** as its own screen button; batch 4 moves it into the HUD. Rejected: waiting for the batch 4 HUD.
4. **(Confirmed 2026-11-21, after task 1.) The cave surfaces are about 2.5× lighter**, and the presets are the "Chosen values" in Design. Lighting alone couldn't brighten near-black surfaces (Findings → Task 1(b)). Rejected: lighting only with stronger values (walls stay greyish, crystals wash out); time of day per level (excluded in "Not included").

## Progress (2026-11-18)

- **Task 0 done:** this record is approved. It is on branch `cave-brightness` (from `batch-2-core-loop`, which is pushed) and **not committed yet**.
- **Task 1 done (2026-11-21):** the client-only proof passed, and you chose the values, including lighter cave surfaces (Findings; Decision 4). The record was re-approved; still **not committed**.
- **Task 2 done (2026-11-21, Haiku, accepted first time):** [Config/Lighting.luau](../../roblox/src/shared/Config/Lighting.luau) with the chosen values, and 4 `Config.spec` cases. Lighting.luau was added to the "no require" check. The file avoids the word "require" even in comments, because that check searches for the plain word.
- **Task 3 done (2026-11-21, orchestrator):**
  - **Template:** `Settings.Brightness = "Normal"` in the template.
  - **`sanitize`:** an unknown `Brightness` becomes `"Normal"` and is reported as `brightness <value>`. Added beyond the plan: a `Settings` value that isn't a table becomes `{}` (reported as `settings not a table`), so the check can't crash on corrupt data.
  - **Valid names:** `Migration` holds the 3 names itself, because Logic modules may not use `require`.
  - **6 new `Profile.spec` cases:** the default; an old profile through `migrate` (and a v1 profile missing the field through `sanitize`); `"Purple"` and `3` repaired and reported; `"Dark"` kept; a non-table `Settings`; and a check that the names and default match `Config/Lighting`.
- **Tests:** `lune run tests` **103 passed, 0 failed** (93 + 4 + 6). `stylua --check src tests` (Vendor skipped) is clean.
- **Task 5 done (2026-11-21, DeepSeek Flash, accepted first time):**
  - **Files:** [LightingController.luau](../../roblox/src/client/Controllers/LightingController.luau), [BrightnessButton.luau](../../roblox/src/client/Controllers/BrightnessButton.luau), the 3 strings, and the `Main.client` order.
  - **Additions to the contract:**
    - `LightingController.current()` returns the level on screen (the button's starting point).
    - `LightingController.applyFromTap(level)` applies the level and ignores `StateSync` for 1.5 s, so replies to earlier taps don't flicker the screen during fast tapping.
  - **Re-applies** only when the saved level differs from the last applied one.
  - **Review:** the recovery journal was checked and acknowledged. LightingController's hash differed from the journal only by a StyLua line wrap.
  - **To check in Studio:** whether GothamBold draws the "☀" glyph.
- **Task 4 done (2026-11-21, orchestrator):**
  - **Remote:** `SetBrightness` added to [Remotes.luau](../../roblox/src/shared/Net/Remotes.luau); the remote count goes from 16 to 17.
  - **Service:** new [SettingsService.luau](../../roblox/src/server/Services/SettingsService.luau). It sets only the caller's `Settings.Brightness`, then syncs, and skips both when the value is already saved. It starts after `DataService` in `Main.server`.
  - **MapService:** `setupLighting` applies `Presets[Default]`, including `ExposureCompensation`, which the old code never set. It asserts that the default names a preset. The 5 surface colours are now named constants with the new values.
  - **New `Config.spec` case:** the remote's enum names equal the Lighting presets.
- **Tests:** **104 passed, 0 failed** (93 + 11 new). StyLua is clean, and `rojo build` succeeds.
- **Task 6 done (2026-11-21):** every check in Verification passed (Findings → Task 6). The Outcome is below.
- **Committed (2026-11-21):** commit `69d1fd4` on branch `cave-brightness`, pushed, and merged into `batch-1-setup` as PR #2 (`00b0fa6`, same tree). The "not committed" notes above are from before that. Batch 3 branches from `cave-brightness`.
- **Context for a new session**, read before task 1:
  - this record
  - [README.md → Starting a new session](README.md#starting-a-new-session)
  - the batch 2 record's **Studio verification** and **Outcome** sections (the Studio MCP limits found there apply here: Rojo Connect, multi-client tests, the Device Simulator and publishing need you; an unfocused Studio window caps FPS at about 15 and hides ProximityPrompts)
  - the code files in **Files** above, plus `Services/DataService.luau`, `Services/RemoteService.luau` and `Controllers/StateController.luau` for the APIs used
- **Environment:** a Rojo server may still be running from the previous session (port 34872). If `rojo serve` fails with "address in use", reuse it and ask you to click Connect.

## Findings

### Task 1(a): a client's Lighting change stays on that client (2026-11-21): passed

Studio local server with 2 clients, place "Crystal Grove DEV" in Edit mode before the test with no playtest running. Studio's `MapService` source matched the file on disk (16,296 characters), so the server ran today's `setupLighting`. The clients were **Player2** and **Player3**: the first Player1 window disconnected when another client was added, and a third client was then added. Values were read through the Studio MCP in each window.

On **Player2's client only**, all 4 tuned properties were set to the proposed Bright values. The other windows were read after 5 s.

| Where | Before | After the change on Player2 |
|---|---|---|
| Player2 client | Ambient 24, 26, 48 · OutdoorAmbient 34, 38, 70 · Brightness 1 · Exposure 0 | Ambient 120, 124, 165 · OutdoorAmbient 130, 136, 180 · Brightness 2 · Exposure 0.6 |
| Player3 client | Ambient 24, 26, 48 · OutdoorAmbient 34, 38, 70 · Brightness 1 · Exposure 0 | **unchanged** |
| Server | Ambient 24, 26, 48 · OutdoorAmbient 34, 38, 70 · Brightness 1 · Exposure 0 | **unchanged** |

**Result:** a client's Lighting change doesn't reach the server or other players. The per-player brightness setting works as planned; the fallback in "Escalation" isn't needed.

### Task 1(b): screenshots of the proposed levels (2026-11-21)

Play Solo in the Device Simulator: **Samsung Galaxy S25 Ultra, landscape, viewport 685 × 338**, with Studio in front (the touch controls were drawn, so the viewport was redrawing). Same spot for all 3: your character in front of its 3 unlocked pedestals, with a ripe crystal showing "READY!". The values were set on the client through the MCP, 0.5 s before each screenshot.

| Level (proposed values) | What the screenshot shows |
|---|---|
| **Dark** (today) | Near black. Only the crystal, the 3 yellow pedestal rims and "READY!" show; the pedestals and avatar are faint shapes, and the walls can't be seen. |
| **Normal** (70, 74, 110 · 80, 86, 130 · 1.5 · 0.3) | Avatar clearly visible (colours readable), pedestal bodies visible, walls a faint dark-blue outline. Crystal glow unchanged. |
| **Bright** (120, 124, 165 · 130, 136, 180 · 2 · 0.6) | Walls show their texture, pedestals and avatar clear. Still reads as a night cave. Crystal glow and rims look the same as at Normal: the glow isn't visibly "less dramatic" as the Behaviour table expected. |

In all 3, the crystal shows as a white, overexposed shape under Bloom. That's the same at every level, so these presets don't cause it.

**You judged Normal and Bright still too dark** (2026-11-21). The cause, measured on the client in the same Play session:

- **The cave surfaces are near black.** `MapService` colours them Ground 18, 18, 26 (Slate), walls 46, 44, 58 (Rock), and locked pedestals 40, 40, 50 (Slate). On screen, a surface is roughly its own colour scaled by the light that reaches it, so a dark surface stays dark even under strong light.
- **Ceiling test:** with Ambient and OutdoorAmbient at full white (255, 255, 255), Brightness 2 and Exposure 0.6, the walls were only mid-grey and the floor stayed dark. These 4 properties can't make the cave much brighter than that.
- **`Brightness` barely matters at `ClockTime = 0`.** It scales the sun and moon light, and at midnight only the moon is up. The caves have no roof (a ray straight up hits nothing), so `OutdoorAmbient` lights the open areas.
- **Higher exposure helps but costs the glow.** The Bright colours with Exposure **1.5** lifted the walls and pedestals somewhat, but "READY!" and the crystal bloom more.
- Other Lighting at play: `EnvironmentDiffuseScale` 0.3, `GlobalShadows` on, Atmosphere density 0.3 with a grey-blue decay colour, plus Sky, DepthOfField and SunRays effects.

**Preview of lighter cave surfaces** (you asked for it, 2026-11-21). These changes were made on the client only, in the same Play session, with no code change. 132 parts in `Workspace.Map` were recoloured, about 2.5× each:

| Surface | Today | Preview |
|---|---|---|
| Ground (Slate) | 18, 18, 26 | 50, 50, 66 |
| Cave floors and paths (Slate) | 28, 28, 40 | 70, 70, 92 |
| Hub floor (Slate) | 34, 34, 52 | 80, 80, 104 |
| Walls, ceilings, lintels, hub base (Rock) | 46, 44, 58 | 105, 100, 125 |
| Locked pedestals (Slate) | 40, 40, 50 | 80, 80, 95 |
| Unlocked pedestals, signs, Neon parts | unchanged | unchanged |

Screenshots (same spot and phone view; 3 s after each change):

| Lighting | Ambient · OutdoorAmbient · Brightness · Exposure | What it shows |
|---|---|---|
| Today's Dark | 24, 26, 48 · 34, 38, 70 · 1 · 0 | Close to today's look; the walls are now a faint outline. |
| Today's ÷ 2.5 | 10, 10, 19 · 14, 15, 28 · 1 · 0 | Darker than today: the avatar and unlocked pedestals vanish (they weren't recoloured). **Rejected** as Dark. |
| Proposed Normal | 70, 74, 110 · 80, 86, 130 · 1.5 · 0.3 | Walls and floor lighter, but still dim overall. |
| Proposed Bright | 120, 124, 165 · 130, 136, 180 · 2 · 0.6 | Clearly readable: walls, floor, locked pedestals and avatar; crystal glow strong. |
| Stronger Bright | 165, 168, 200 · 175, 180, 215 · 2 · 0.8 | Very readable, floor texture visible; the rims and glow stand out less. |

An A/B check under the proposed Normal (original colours, then lighter) showed the unlocked pedestals look the same either way; only the walls and floor change.

**Your chosen values (approved 2026-11-21):** the lighter surfaces above, with **Dark** = today's lighting, **Normal** = the proposed Bright values, and **Bright** = the stronger Bright values. They're written into Design → "Chosen values" (Decision 4).

### Task 6: Studio Play Solo (2026-11-21)

Rojo connected; all 11 changed scripts had the same length in Studio as on disk. Phone view: Galaxy S25 Ultra, landscape, viewport 685 × 338.

| # | Check | Result |
|---|---|---|
| 1 | First join → Normal; pedestals and walls visible | **Passed.** The client and server Lighting equal the Normal preset (Ambient 120, 124, 165 · Exposure 0.6). The walls (105, 100, 125) and ground (50, 50, 66) have the new colours, and the screenshot shows walls, floor and pedestals. Your existing profile got the field from `Reconcile` with no "Sanitized" warning. 17 remotes, including `SetBrightness`. |
| 2 | Tap ☀ three times → Bright, Dark, Normal, each at once with its name label | **Passed** (you tapped by hand). Each tap changed the cave at once and showed the right name, in order. There was 1 server `StateSync` per tap and no `[Remote] rejected` line. A 4th tap left it on Bright. |
| 3 | Leave on Bright, Stop, Play → Bright after load | **Passed.** After the restart (sessions 17 → 18), the server set its default Normal and the client showed Bright (Ambient 165, 168, 200 · Exposure 0.8). |

**Button:** 52 × 52 points at the top right, below the 58 px top-bar inset and clear of the jump button. GothamBold draws "☀" (screenshot). Output: no errors; only the known `rbxassetid://203785492` warning.

### Task 6: Studio local server, 2 players (2026-11-21)

Server and 2 clients (Player1, Player2, test profiles `Player_-1` and `Player_-2`); both started at Normal with the ☀ button. The calls were sent from Player1's client through the MCP; it's the same call the button makes.

| # | Check | Result |
|---|---|---|
| 1 | Player1 picks Dark → Player2 stays Normal | **Passed.** `SetBrightness:FireServer("Dark")` without a local apply: 3 s later Player1's Lighting was Dark (24, 26, 48 · Exposure 0). So the server saved it, synced it, and `LightingController` followed. Player2 (120, 124, 165 · 0.6) and the server (120, 124, 165 · 0.6) stayed unchanged. |
| 2 | `FireServer("Purple")` → rejected, nothing saved | **Passed.** `[Remote] rejected SetBrightness from Player1: arg 1: not an allowed value` for `"Purple"` and for `3`; `… arg 1: missing` for no argument. Player1 stayed Dark, and no `StateSync` followed. |

### Task 6: Device Simulator, phone landscape (2026-11-21)

Galaxy S25 Ultra, landscape, viewport 685 × 338, in the Play Solo run above.

- **The button isn't hidden by the top bar: passed.** The screenshot shows it below the 58 px top-bar inset, at the top right, clear of the jump button.
- **Easy to tap, label readable: passed.** You tapped it by hand 4 times and confirmed it was "easy to tap and readable".

### Task 6: published DEV experience, your phone (2026-11-21)

**First attempt: not valid.** The phone showed the old version: no ☀ button and the old dark cave. Your DEV profile wasn't touched either (read-only DataStore read: `Brightness = "Bright"`, `Sessions = 18`, no session lock, last write = the earlier Studio Play). Even the old code loads and saves the profile on join, so the phone most likely wasn't in "Crystal Grove DEV" with your Studio account. The first publish probably didn't go through: the 2-player test session was still open at the time. Its stress readings (58, 57, 58) don't count for this change.

**Second attempt:** you ended the test session, published again, fully closed the app and joined through the DEV place link (`roblox.com/games/138038244823412`). The phone shows the ☀ button and the lighter cave.

- **Profile-loaded level: passed.** A DEV server held your profile's lock and the join count rose (18 → 23), so the phone loaded your real profile. Its saved level was Bright, and the first tap's label said **Dark**, the next step after Bright. So the phone started at the saved Bright, not the Normal default.
- **Stress mode FPS: passed** (your readings). Lowest: **Dark 58, Normal 57, Bright 58** (target ≥ 30). They're identical to the invalid first attempt's numbers.
- **Saved level across devices: failed, cause unknown.** You finished on Dark. While the phone was still in the game, two reads 30 s apart showed `Brightness = "Bright"`, the lock held, and the last save 109–149 s earlier. That was expected: a tap changes only the server's copy, and ProfileStore writes it every few minutes and when you leave. After you left the game and closed the app, the lock was released and the profile saved, but with `Brightness = "Bright"` and **`Sessions = 26`**: one more join than the 25 seen while you were still on the phone. The DataStore's version list (one version per stretch of time) shows no version with Dark.
  - **What still works:** the save path in Studio. The stored Bright came from Studio taps and survived Stop and Play.
  - **Possible causes, not yet checked:** the published server didn't accept the Dark taps; or session 25 ended without saving them before session 26 loaded the profile. The server log can't show which: `[Remote] rejected` prints only in Studio, and that server has shut down.
- **Clean repeat: passed.** One join, one tap (label "Dark"), leave at once, close the app. The profile read showed **`Brightness = "Dark"`, `Sessions = 27`**, lock released, saved 31 s earlier. Then a PC join (Studio Play, sessions 28) loaded **Dark** on the client (Ambient 24, 26, 48 · Exposure 0) while the server had its Normal default. So the published server saves the choice, and it applies on another device. The failed run came from the extra session 26 that loaded your profile between the Dark taps and leaving. How that session interacted with the save isn't known.

**Lesson:** end every test session before publishing. Then check File → Version History and join from the DEV link; the ☀ button and lighter cave confirm the new version.

## Outcome (2026-11-21)

- **Built as specified**, with these differences:
  - **Values and lighter surfaces.** The values come from task 1, not the first proposal. The cave surfaces are about 2.5× lighter (Decision 4): lighting alone couldn't brighten near-black surfaces. Batch 6's art pass now tunes these colours too.
  - **Two client helpers** beyond the contract: `LightingController.current()` and `applyFromTap()`. The latter ignores `StateSync` for 1.5 s after a tap, so fast tapping doesn't flicker.
  - **`sanitize` also repairs a `Settings` value that isn't a table.**
  - **`MapService` now also sets `ExposureCompensation`**; the old code left it at the engine default.
  - **One extra test** checks that the `SetBrightness` enum names equal the Lighting presets.
- **Who did what:**
  - **Haiku:** task 2, accepted first time.
  - **DeepSeek Flash:** task 5, accepted first time. The recovery journal was checked and acknowledged.
  - **Orchestrator:** tasks 1, 3, 4 and 6.
  - Nothing went to DeepSeek Pro or Sonnet.
- **Tests:** `lune run tests` gives **104 passed, 0 failed** (93 existing + 11 new). `stylua --check` is clean (Vendor skipped), and `rojo build` succeeds.
- **Each place checked** (details in Findings → Task 6):

  | Where | What | Result |
  |---|---|---|
  | Studio Play Solo | First join Normal; 3 taps cycle with labels; Bright kept after Stop and Play | All 3 passed |
  | Studio local server, 2 players | Player1 Dark, Player2 stays Normal; `"Purple"`, `3` and a missing argument rejected | All passed |
  | Device Simulator (phone, landscape) | Button clear of the top bar, easy to tap, label readable | Passed (screenshot + your taps) |
  | Published DEV experience, your phone | Saved level loads on join; stress FPS at each level; phone → PC | Passed. FPS 58 / 57 / 58 (your readings). Dark saved on the phone was loaded on PC (Studio Play), after one clean repeat. |

- **Not verified:**
  - **Why the first phone → PC run saved Bright.** An extra session (26) loaded your profile between the Dark taps and leaving. The clean repeat passed, so the cause was that extra session, not the save code. How the extra session dropped the Dark change wasn't investigated.
  - **"PC join" was a Studio Play** in the DEV universe with your profile, not the Roblox app on PC. It loads the same DataStore and code.
  - **The FPS readings are yours,** and they're identical to the first, invalid attempt (old version).
- **Leftovers:**
  - **Dev data:** your profile is saved on **Dark** with 28 sessions. The test profiles `Player_-1` (Dark) and `Player_-2` were used.
  - **The DEV experience is published with this change.**
  - **The Rojo server** started in this session is still running.
  - **The Studio Device Simulator** is still on (Galaxy S25 Ultra).
  - **The `rojo build` output** is outside the repo, in the temp folder.
- **Lessons:**
  - **Before publishing,** end every test session (an open 2-player session most likely blocked the first publish). Check File → Version History, then join from the DEV link. The ☀ button and lighter cave confirm the new version.
  - **For a save check on the phone,** use one join and leave straight away; extra joins in between hide the result.
