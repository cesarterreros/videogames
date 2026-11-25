# Specification: Batch 1, project setup and core data architecture

Status: approved 2026-11-18. Verified in Studio Play Solo on the dev experience 2026-11-18; the open 2-player, `[Remote] rejected` and phone session-lock checks passed in batch 2's verification (see its Outcome).

## Summary

- **What:** the project skeleton: Rojo project, player profiles with session locking (ProfileStore), all remotes behind the security layer, balance numbers in config, Lune unit tests. No gameplay.
- **Result:** done 2026-11-18. **64 tests pass.** In Play Solo the profile saved and reloaded (sessions 1 → 2 → 3), and bad or spammed remote calls changed no data.
- **Correction found:** Studio without API access warns instead of kicking.
- **Closed later:** the 2-player, `[Remote] rejected` and phone session-lock checks passed in batch 2.

## Context

This is the first of the six implementation batches. It follows the approved [architecture](2026-11-18-crystal-grove-architecture.md), [MVP](2026-11-18-crystal-grove-mvp.md) and [monetization](2026-11-18-crystal-grove-monetization.md) specs. The repository has no code yet: [roblox/](../../roblox/) is empty.

**Goal:** a project that syncs into Studio, loads and saves each player's profile safely with session locking, creates every remote behind the security layer, holds all balance numbers in config, and has passing unit tests. There is no gameplay yet. The visible result is a profile that loads, counts your sessions, and survives a rejoin.

## Behaviour

What you can see when this batch is done:

- **Terminal:** `lune run tests` from `roblox/` prints each test file with ✓ or ✗ and a total, for example `47 passed, 0 failed`. It exits with code 1 if anything fails.
- **Studio Play Solo (dev experience, API access on):**
  - The Output shows `[Data] Loaded Player_<UserId> v1 sessions=1`.
  - The client Output shows `[State] coins=0 sessions=1 seeds={Quartz=1}`.
  - Stop and play again: `sessions=2`. The number goes up on every join, which proves saving works.
- **Studio with API access off, or a DataStore failure:** the player is kicked with the `Error.DataLoad` text ("Couldn't load your cave. Please rejoin in a minute."), and nothing is saved.
- **A remote fired with bad arguments** (from the client command bar): nothing happens to the data. The server Output shows `[Remote] rejected <name> from <player>: <reason>` (Studio only; in live servers it is silent).
- **Players see nothing new in the 3D world.** The map comes in batch 2.

### Edge cases

- **Player leaves while their profile is loading:** the session is ended and released, and no data is written.
- **Profile from a future version** (`Version > 1`): sanitize clamps fields, but the version number is kept and the player keeps playing. This can't happen in v1 and is logged if it does.
- **Corrupt fields** (negative coins, an unknown seed ID in the bag, pedestal keys outside 1–13): `sanitize` fixes them and returns a list of issues, which is logged as an `Anomaly`.

## Not included

- **The map, plots, planting, growing, shattering, crystal rendering:** batch 2.
- **Shop, upgrades, codex, streak, goals, leaderboard, friend bonus, surge:** batch 3.
- **All UI, the tutorial and sounds:** batch 4. Batch 1 has only Output prints.
- **Passes, products, receipts and ads:** batch 5. The `Monetization` config holds placeholder IDs of `0`.
- **The admin command, polish and the launch checklist:** batch 6.
- **Handlers for gameplay remotes.** The remotes are created and protected, but they have no handler yet, so every call is dropped as "no handler".
- **Analytics events other than `Anomaly`.** The wrapper is built, but the other events are wired in later batches.

## Design

Stored data: **the profile schema version 1 is created** exactly as in the architecture spec. There is no earlier data, so nothing needs migrating.

### Shared contract (fixed before parallel work)

```lua
-- Config (pure tables, NO requires). Colours are hex strings ("#8E44AD") so Lune can load them.
Config.Seeds = { { Id: string, Tier: number, Rarity: "Common"|"Uncommon"|"Rare"|"Epic"|"Legendary",
                   Price: number, GrowSeconds: number, BaseValue: number, BaseCarats: number,
                   ColorHex: string }, ... }          -- exactly the 10 rows of the MVP table, Tier 1..10
Config.Rolls = {
  Size = { {Name="Normal",Min=1.0,Max=1.4,Chance=0.88}, {Name="Big",Min=1.4,Max=2.0,Chance=0.10},
           {Name="Huge",Min=2.0,Max=4.0,Chance=0.018}, {Name="Colossal",Min=4.0,Max=8.0,Chance=0.002} },
  Mutation = { {Name="Glowing",Mult=2,Chance=0.06}, {Name="Molten",Mult=5,Chance=0.012},
               {Name="Prismatic",Mult=20,Chance=0.0015} },   -- "None" is the remainder
  Overgrowth = { PerHour = 0.10, Cap = 0.50 },
}
Config.Economy = { StartPedestals=3, MaxCoinPedestals=10, PassPedestals=3,
  PedestalCosts = { [4]=100,[5]=500,[6]=2000,[7]=8000,[8]=30000,[9]=120000,[10]=500000 },
  LampCosts = { 1000, 10000, 100000, 1000000, 5000000 }, LampStep = 0.05,
  FriendBonusPer = 0.10, FriendBonusCap = 0.30, SurgeMinutes = 5, SurgeMutationMult = 2 }
Config.Progression = {
  Streak = { {Coins=100},{Coins=250},{Seed="Citrine",Count=1},{Coins=1000},{Coins=2500},{Coins=5000},{Seed="Emerald",Count=1} },
  GoalPool = { {Id="Shatter20",Target=20},{Id="PlantUncommon5",Target=5},{Id="FindMutation",Target=1},
               {Id="Earn5000",Target=5000},{Id="BuyUpgrade",Target=1},{Id="ShatterBig",Target=1} },
  GoalsPerDay = 3, CodexBonus = 0.10,
  Tutorial = { GrowSeconds = 8, BonusCoins = 50, GuaranteedGlowingOnShatter = 3 } }
Config.Monetization = {
  Passes = { FastGrow={Id=0,DefaultPrice=249,GrowMult=0.5}, DoubleCoins={Id=0,DefaultPrice=199},
             ExtraPedestals={Id=0,DefaultPrice=149}, AutoShatter={Id=0,DefaultPrice=299},
             VIP={Id=0,DefaultPrice=99} },
  Products = { InstantGrowS={Id=0,DefaultPrice=9,MaxSeconds=900}, InstantGrowM={Id=0,DefaultPrice=29,MaxSeconds=7200},
               InstantGrowL={Id=0,DefaultPrice=59}, GrowAll={Id=0,DefaultPrice=99},
               LuckBoost={Id=0,DefaultPrice=25}, CoinPouchS={Id=0,DefaultPrice=19,Mult=5},
               CoinPouchM={Id=0,DefaultPrice=99,Mult=30}, CoinPouchL={Id=0,DefaultPrice=249,Mult=100},
               SeedBundle={Id=0,DefaultPrice=39,Count=3}, StarterPack={Id=0,DefaultPrice=49} },
  Ads = { CooldownSeconds=60, DailyTotal=9, Caps = { FinishNow=5, Luck=3, CoinPouch=1 } },
  LuckBoost = { Minutes=15, MaxBankMinutes=60, Mult=2, MaxTotalMult=3 },
  ReceiptHistory = 100 }
Config.Game = { MaxPlayers=6, PlotCount=6, MaxPedestals=13,
  ProfileStoreName="PlayerData", ProfileKeyPrefix="Player_",
  LeaderboardStorePrefix="BiggestCrystal_", LeaderboardRefreshSeconds=120, LeaderboardFlushSeconds=30,
  RemoteDefaultRate=8, RemoteDefaultBurst=12, AnomalyThresholdPerMinute=50 }

-- Logic (pure, NO requires; config passed in where needed)
WeekId.fromUnix(t: number): string            -- ISO-8601 week, UTC: "2026W47"; 2027-01-01 -> "2026W53"
WeekId.dateString(t: number): string          -- UTC "YYYY-MM-DD"
Format.compact(n: number): string             -- 999 -> "999", 12400 -> "12.4K", 3100000 -> "3.1M", 2.5e9 -> "2.5B", 1e12 -> "1T"
Format.carats(x: number): string              -- 14.234 -> "14.2 ct"
Format.interpolate(template: string, params: {[string]: any}?): string   -- "{coins} coins" ; unknown {x} left as-is
RateLimiter.new(rate: number, burst: number) -> limiter
limiter:allow(key: any, now: number): boolean -- token bucket per key; now injected for tests
limiter:forget(key: any)                       -- called on PlayerRemoving
Validate.check(schema: {ArgSpec}, args: {any}, n: number): (boolean, string?)
  -- ArgSpec = {kind="int",min,max} | {kind="number",min,max} | {kind="bool"} | {kind="enum",values={...}}
  --         | {kind="string",maxLen}; n = select("#", ...) so extra args are rejected;
  --         NaN/inf rejected; optional = true allows nil
ProfileTemplate.VERSION = 1
ProfileTemplate.new(): table                  -- fresh deep copy of the schema in the architecture spec
Migration.migrate(data: table, template: table): table      -- v0/missing Version -> 1; no-op at 1
Migration.sanitize(data: table, config: {seedIds: {[string]: true}, maxPedestals: number, maxLamp: number, maxTier: number}): (table, {string})

-- Net/Remotes.luau (pure table)
Remotes = { [name] = { Kind="Event"|"Function", Direction="ToServer"|"ToClient",
                       Rate: number?, Burst: number?, Args: {ArgSpec}? } }
  -- every remote in the architecture table; seed IDs use {kind="enum", valuesFrom="SeedIds"}
  -- which RemoteService resolves from Config.Seeds at Init

-- Server services
DataService:GetProfile(player): Profile?      -- nil until loaded
DataService:GetData(player): table?
DataService.ProfileLoaded: signal (player, data)   -- simple BindableEvent wrapper
DataService:Save(player)                      -- used by receipts in batch 5
RemoteService:On(name, handler(player, ...))  -- registers a validated, rate-limited handler
RemoteService:Fire(name, player, ...)         -- server → one client
RemoteService:FireAll(name, ...)
Analytics:Custom(player, name, value?, fields?)  -- wraps LogCustomEvent in pcall
```

### Files

| File (under `roblox/` unless rooted) | Roblox location | Change |
|---|---|---|
| `/.gitignore` | — | New: `*.rbxl*` lock files, `roblox/*.rbxl`, `roblox/*.rbxlx`, `sourcemap.json` |
| `rokit.toml` | — | New: rojo, lune, stylua pinned at the versions installed in task 1 |
| `default.project.json` | — | New: `src/shared` → ReplicatedStorage.Shared; `src/server` → ServerScriptService.Server; `src/client` → StarterPlayer.StarterPlayerScripts.Client |
| `stylua.toml` | — | New: tabs, 120 columns |
| `tests/run.luau`, `tests/lib/expect.luau` | — | New: Lune runner and assertions |
| `src/shared/Config/Seeds.luau`, `Rolls.luau`, `Economy.luau`, `Progression.luau`, `Monetization.luau`, `Game.luau` | ReplicatedStorage.Shared.Config | New, per the contract |
| `src/shared/Logic/WeekId.luau`, `Format.luau` | …Shared.Logic | New |
| `src/shared/Logic/RateLimiter.luau`, `Validate.luau` | …Shared.Logic | New |
| `src/shared/Logic/ProfileTemplate.luau`, `Migration.luau` | …Shared.Logic | New |
| `src/shared/Strings/en.luau`, `Strings.luau` | …Shared.Strings | New: keys for batch 1 (`Error.DataLoad`, `Loading.Cave`) plus a `get(key, params)` lookup that falls back to the key itself |
| `src/shared/Net/Remotes.luau` | …Shared.Net | New: all 16 remotes from the architecture table |
| `src/server/Vendor/ProfileStore.luau`, `Vendor/LICENSE` | ServerScriptService.Server.Vendor | Copied from the official MadStudioRoblox repository at a fixed commit (recorded in task 1 findings) |
| `src/server/Services/DataService.luau` | …Server.Services | New |
| `src/server/Services/RemoteService.luau` | …Server.Services | New |
| `src/server/Services/Analytics.luau` | …Server.Services | New |
| `src/server/Main.server.luau` | ServerScriptService.Server (Script) | New: Init then Start: Analytics → Remote → Data |
| `src/client/Main.client.luau`, `Controllers/StateController.luau` | StarterPlayerScripts.Client | New: waits for remotes, logs `StateSync` snapshots |
| `tests/Config.spec.luau`, `WeekId.spec.luau`, `Format.spec.luau`, `RateLimiter.spec.luau`, `Validate.spec.luau`, `Profile.spec.luau` | — | New tests (see Verification) |

**Properties to set in Studio** (you do these; Rojo doesn't sync them):
- Game Settings → Security → **Enable Studio Access to API Services** = on, in the **dev experience only**.
- Players → **MaxPlayers** = 6. This is set per place in the Creator Dashboard (Places → Server Size), and `Config.Game.MaxPlayers` must match it.

## Task breakdown and model assignment

| # | Task | Model | Why this model | Depends on |
|---|---|---|---|---|
| 0 | Save this record and the architecture record | Orchestrator | — | — |
| 1 | **Proofs:** (a) install Rokit and add rojo, lune and stylua, then record the versions; (b) you install the Rojo Studio plugin and connect `rojo serve` to an empty place; (c) download ProfileStore from the official repository, confirm the Apache-2.0 LICENSE, and **check the real API names** (`New`, `StartSessionAsync`, `Reconcile`, `EndSession`, `OnSessionEnd`, `Save`, `.Data`, `.Mock`) against its docs; (d) you create the **dev experience** and enable Studio API access; (e) `ping()` the DeepSeek server | Orchestrator + you (b, d) | Tool installs and external checks need judgment | 0 |
| 2 | `.gitignore`, `rokit.toml`, `default.project.json`, `stylua.toml` | Haiku | Small, fully specified files | 1 |
| 3 | `tests/run.luau`, `tests/lib/expect.luau` | DeepSeek Flash | Standard code against the Lune API | 1 |
| 4 | `Config/Seeds`, `Config/Rolls`, `Config/Economy` + `tests/Config.spec.luau` (part 1) | DeepSeek Flash | Data entry from the contract | 3 |
| 5 | `Config/Progression`, `Config/Monetization`, `Config/Game` + `Config.spec` (part 2) | DeepSeek Flash | Same | 4 |
| 6 | `Logic/WeekId`, `Logic/Format` + their specs | DeepSeek Flash | Pure functions with exact examples | 3 |
| 7 | `Logic/RateLimiter`, `Logic/Validate` + their specs | Orchestrator | Security-critical (project rule) | 3 |
| 8 | `Logic/ProfileTemplate`, `Logic/Migration` + `Profile.spec` | Orchestrator | Stored-data schema (project rule) | 5 |
| 9 | `Strings/en`, `Strings/Strings`, `Net/Remotes` | Haiku | Tables fully given by the contract | 1 |
| 10 | `Services/Analytics` | DeepSeek Flash | Thin wrapper | 1 |
| 11 | `Vendor/ProfileStore` + LICENSE, `Services/DataService`, `Services/RemoteService`, `Main.server` | Orchestrator | Session locking and remote security (project rule) | 1c, 7, 8, 9, 10 |
| 12 | `Main.client`, `Controllers/StateController` | Haiku | Small, fully specified | 9 |
| 13 | Review every diff, `stylua --check`, `lune run tests`, the Studio checks with you, write the findings | Orchestrator | Review and integration | 2–12 |

Tasks 2, 3, 9, 10 can run in parallel after task 1. Tasks 4–8 follow task 3, since they need the test runner.

Escalation:
- A delegated task that fails review goes back once with the specific defects, then to DeepSeek Pro (or Sonnet for Haiku tasks), or the orchestrator fixes it if the fix is small.
- **If proof 1(c) shows ProfileStore's API differs**, DataService is written against the real API and the differences are recorded in the findings. If ProfileStore is unavailable or the license isn't Apache-2.0, stop and ask you before writing our own session lock.
- **If the DeepSeek server is unavailable (1e)**, Sonnet subagents take its tasks.

### Acceptance criteria

- **Task 2:** `rojo build -o test.rbxlx` succeeds (the orchestrator runs it); the paths match the table.
- **Task 3:** `lune run tests` with one dummy spec prints ✓ and exits 0; with a failing spec it prints ✗ with the message and exits 1. Spec files are found automatically.
- **Tasks 4–5:** the config values equal the approved specs exactly. `Config.spec` checks: 10 seeds with tiers 1–10, ascending price, grow time and value; size chances add up to 1 (±1e-9); mutation chances are below 1; all 13 product and pass entries exist; every `ColorHex` matches `^#%x%x%x%x%x%x$`. No file contains `require`.
- **Task 6:** all `Format` and `WeekId` examples from the contract pass, plus the year boundaries 2026-12-28 → 2026W53, 2027-01-04 → 2027W01, and 2024-12-30 → 2025W01.
- **Task 7:** the rate limiter allows a burst of 12, then refuses, and refills at 8 per second (simulated `now`); `Validate` rejects a wrong type, a float for an int, out-of-range values, NaN, inf, extra arguments, unknown enum values and over-long strings, and accepts valid calls and missing optional arguments.
- **Task 8:** `new()` returns independent copies (changing one doesn't change another); `migrate({})` returns a valid v1 profile; `sanitize` fixes negative coins, unknown seed IDs, pedestal key "14" and lamp level 9, and reports each one.
- **Task 9:** `Remotes.luau` lists all 16 remotes with the kind, direction and arguments from the architecture table. Strings contain the 2 keys.
- **Task 10:** every call is in `pcall`; there are no other analytics calls.
- **Task 11:** DataService follows the join flow from the architecture spec, kicks the player on load failure, releases the session on leave, and increments `Sessions` and sets `LastJoinAt` on each load. RemoteService creates every remote, and its wrapper does profile check → rate limit → validate → pcall. Rejections are counted and logged as `Anomaly` above 50 per minute. `InvokeClient` is never used.
- **Task 12:** the client logs each `StateSync` and never sends anything in batch 1.
- **Task 13:** all tests pass, `stylua --check src tests` is clean, and the checks below pass.

## Verification

- **Automated tests** (`lune run tests` from `roblox/`): `Config.spec`, `WeekId.spec`, `Format.spec`, `RateLimiter.spec`, `Validate.spec` and `Profile.spec`. The expected total is recorded in the Outcome; there were 0 tests before.
- **Backup first:** not needed. There is no stored data yet.
- **Studio Play Solo (dev experience):** play → `[Data] Loaded … sessions=1` and `[State] coins=0 sessions=1 seeds={Quartz=1}`. Stop, play again → `sessions=2`. No errors in Output.
- **Studio with API access off:** play → kicked with the `Error.DataLoad` text, and no write is attempted.
- **Studio 2-player local server:** both players load separate profiles. From player 1's client command bar, `game.ReplicatedStorage.Remotes.Plant:FireServer("x", 99)` → the server logs a rejection, and player 1's data is unchanged. 100 rapid calls → rate-limit rejections, and the server keeps running.
- **Device emulator / real phone:** not needed. There is no UI or world content in this batch.
- **Session lock (published dev experience):** join on PC; then join the same account on your phone. Roblox disconnects the PC session, and the phone loads with `sessions` exactly one higher. Nothing is lost and nothing is duplicated.

## Decisions for you before approval

1. **Start the build in the Studio Output**, with no UI until batch 4. Alternative: a temporary debug label for coins, which would be thrown away later. **Recommended: Output only.**
2. **You do tasks 1(b) and 1(d)** in Studio and the Creator Dashboard, and I run everything else. Tell me if you'd rather I write step-by-step instructions for every Studio step.

## Decisions (confirmed by the user 2026-11-18)

1. **Batch 1 is checked through the Output window only.** Rejected: a temporary debug coin label.
2. **You do tasks 1(b) and 1(d)** (Rojo Studio plugin connection, dev experience with API access); the orchestrator does the rest.

## Task 1 findings (2026-11-18)

- **1(a) Toolchain:** Rokit 1.2.0 installed from the official release (`~/.rokit/bin`). `roblox/rokit.toml` pins **Rojo 7.7.1, Lune 0.11.1, StyLua 2.6.0** (each marked trusted with `rokit trust`).
- **1(b) Rojo plugin:** `rojo plugin install` failed because **Roblox Studio is not installed** on this PC (no `%LOCALAPPDATA%\Roblox`). Open for you: install Studio, then run `rojo plugin install` from `roblox/`.
- **1(c) ProfileStore:** copied from `MadStudioRoblox/ProfileStore` at commit `45c9847cbcf1fc260369c50eb335aba7c35aecdd` (2025-07-31) into `roblox/src/server/Vendor/`, with its Apache-2.0 LICENSE. API confirmed in the source: `ProfileStore.New(name, template)`, `store:StartSessionAsync(key, {Steal?, Cancel?})` → `Profile?`, `profile:Reconcile()`, `profile:EndSession()`, `profile:Save()` (**does not yield**; it spawns the save), `profile:AddUserId()`, `profile.Data`, `profile.LastSavedData`, `profile.OnSessionEnd`, `profile.OnAfterSave`, `store.Mock`, `ProfileStore.DataStoreState`.
- **1(d) Dev experience:** open for you (needs Studio).
- **1(e) DeepSeek:** `ping` OK (v0.1.0, Flash and Pro configured).

**Corrections to the design above:**

1. **Studio without API access does not fail.** ProfileStore detects it and keeps data **in memory only**, printing "data will not be saved". DataService will log `[Data] Studio has no DataStore access – data will not be saved` instead of kicking. The kick happens only when `StartSessionAsync` returns `nil`. The Verification check "Studio with API access off → kicked" becomes "→ warning printed, play continues, nothing persists".
2. **Receipt saves (batch 5):** `Save()` doesn't yield, so ProcessReceipt must wait for `OnAfterSave` (with a timeout) and check that `LastSavedData` contains the PurchaseId before returning `PurchaseGranted`. This is recorded here for batch 5.
3. **The Cancel parameter is used:** `StartSessionAsync` gets `Cancel = function() return player.Parent ~= Players end`, so a player who leaves during loading stops the load.

## Progress (2026-11-18)

**Code for tasks 2–12 is written and reviewed. The Studio checks (task 13) are blocked until you install Roblox Studio (finding 1(b)).**

| Task | Files | Written by | Review |
|---|---|---|---|
| 2 | `.gitignore`, `default.project.json`, `stylua.toml` | Haiku | Accepted first time |
| 3 | `tests/run.luau`, `tests/lib/expect.luau`, `tests/Smoke.spec.luau` | DeepSeek Flash (**cut off** at 50 turns) | Orchestrator fixed 2 defects: added `tests/init.luau` (`require("@self/run")`) so `lune run tests` works, and changed `expect` methods from dot to colon style |
| 4 | `Config/Seeds`, `Rolls`, `Economy`, `tests/Config.spec.luau` | DeepSeek Flash | Accepted first time |
| 5 | `Config/Progression`, `Monetization`, `Game`, extended `Config.spec` | DeepSeek Flash | Accepted first time |
| 6 | `Logic/WeekId`, `Logic/Format` + specs | DeepSeek Flash | Orchestrator fixed `interpolate` placeholders to allow `_` (contract said `[%w_]+`) and added a test |
| 7 | `Logic/RateLimiter`, `Logic/Validate` + specs | Orchestrator | — |
| 8 | `Logic/ProfileTemplate`, `Logic/Migration`, `tests/Profile.spec.luau` | Orchestrator | — |
| 9 | `Strings/en`, `Strings/Strings`, `Net/Remotes` | Haiku | Accepted first time (16 remotes) |
| 10 | `Services/Analytics` | DeepSeek Flash | Accepted first time |
| 11 | `Vendor/ProfileStore` + LICENSE, `Services/DataService`, `Services/RemoteService`, `Main.server` | Orchestrator | Self-review fixed an ambiguous-call parse (`assert(...)` followed by a line starting with `(`) |
| 12 | `Main.client`, `Controllers/StateController` | Haiku | Accepted first time |

**Small additions beyond the contract:**
- `Migration.sanitize` config takes optional `startPedestals` and `maxCoinPedestals` (defaults 3 and 10).
- `ProfileTemplate.deepCopy` is exported.
- The StateSync snapshot leaves out `Monetization.ProcessedReceipts` and every crystal's `SizeRoll`, so sizes stay secret.

**Checks run:**
- `lune run tests`: **64 passed, 0 failed** (0 before this batch).
- `stylua --check`: clean.
- `rojo build`: succeeds.

**Still open (task 13):**
- Install Studio and run `rojo plugin install`.
- Create the dev experience and turn on API access.
- Studio Play Solo: `sessions=1`, then `sessions=2` after a rejoin.
- With API access off: a warning is printed and nothing is saved.
- 2-player bad-argument and spam checks.
- Phone session-lock check.

## Outcome (2026-11-18)

- **Built as specified**, with the corrections in the task 1 findings (Studio without API access warns instead of kicking) and the small contract additions listed under Progress.
- **Who did what:** see the Progress table. In short, DeepSeek Flash wrote 5 jobs: one was cut off and finished by the orchestrator, one had a small drift fixed in review. Haiku wrote 3 jobs, all accepted first time. The orchestrator wrote the security- and data-critical modules.
- **Tests:** `lune run tests` gives **64 passed, 0 failed** (0 existing + 64 new). `stylua --check` is clean, and `rojo build` succeeds.
- **Studio Play Solo, dev experience "Crystal Grove DEV" (you ran it):**

  | Check | Result |
  |---|---|
  | First Play | `[Server] Started 3 services`, `[ProfileStore]: Roblox API services available - data will be saved`, `[Data] Loaded Player_… v1 sessions=1`, `[State] coins=0 sessions=1 seeds={Quartz=1}` |
  | Second Play | `sessions=2` on the server and client lines. **Save and reload proven.** |
  | After the bad-argument and 100-call spam tests, Play again | `sessions=3`, `coins=0`, seeds unchanged. **The fake calls changed no data.** |

  The orange `ContentId: rbxassetid://203785492 failed … Asset type does not match` line comes from Studio itself (its source is "Studio"), not our code.
- **Not verified:**
  - The `[Remote] rejected …` log lines from tests 1 and 2: you reported them working, but the Output was cleared before the screenshot.
  - The **2-player local server** check (separate profiles; cross-player rejection).
  - The **phone session-lock** check (PC session, then the same account on the phone).
  - "Studio with API access off": not run.
- **Known limits:** no gameplay remote has a handler yet, so every client request is rejected ("no handler"), as planned.
- **Leftovers:** the Rojo server is running from this session; the `rokit-dl`, `lunetest` and `test.rbxlx` scratch files are in the session scratchpad, outside the repo. Nothing temporary is in the repo.
- **Noticed, not changed:** Rokit's self-install may not have added `%USERPROFILE%\.rokit\bin` to PATH for new terminals. Not checked yet.
