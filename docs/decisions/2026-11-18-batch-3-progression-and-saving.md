# Specification: Batch 3, progression and saving (shop, upgrades, unlocks, codex, daily, social, leaderboard)

Status: approved 2026-11-18. Implemented and verified 2026-11-21; committed as `c0d07d3` on branch `batch-3-progression` (pushed) and opened as a pull request into `batch-1-setup`.

## Summary

- **What:** progression and retention: seed shop and tier unlocks, pedestal and Growth Lamp upgrades, Crystal Codex, 7-day streak and daily goals, friend bonus, rare-find announcements, the hourly Crystal Surge, and the weekly Biggest Crystal board in the hub.
- **Decided:** the Surprise Seed is the next tier (not random); goal rewards scale with your highest seed; the Growth Lamp affects only new plantings; leaderboard writes are budget-checked, reads aren't.
- **Result:** done 2026-11-21. **154 tests pass.** Checked in Play Solo, a 2-player server, the Device Simulator and on the published DEV experience.
- **Lesson:** `BindableEvent` arguments are copies; change profiles only through `DataService:GetData`.

## Context

After batch 2 ([record](2026-11-18-batch-2-core-gameplay-loop.md)), players can plant, grow and shatter crystals in their own cave, but coins have nothing to buy and there is no reason to come back tomorrow. This batch adds the **progression and retention systems** from the [MVP spec](2026-11-18-crystal-grove-mvp.md) ("Player progression" and "Retention hooks"):
- the seed shop and seed-tier unlocks,
- the pedestal and Growth Lamp upgrades,
- the Crystal Codex,
- the 7-day streak and daily goals,
- the friend bonus and server announcements of rare finds,
- the hourly Crystal Surge,
- the global weekly **Biggest Crystal** leaderboard with its board in the hub.

It follows the [architecture](2026-11-18-crystal-grove-architecture.md), build order item 9.

**Screen UI still waits for batch 4.** In this batch every action is tested by firing remotes from Studio's command bar, and the client prints `Toast` and `Announce` messages to the Output.

### Context for a new session (read before task 1)

1. [README.md](README.md), especially **Starting a new session** and **Delegation lessons**.
2. This record.
3. The [batch 2 record](2026-11-18-batch-2-core-gameplay-loop.md): its **shared contract** (map names, pedestal attributes, `Growth`/`Rolls` signatures, the `ShatterResult` payload) and its Findings and Outcome sections.
4. The [MVP spec](2026-11-18-crystal-grove-mvp.md): the sections "Seeds", "Player progression", "Retention hooks", "Analytics events" and the Decisions.
5. The [architecture spec](2026-11-18-crystal-grove-architecture.md): "Data architecture" (the leaderboard part), "Remote security rules", "Analytics events".
6. **Code to read:**
   - `roblox/src/server/Services/CrystalService.luau` (changed here), `DataService.luau`, `RemoteService.luau`, `Analytics.luau`, `MapService.luau`, `PlotService.luau`
   - `roblox/src/shared/Config/*.luau`, `roblox/src/shared/Logic/WeekId.luau`, `Format.luau`, `Growth.luau`, `Rolls.luau`
   - `roblox/src/shared/Net/Remotes.luau`, `roblox/src/shared/Strings/en.luau`
   - `roblox/src/client/Controllers/StateController.luau`
7. **Starting state:** branch `batch-2-core-loop` (or whatever name batch 2 used) is committed; all tests pass. Create the branch `batch-3-progression` from it.

### Outside facts

These are **to be checked in official docs in task 1** (they were not re-checked when this plan was written, so the session must record the URL and date):
- `Player:IsFriendsWith(userId)` (yields).
- `DataStoreService:GetOrderedDataStore(name)`, `OrderedDataStore:UpdateAsync`, `OrderedDataStore:GetSortedAsync(ascending, pageSize)` → `DataStorePages:GetCurrentPage()`.
- `DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.*)` (exact enum names).
- The `Enum.AnalyticsEconomyTransactionType` names, used as transaction-type strings.

Already checked (2026-11-18):
- `UserService:GetUserInfosByUserIdsAsync(userIds)` ([reference](https://create.roblox.com/docs/reference/engine/classes/UserService.md)) returns `{Id, Username, DisplayName, HasVerifiedBadge}`. Results may come back in any order and leave out invalid or negative IDs, so match them by `Id`. The limit is **250 results per minute**, and the call can fail, so wrap it in `pcall`.
- The DataStore limits are in the architecture record: ordered writes are 30 + 5 × players per minute, and `GetSortedAsync` is 5 + 2 × players per minute.

## Behaviour

All amounts come from the config files (`Seeds`, `Economy`, `Progression`); none are hard-coded in services.

### Seed shop and unlocks
- **Buying:** `BuySeed(seedId, qty)`, where qty is 1 or 5. It succeeds when the seed's `Tier <= HighestUnlockedTier` and you have at least `Price × qty` coins. Coins go down, and `SeedBag[seedId]` goes up by qty.
- **Failures:** a toast `Toast.NotEnoughCoins` or `Toast.SeedLocked`; nothing else changes.
- **Unlocking:** when you shatter a crystal whose tier **equals** your `HighestUnlockedTier` (and that tier is below 10), `HighestUnlockedTier` goes up by 1. You get the toast `Toast.SeedUnlocked` ("{seed} unlocked!"), and a `LogProgressionEvent` ("SeedTier", Complete, the new tier) is logged.
  - Example: shattering your first Quartz unlocks Amethyst.

### Upgrades
- **`BuyUpgrade("Pedestal")`:** the next pedestal is `UnlockedPedestals + 1` (at most 10) and costs `Economy.PedestalCosts[next]`. On success that pedestal's `Unlocked` attribute becomes true straight away.
- **`BuyUpgrade("Lamp")`:** the next level is `LampLevel + 1` (at most 5) and costs `Economy.LampCosts[next]`. **It only affects crystals planted after the purchase**, because `ReadyAt` is fixed at planting.
- **At the maximum:** the toast `Toast.MaxLevel`.

### Crystal Codex
- **Recording:** every shatter records `Codex[seedId][mutation] = true`. A first-time variant gives the toast `Toast.CodexNew` ("New in Codex: {mutation} {seed}"). "None" counts as a variant.
- **Completion bonus:** once all 4 variants (None, Glowing, Molten, Prismatic) of a crystal are recorded, that crystal's shatter coins get **×(1 + CodexBonus) = ×1.10** from then on.

### Daily streak (7-day cycle, UTC dates)
- **`ClaimDaily()`:**
  - **Already claimed today:** the toast `Toast.AlreadyClaimed`.
  - **Last claim was yesterday:** the streak moves to the next day (after day 7 it goes back to day 1).
  - **Any other gap:** the streak resets to day 1.
- **Reward:** from `Progression.Streak[day]`: coins, or seeds of a fixed type.
- **Then:** the toast `Toast.DailyClaimed`, and analytics `StreakClaim` (value = day).

### Daily goals
- **Picking:** on the first load or action of a UTC day, 3 different goals are drawn from `Progression.GoalPool` with the server random generator, and progress resets.
- **Progress events:**

  | Goal | What counts |
  |---|---|
  | `Shatter20` | +1 per shatter |
  | `PlantUncommon5` | +1 per plant of tier ≥ 3 |
  | `FindMutation` | +1 per shatter with a mutation |
  | `Earn5000` | + the coins from each shatter |
  | `BuyUpgrade` | +1 per upgrade bought |
  | `ShatterBig` | +1 per shatter with size tier Big or larger |

- **`ClaimGoal(1|2|3)`:** if `Progress >= Target` and not claimed yet, it pays **`GoalRewardValueMult (10) × BaseValue` of your highest unlocked seed**. For example, at tier 1 that is 10 × 15 = 150 coins.
- **`ClaimGoal("Bonus")`:** once all 3 are claimed (and the bonus isn't yet), it gives **1 Surprise Seed**: the seed of tier `min(HighestUnlockedTier + 1, 10)`.
  - It is **not random** (despite its name, there is one seed per tier), so it isn't a random item.
  - It doesn't unlock buying that tier.
  - Analytics: `GoalsComplete`.

### Friend bonus
- **Amount:** +10% shatter coins for each Roblox friend in the same server, up to +30%.
- **Checking friendships:** done once per player pair when someone joins, and cached.
- **For the HUD later:** the server sets the player attribute `FriendBonus` (0, 0.1, 0.2 or 0.3).

### Server announcements
- **When:** a shatter with mutation **Molten or Prismatic**, or size tier **Colossal**.
- **What:** everyone in the server receives `Announce("Announce.RareFind", {player = DisplayName, size = sizeTier, mutation = …, seed = …})`.
- **Batch 3 client:** it prints the message to the Output in Studio. Batch 4 shows it as a toast.

### Crystal Surge
- **When:** during the first `SurgeMinutes` (5) minutes of every UTC hour (`os.time() % 3600 < 300`).
- **Effect:** crystals planted then get mutation chances × `SurgeMutationMult` (2).
- **Display:** the client can work out the next surge from `workspace:GetServerTimeNow()`; the countdown is shown in batch 4.

### Weekly leaderboard: Biggest Crystal This Week
- **Writes:**
  - A shatter that beats `WeeklyBest` for the current ISO week is queued for writing (`WeekId.fromUnix(os.time())`).
  - Every `LeaderboardFlushSeconds` (30 s), the queue is written with `UpdateAsync` to the OrderedDataStore `BiggestCrystal_<WeekId>`, key `tostring(UserId)`, value `math.floor(carats × 100)`, **keeping the larger value**.
  - Instant-grown crystals never enter the queue. That flag is always false until batch 5, but the check is in place.
  - Players with `UserId <= 0` (Studio local test players) are skipped.
- **Reads:** every `LeaderboardRefreshSeconds` (120 s), `GetSortedAsync(false, 10)` fetches the top 10. Names are looked up with `GetUserInfosByUserIdsAsync` and cached for the server's lifetime.
- **Budget guard:** before every leaderboard **write** cycle, the `OrderedWrite` and `OrderedRead` budgets are checked (ordered `UpdateAsync` uses both), and that cycle is skipped if either is too low. **Reads are not budget-checked** (Decision 4, 2026-11-21): one read per 120 s is far below the 5 + 2 × players per minute limit, and a failed read keeps the board as it is.
- **Hub board:** a 16 × 10-stud board facing the spawn. Title: **"Biggest Crystal This Week"**. 10 rows of "#rank  DisplayName  14.2 ct". Empty rows show "—". The server updates its SurfaceGui text, which replicates to everyone.
- **On shutdown:** the queue is flushed in `game:BindToClose`, with a 10-second limit.

### Edge cases
- **Day or week rollover mid-session:** goals and the streak use the date at the time of the action; the leaderboard key is computed at write time.
- **Friend checks fail (pcall error):** treated as "not friends"; no retry storm.
- **Leaderboard read fails:** the board keeps its last content.
- **Spending coins you don't have:** impossible; every check runs on the server against profile data.

## Not included

- **Screen UI:** the shop and upgrade panels, Codex grid, daily popup, goal list, toasts, surge countdown, hub stalls: all batch 4.
- **Leaderboard prizes:** v1.1, per the MVP decision.
- **Passes and products** that change these numbers (Double Coins, Fast Grow, Extra Pedestals 11–13, Luck Boost): batch 5.
- **Tutorial rules** (8-second grow, guaranteed Glowing, tutorial coins): batch 4.
- **Cross-server announcements** (MessagingService): not in v1.

## Design

**Stored data:** no schema change. Batch 3 fills existing version 1 fields: `HighestUnlockedTier`, `Codex`, `Streak`, `DailyGoals`, `WeeklyBest`, `LampLevel`, `UnlockedPedestals`, `Stats`.

### Shared contract

```lua
-- Config additions
Config.Progression.GoalRewardValueMult = 10
Config.Game.AnnounceMutations = { Molten = true, Prismatic = true }
Config.Game.AnnounceSizeTiers = { Colossal = true }
Config.Game.LeaderboardRows = 10

-- Logic (pure, NO requires)
Economy.seedById(seeds, id): Seed?
Economy.canBuySeed(seed, highestTier: number, coins: number, qty: number): (boolean, "Locked"|"Coins"|nil)
Economy.nextPedestalCost(unlocked: number, costs, maxCoin: number): number?   -- nil at max
Economy.nextLampCost(level: number, costs): number?                          -- nil at max
Economy.shatterCoinMult(codexComplete: boolean, codexBonus: number, friendBonus: number): number
Economy.goalReward(seeds, highestTier: number, mult: number): number
Economy.surpriseSeedId(seeds, highestTier: number): string
Streak.claim(streak: {Day, LastClaimDate}, today: string, yesterday: string)
  : (ok: boolean, newStreak: {Day, LastClaimDate}?, day: number?)           -- ok=false when already claimed today
Goals.ensureToday(dailyGoals, today: string, pool, count: number, rng: () -> number): (dailyGoals, rerolled: boolean)
Goals.track(dailyGoals, eventName: string, amount: number): {number}        -- indexes whose progress changed
  -- eventName ∈ "Shatter" | "PlantUncommon" | "Mutation" | "Coins" | "Upgrade" | "ShatterBig"
Goals.canClaim(dailyGoals, index: number, pool): boolean
Goals.canClaimBonus(dailyGoals): boolean
Codex.record(codex, seedId: string, mutation: string): (isNew: boolean)
Codex.isComplete(codex, seedId: string): boolean                              -- all 4 variants
Surge.isActive(now: number, minutes: number): boolean
Surge.nextStart(now: number): number                                         -- next hour boundary, or now if active

-- Server services
ShopService            -- handlers BuySeed, BuyUpgrade
ProgressionService     -- handlers ClaimDaily, ClaimGoal; :Track(player, eventName, amount); :OnShatter(player, result, seed)
SocialService          -- :FriendBonus(player): number; :Announce(player, result, seed)
LeaderboardService     -- :Submit(player, carats: number); builds and updates the hub board
CrystalService         -- changed: unlock tiers, codex, goals, friend and codex coin multipliers, surge chance, leaderboard submit
-- All coin changes go through one helper: CrystalService/ShopService call
DataService:AddCoins(player, amount, transactionType, sku)   -- NEW in DataService: also logs LogEconomyEvent (Source)
DataService:SpendCoins(player, amount, sku): boolean         -- NEW: false if not enough; logs LogEconomyEvent (Sink)
```

### Files

| File (under `roblox/`) | Change | Task |
|---|---|---|
| `src/shared/Config/Progression.luau`, `Game.luau` | Add the fields above | 1 |
| `src/shared/Strings/en.luau` | Add `Toast.NotEnoughCoins` "Not enough coins", `Toast.SeedLocked` "Shatter a {prev} to unlock", `Toast.SeedUnlocked` "{seed} unlocked!", `Toast.MaxLevel` "Already at max level", `Toast.CodexNew` "New in Codex: {mutation} {seed}", `Toast.AlreadyClaimed` "Already claimed today", `Toast.DailyClaimed` "Day {day} reward claimed!", `Toast.GoalClaimed` "+{coins} coins", `Toast.BonusSeed` "Surprise Seed: {seed}!", `Announce.RareFind` "{player} found a {size} {mutation} {seed}!", `Board.Title` "Biggest Crystal This Week", `Board.Empty` "—", `Goal.<Id>` labels for the 6 goals ("Shatter 20 crystals", "Plant 5 Uncommon or better", "Find a mutation", "Earn 5,000 coins", "Buy an upgrade", "Shatter a Big or larger crystal"), `Mutation.<Name>` ("Glowing", "Molten", "Prismatic"), `Size.<Name>` ("Normal", "Big", "Huge", "Colossal") | 1 |
| `src/shared/Logic/Economy.luau`, `Surge.luau` + `tests/Economy.spec.luau`, `tests/Surge.spec.luau` | New | 2 |
| `src/shared/Logic/Streak.luau`, `Goals.luau` + specs | New | 3 |
| `src/shared/Logic/Codex.luau` + spec | New | 4 |
| `src/server/Services/DataService.luau` | Add `AddCoins` and `SpendCoins` | 5 |
| `src/server/Services/ShopService.luau` | New | 5 |
| `src/server/Services/ProgressionService.luau` | New | 6 |
| `src/server/Services/LeaderboardService.luau` | New (hub board part built here, parented under `workspace.Map.Hub`) | 7 |
| `src/server/Services/SocialService.luau` | New | 8 |
| `src/server/Services/CrystalService.luau` | Integration | 9 |
| `src/server/Main.server.luau` | Order: … → CrystalService → ShopService → ProgressionService → SocialService → LeaderboardService (CrystalService calls the others at runtime; they are required lazily inside functions to avoid require cycles) | 9 |
| `src/client/Controllers/StateController.luau` | In Studio only, print `Toast` and `Announce` as `[Toast] <text>` and `[Announce] <text>` using `Strings.get` | 4 |

## Task breakdown and model assignment

| # | Task | Model | Why this model | Depends on |
|---|---|---|---|---|
| 0 | Save the record status and create the branch | Orchestrator | — | — |
| 1 | **Proof:** check the "Outside facts" APIs in official docs and record them as findings; add the config fields and strings | Orchestrator | Needs judgment | 0 |
| 2 | `Logic/Economy`, `Logic/Surge` + specs | DeepSeek Flash | Pure functions, exact contract | 1 |
| 3 | `Logic/Streak`, `Logic/Goals` + specs | DeepSeek Flash | Pure functions; date strings passed in | 1 |
| 4 | `Logic/Codex` + spec; StateController Studio prints | Haiku | Small, fully specified | 1 |
| 5 | `DataService:AddCoins/SpendCoins`, `ShopService` | Orchestrator | Coins and validation (project rule) | 2 |
| 6 | `ProgressionService` | Orchestrator | Grants coins and seeds | 3, 5 |
| 7 | `LeaderboardService` + hub board | Orchestrator | DataStore code (project rule) | 1 |
| 8 | `SocialService` | DeepSeek Flash | Friend cache and announcements, no economy writes | 1 |
| 9 | `CrystalService` integration + `Main.server` order | Orchestrator | Touches the coin path | 2–8 |
| 10 | Review, tests, StyLua, `rojo build`, Studio checks with you, findings and outcome | Orchestrator | — | 2–9 |

Escalation: review failures go back once with the specific defects, then to DeepSeek Pro, or the orchestrator fixes small ones. **If task 1 shows an API differs** (for example, ordered-store `UpdateAsync` behaves differently), add the correction to Findings before writing tasks 5–9.

### Acceptance criteria

- **Task 2:**
  - `canBuySeed` handles the lock, the coins and qty 5.
  - Pedestal costs return 100 for the 4th pedestal and `nil` after the 10th.
  - Lamp costs return `nil` after level 5.
  - `shatterCoinMult(true, 0.1, 0.3)` = 1.43 (1.1 × 1.3).
  - `goalReward` at tier 1 = 150.
  - `surpriseSeedId` at tier 10 = "Voidheart".
  - Surge: 12:03 UTC is active, 12:05 is not; `nextStart(12:30)` = 13:00.
- **Task 3:**
  - Streak cases: first claim → day 1; yesterday → +1; day 7 → 1; a 2-day gap → 1; the same day → `ok = false`.
  - Goals: the 3 picks are distinct; a new day rerolls and resets; `track` caps nothing (progress can exceed the target); claims need `Progress >= Target`; the bonus needs all 3 claimed and pays once.
  - Each pure module has a test that it contains no `require` call.
- **Task 4:** `record` returns true only the first time; `isComplete` needs all 4 variants; the Studio prints show the formatted strings.
- **Tasks 5 and 6:**
  - Every handler re-reads profile data and never trusts amounts from the client.
  - `SpendCoins` returns false without changing anything when coins are short.
  - Each grant and spend logs one `LogEconomyEvent`, with transaction types from task 1 (no more than 20 distinct, and SKUs are seed IDs, `Pedestal_n`, `Lamp_n`, `Daily_n`, `Goal_<Id>`).
  - `StateSync` is sent after each change.
- **Task 7:** writes only when beating the weekly best; never for instant-grown crystals or `UserId <= 0`; `UpdateAsync` keeps the maximum; the write budget is checked (reads aren't, Decision 4); the queue is flushed on shutdown; the board is updated after each read; nothing is called more often than the architecture allows.
- **Task 8:** friendships are checked once per pair, wrapped in `pcall`; the bonus is capped at 0.3; announcements follow the config lists.
- **Task 9:**
  - The shatter path order: remove the crystal → compute coins with `shatterCoinMult` → `AddCoins` → codex → goals → unlock → weekly best and leaderboard submit → announce → `ShatterResult` → `StateSync`.
  - Plant: surge `chanceMult`; goal `PlantUncommon` for tier ≥ 3.
- **Task 10:** all tests pass (the previous total plus the new ones), StyLua is clean, `rojo build` succeeds, and the checks below pass.

## Verification

- **Automated tests:** `Economy.spec`, `Surge.spec`, `Streak.spec`, `Goals.spec`, `Codex.spec`, plus all earlier ones.
- **Backup first:** not needed. There is no schema change; dev data only.
- **Studio Play Solo, using the client command bar** (`local R = game.ReplicatedStorage.Remotes`):
  1. Shatter your Quartz → the Output shows `[Toast] Amethyst unlocked!` and `[Toast] New in Codex: … Quartz`.
  2. `R.BuySeed:FireServer("Amethyst", 1)` with too few coins → `[Toast] Not enough coins`; with enough → the `[State]` seeds include Amethyst.
  3. `R.BuyUpgrade:FireServer("Pedestal")` with 100+ coins → pedestal 4 becomes unlocked in the world.
  4. `R.ClaimDaily:FireServer()` → `Day 1 reward claimed!`, coins +100; again → `Already claimed today`.
  5. Shatter 1 crystal → the progress of a goal you have moves (shown in `[State]` DailyGoals).
  6. Plant during minutes :00–:04 of the hour → the planted crystals show mutations more often. This is a statistical check only; the unit tests prove the rule.
  7. Set a new weekly best → within 2 minutes the hub board shows your name and carats.
- **Studio 2-player local server:** both players have `UserId < 0`, so leaderboard writes are skipped (by design). Friend bonus = 0. Announcements reach both Outputs when a Molten or Prismatic crystal is found. This is rare, so the server also logs a debug announcement test.
- **Phone (published dev experience):** the leaderboard board is readable at the hub.
- **Published DEV server:** print `GetRequestBudgetForRequestType` for `OrderedList`, `OrderedRead` and `OrderedWrite` from the developer console (Server) and record the values (Decision 4).

## Decisions (confirmed by the user 2026-11-18, recommended options chosen)

1. **The Surprise Seed is the next tier's seed, not random.** Rejected: a random seed, which would need odds shown and could count as a random item.
2. **Goal rewards scale with your highest unlocked seed (×10 its base value).** Rejected: fixed coin amounts, which become worthless late in the game.
3. **The Growth Lamp affects only new plantings.** Rejected: re-timing crystals that are already growing, which is more complex and has a double-dip risk.
4. **Leaderboard reads aren't budget-checked; writes are** (your choice, 2026-11-21, option A; Findings → Task 1). The docs say `GetRequestBudgetForRequestType(OrderedList)` returns 0, which would block every read. Task 10 prints the real value on the published DEV server. Rejected: checking reads but treating 0 as "unknown".

## Progress (2026-11-21)

- **Task 0 done:** branch `batch-3-progression` created from `cave-brightness` (`69d1fd4`, pushed; the same tree as `batch-1-setup` after PR #2). Starting state: `lune run tests` **104 passed, 0 failed**.
- **Changes since this plan was written** (the [cave-brightness record](2026-11-18-cave-brightness-setting.md) was done after approval). Checked against this plan on 2026-11-21; **none conflicts with it**, so the plan stands:
  - **`SettingsService` already exists** and starts after `DataService`. The task 9 order becomes Analytics → RemoteService → DataService → SettingsService → MapService → PlotService → CrystalService → ShopService → ProgressionService → SocialService → LeaderboardService.
  - **Remotes has 17 entries**, including `SetBrightness`. Batch 3 adds none: `BuySeed`, `BuyUpgrade`, `ClaimDaily`, `ClaimGoal`, `Toast` and `Announce` already exist with the argument rules this plan needs.
  - **The profile template has `Settings.Brightness`.** Batch 3 doesn't touch `Settings`; still no schema change.
  - **`MapService` reads `Config/Lighting`** and uses lighter cave colours. Players can pick Dark, so the hub board's `SurfaceGui` gets `LightInfluence = 0` (text at full brightness at every level). This is a detail inside task 7, not a plan change.
  - **The test baseline is 104**, not 93.
- **Noted, not a conflict:** the architecture record says the leaderboard writes a JSON `StringValue` that the client renders. This plan (later and approved) has the server write the board's `SurfaceGui` text directly; the plan is followed.
- **Task 1 done (2026-11-21, orchestrator):**
  - **Config:** `Progression.GoalRewardValueMult = 10`; `Game.AnnounceMutations`, `Game.AnnounceSizeTiers`, `Game.LeaderboardRows = 10` (with their types).
  - **Strings:** all 25 keys from the Files table, word for word.
  - **Added beyond the plan:** 3 `Config.spec` cases: the announce lists name real mutation and size bands; `GoalRewardValueMult` is 10 (a tier 1 goal pays 150); every goal, mutation and size tier has an English label.
  - **Tests:** `lune run tests` **107 passed, 0 failed** (104 + 3). StyLua clean.
- **Decision 4 recorded (2026-11-21):** leaderboard writes are budget-checked, reads aren't (option A). Behaviour, acceptance criteria and Verification are updated.
- **Task 2 done (2026-11-21, DeepSeek Flash, accepted first time):** [Logic/Economy.luau](../../roblox/src/shared/Logic/Economy.luau), [Logic/Surge.luau](../../roblox/src/shared/Logic/Surge.luau), 12 + 4 tests covering every task 2 criterion.
  - **Contract change:** `Surge.nextStart(now, minutes)` takes `minutes` too. The plan's `nextStart(now)` must return `now` while a surge is active, which needs the window length, and Logic modules can't read config.
  - **Edge rules:** `goalReward` falls back to the closest lower tier, then the lowest seed, if no seed has exactly `highestTier`; it floors `x + 1e-9` like `Growth.shatterValue`.
  - **Review:** the recovery journal hashes matched the files; acknowledged. Tests **123 passed, 0 failed**; StyLua clean.
- **Task 3 done (2026-11-21, DeepSeek Flash, accepted with one comment fix):** [Logic/Streak.luau](../../roblox/src/shared/Logic/Streak.luau), [Logic/Goals.luau](../../roblox/src/shared/Logic/Goals.luau), 8 + 17 tests covering every task 3 criterion (200 seeded draws all distinct; rng 0 and 0.9999999 also distinct).
  - **Contract additions:** `Streak.claim(..., cycle?)` (default 7) returns a new table and never changes its input. `Goals.EventGoal` maps the 6 event names to goal IDs. `Goals.ensureToday` changes the board in place and returns it (the profile keeps the same table). `track` skips claimed goals.
  - **Review:** journal hashes matched; acknowledged. The orchestrator then fixed one comment (`Config/Goals` → `Config/Progression.GoalPool`). Tests **148 passed, 0 failed**; StyLua clean.
- **Task 4 done (2026-11-21, Haiku, accepted first time):** [Logic/Codex.luau](../../roblox/src/shared/Logic/Codex.luau) (with `Codex.Variants`, the 4 names in order), 6 tests, and the Studio-only `[Toast]`/`[Announce]` prints in [StateController.luau](../../roblox/src/client/Controllers/StateController.luau).
  - **Mutation "None" in messages:** the server will send `mutation = ""` for a crystal with no mutation, and the print collapses the leftover double space ("New in Codex: Quartz"). Batch 4's toasts need the same tidy-up, or a `Mutation.None` label.
  - **Not checked yet:** the prints run only in Studio; they're checked in task 10.
  - Tests **154 passed, 0 failed** (104 + 50 new); StyLua clean; `rojo build` succeeds.
- **Task 5 done (2026-11-21, orchestrator):**
  - **`DataService:AddCoins(player, amount, transactionType, sku?)`** and **`:SpendCoins(player, amount, sku)`** return `false` and change nothing if the profile isn't loaded, the amount isn't a positive whole number, or (spend) coins are short. Each success logs one `LogEconomyEvent` with currency `"Coins"`: a `Source` event of the given type, or a `Sink` of type `Shop`. Neither sends `StateSync`; the caller syncs once after all its changes. `Stats` stay with the callers (as in batch 2).
  - **[ShopService.luau](../../roblox/src/server/Services/ShopService.luau):** `BuySeed` and `BuyUpgrade` re-read the profile and prices from config; nothing from the client except the seed ID, qty (1 or 5) and upgrade kind, all already checked by `RemoteService`. On failure: a toast and no change. A bought pedestal gets `Unlocked = true` and the unlocked look at once (`MapService.setPedestalLook`). SKUs: the seed ID, `Pedestal_<n>`, `Lamp_<n>`.
  - **`Toast.SeedLocked`'s `{prev}`** is the seed one tier below the locked one (its direct prerequisite).
  - **Depends on task 6:** after a bought upgrade, `ShopService` calls `ProgressionService:Track(player, "Upgrade", 1)` (required lazily), then syncs. So **`Track` changes data only and never syncs**. `ShopService` isn't in the `Main.server` order until task 9, so nothing runs before that file exists.
  - Tests **154 passed, 0 failed**; StyLua clean; `rojo build` succeeds. Not run in Studio yet (task 10).
- **Task 6 done (2026-11-21, orchestrator):** [ProgressionService.luau](../../roblox/src/server/Services/ProgressionService.luau).
  - **`ClaimDaily`:** dates from `WeekId.dateString(os.time())` and the same minus one day; the cycle length is `#Progression.Streak` (7). Coin days → `AddCoins(..., "TimedReward", "Daily_<day>")`; seed days add to `SeedBag` (no economy event, as Findings say). Then `Toast.DailyClaimed`, the `StreakClaim` custom event (value = day) and one `StateSync`. Same day again → `Toast.AlreadyClaimed`, no change.
  - **`ClaimGoal(1|2|3)`:** redraws first if the day has changed. Claimable → `Claimed = true`, `AddCoins(Economy.goalReward(...), "Gameplay", "Goal_<Id>")`, `Toast.GoalClaimed` (coins shown with `Format.compact`), sync. **`ClaimGoal("Bonus")`:** 1 seed from `Economy.surpriseSeedId`, `Toast.BonusSeed`, `GoalsComplete` event. Not claimable → no toast and no change (a sync only if the day's goals were just redrawn).
  - **`:Track(player, event, amount)`** redraws the goals on a new day, then adds progress. It **changes data only and never syncs** (task 5).
  - **`:OnShatter(player, result, seed)`**, in plan order: codex record (+ `Toast.CodexNew` the first time) → goals (`Shatter`, `Coins`, `Mutation` if any, `ShatterBig` for Big and every larger tier in `Config/Rolls`) → unlock (shattering your highest tier, below 10, unlocks the next one: `Toast.SeedUnlocked` and `LogProgressionEvent("SeedTier", Complete, newTier, seedId)`). Changes data only; `CrystalService` syncs once (task 9).
  - **On profile load:** goals are drawn for the day, with a sync only if they changed. A catch-up loop covers profiles that loaded before `Start`.
  - Checked in the docs (2026-11-21): [`AnalyticsProgressionType`](https://create.roblox.com/docs/reference/engine/enums/AnalyticsProgressionType.md) has `Complete`.
  - Tests **154 passed, 0 failed**; StyLua clean; `rojo build` succeeds. Not run in Studio yet (task 10).
- **Task 7 done (2026-11-21, orchestrator):** [LeaderboardService.luau](../../roblox/src/server/Services/LeaderboardService.luau).
  - **`:Submit(player, carats, instantGrown?)`:** skips instant-grown crystals and `UserId <= 0`. Queues `math.floor(carats × 100)` under the week **in which the crystal was shattered**, keeping the larger value per player. A shatter just before Monday 00:00 UTC therefore counts for the week it happened in, matching `WeeklyBest`.
  - **Flush every 30 s:** each entry is taken out of the queue, then written with `UpdateAsync`. The callback returns `nil` (no write) when the stored value is already ≥ ours. A write that fails, or is skipped because `OrderedWrite` or `OrderedRead` is at or below 2, goes back in the queue for the next cycle. Only one flush runs at a time.
  - **Read every 120 s** (and once at start): `GetSortedAsync(false, 10)` on the current week's store, with no budget check (Decision 4). Names come from players in the server, then one `GetUserInfosByUserIdsAsync` call for the rest (matched by `Id`). Found names are cached for the server's lifetime; a failed lookup is retried at the next refresh, and the row shows "…" until then. A failed read keeps the board as it is.
  - **Most calls per minute (6 players):** writes ≤ 12 (one per player per 30 s) against an OrderedWrite budget of 60; reads 0.5 against OrderedList's 17; name lookups ≤ 0.5 against UserService's 250.
  - **Shutdown:** `BindToClose` flushes the queue, waiting at most 10 s.
  - **Board:** a 16 × 10 × 0.5-stud part, `workspace.Map.Hub.LeaderboardBoard`, built in `Init` (it must run after `MapService`). It stands inside the hub rim (radius 34, 30° round from plot 1's path, between the paths to plots 1 and 2), bottom 2 studs above the floor, with its front facing the spawn pad. `SurfaceGui` at 50 px per stud with `LightInfluence = 0`: the title "Biggest Crystal This Week" and 10 rows "#1  Name  14.2 ct" (empty: "#1  —").
  - Tests **154 passed, 0 failed**; StyLua clean; `rojo build` succeeds. Not run in Studio yet (task 10).
- **Task 8 done (2026-11-21, DeepSeek Flash, accepted with one fix):** [SocialService.luau](../../roblox/src/server/Services/SocialService.luau).
  - **Friend bonus:** on join, `FriendBonus = 0`, then one `IsFriendsWithAsync` check per uncached pair, each in its own thread inside `pcall`. A failure or non-boolean counts as "not friends" and is cached (never retried). Pairs with a user ID ≤ 0 (Studio test players) are cached `false` without a call. `:FriendBonus(player)` = 0.10 per friend in the server, capped at 0.30, rounded to 2 decimals; the attribute gets the same value after each check and after each leave. A leave forgets that player's pairs, so a rejoin is rechecked.
  - **Announcements:** `:Announce` fires `Announce("Announce.RareFind", {player, size, mutation, seed})` to everyone when the mutation is in `AnnounceMutations` or the size tier in `AnnounceSizeTiers`; the names are display strings (mutation `""` for None).
  - **Studio debug test (the plan's "debug announcement"):** setting `workspace:SetAttribute("DebugAnnounce", true)` from the server command bar announces a fake Colossal Prismatic Quartz from the first player, then resets the attribute.
  - **Review fix (orchestrator):** a check still running when a player left and rejoined could overwrite the new check's result, or block the recheck. Each check now carries a token; a leave clears it, and a check whose token no longer matches is dropped.
  - **Review:** the journal hash differed because StyLua reformatted the file after the write; the whole file was read and acknowledged. DeepSeek's build check left a file in `C:\Windows\Temp`; deleted.
  - Tests **154 passed, 0 failed**; StyLua clean; `rojo build` succeeds. Not run in Studio yet (task 10).
- **Task 9 done (2026-11-21, orchestrator):** [CrystalService.luau](../../roblox/src/server/Services/CrystalService.luau) and [Main.server.luau](../../roblox/src/server/Main.server.luau).
  - **Shatter path** (unchanged checks, then): remove the crystal → `coinMult = Economy.shatterCoinMult(Codex.isComplete(...), CodexBonus, SocialService:FriendBonus(player))` passed to `Growth.shatterValue` → `DataService:AddCoins(..., "Gameplay", seedId)` plus `Stats` → `ProgressionService:OnShatter` (codex, goals, unlock) → weekly best, with `LeaderboardService:Submit(player, carats, instantGrown)` only on a new best → `SocialService:Announce` → clear the pedestal → `ShatterResult` → `StateSync` (one per `ShatterAll`). Still no yields between the removal and the grant.
  - **The Codex bonus** uses the Codex as it was before this shatter, so the shatter that completes an entry isn't boosted; the next ones are ("from then on").
  - **Plant:** mutation `chanceMult = SurgeMutationMult` (2) when `Surge.isActive(plantedAt, SurgeMinutes)`, else 1; `Track("PlantUncommon")` for tier ≥ 3, before the sync.
  - **Lazy requires:** `ProgressionService`, `SocialService` and `LeaderboardService` are required inside small helper functions on first use (none of them requires `CrystalService`, so there's no cycle either way).
  - **`Main.server` order:** Analytics → RemoteService → DataService → SettingsService → MapService → PlotService → CrystalService → ShopService → ProgressionService → SocialService → LeaderboardService (11 services).
  - Tests **154 passed, 0 failed**; StyLua clean; `rojo build` succeeds. **Nothing from tasks 5–9 has run in Studio yet** (task 10).

## Findings

### Task 1: outside facts (checked 2026-11-21)

Pages read through the Studio MCP doc fetcher; each page showed `last_updated: 2026-11-20`.

| API | Official page | What it says | Effect on this plan |
|---|---|---|---|
| `Player:IsFriendsWith(userId)` | [Player](https://create.roblox.com/docs/reference/engine/classes/Player.md) | **Deprecated**, "superseded by `Player:IsFriendsWithAsync()`, which shares the same behavior". Yields; results are cached per player and user ID. | Use **`IsFriendsWithAsync`** in task 8. Same behaviour, so no plan change. Still wrapped in `pcall`. |
| `DataStoreService:GetOrderedDataStore(name, scope?)` | [DataStoreService](https://create.roblox.com/docs/reference/engine/classes/DataStoreService.md) | Returns an `OrderedDataStore`; the same object for the same name and scope. | As planned. |
| `OrderedDataStore:UpdateAsync(key, fn)` | [OrderedDataStore](https://create.roblox.com/docs/reference/engine/classes/OrderedDataStore.md), [GlobalDataStore](https://create.roblox.com/docs/reference/engine/classes/GlobalDataStore.md) | Inherited from `GlobalDataStore`. If the callback returns `nil`, the write is cancelled. Ordered values must be **integers**; no versions or metadata. | As planned: return `nil` when the stored value is already ≥ ours (keeps the maximum, and costs no write). The value is already an integer (`math.floor(carats × 100)`). |
| `OrderedDataStore:GetSortedAsync(ascending, pageSize, min?, max?)` → `DataStorePages:GetCurrentPage()` | [OrderedDataStore](https://create.roblox.com/docs/reference/engine/classes/OrderedDataStore.md) | Page size 1–100. The page is an array of `{ key, value }` in rank order. | As planned: `GetSortedAsync(false, 10)`. |
| `GetRequestBudgetForRequestType(Enum.DataStoreRequestType.*)` | [DataStoreRequestType](https://create.roblox.com/docs/reference/engine/enums/DataStoreRequestType.md), [limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits.md) | Legacy names (`GetSortedAsync`, `SetIncrementSortedAsync`, `UpdateAsync`, …) "should not be used". Modern names: **`OrderedRead`**, **`OrderedWrite`**, **`OrderedList`**. Per-server limits: OrderedRead 60 + 40 × players, OrderedWrite 30 + 5 × players, OrderedList 5 + 2 × players per minute. Ordered `UpdateAsync` counts against **both OrderedRead and OrderedWrite**. The `OrderedList` row also says: "`GetRequestBudgetForRequestType()` with this enum will return `0`." | **See below:** the planned read guard would skip every read if `OrderedList` really returns 0. |
| `Enum.AnalyticsEconomyTransactionType` | [enum page](https://create.roblox.com/docs/reference/engine/enums/AnalyticsEconomyTransactionType.md) | `IAP`, `Shop`, `Gameplay`, `ContextualPurchase`, `TimedReward`, `Onboarding`; pass `.Name`. Custom strings allowed, 20 distinct at most. Flow types ([page](https://create.roblox.com/docs/reference/engine/enums/AnalyticsEconomyFlowType.md)): `Source`, `Sink`. | Batch 3 uses 3: shatter coins and goal rewards → `Gameplay`; seed and upgrade purchases → `Shop`; daily streak coins → `TimedReward`. Seed rewards (streak days 3 and 7, the Surprise Seed) aren't coins, so they log no economy event. |
| `SurfaceGui.LightInfluence` | [SurfaceGui](https://create.roblox.com/docs/reference/engine/classes/SurfaceGui.md) | A float property, read/write. | Board uses `LightInfluence = 0` (see Progress). |

**Budget values measured in Studio** (Edit mode, place "Crystal Grove DEV", read-only call over every enum item): `OrderedRead = 2500`, `OrderedWrite = 350`, **`OrderedList = 130`**, legacy `GetSortedAsync = 130`. So Studio does **not** return 0 for `OrderedList`. Studio uses its own fixed limits ([limits page](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits.md): "Data store requests made in Studio Run mode are subject to a separate set of static limits"), so this doesn't show what a live server returns. **Open:** the value on a published DEV server.

### Task 10: Studio Play Solo (2026-11-21)

Place "Crystal Grove DEV", Rojo connected (the server from the previous session on port 34872). All 16 changed scripts had the same length in Studio as on disk. Device Simulator on (Galaxy S25 Ultra, landscape, 685 × 338). Your DEV profile was used (sessions 29, 223 coins, highest tier 1 at the start).

The command bar loads its own copy of each module, so it can't read the server's live profile. The checks instead listened on the client to `StateSync`, `Toast`, `Announce` and `ShatterResult`, and fired the remotes from the client command bar.

| # | Check | Result |
|---|---|---|
| — | Server start | **Passed.** `[Server] Started 11 services`; `[Leaderboard] board refreshed: 0 entries`; no errors (only the known `rbxassetid://203785492` warning). |
| 1 | Shatter Quartz → `Amethyst unlocked!` and `New in Codex: … Quartz` | **Passed.** `ShatterAll` on 3 ripe Quartz: Output `[Toast] New in Codex: Quartz` (no double space) and `[Toast] Amethyst unlocked!`, each once. Coins 223 → 276 = 17 + 18 + 18 from the 3 `ShatterResult`s. Codex `{Quartz = {None}}`, highest tier 2. `LogEconomyEvent` ×3 and `LogProgressionEvent` ×1 fired. |
| 2 | `BuySeed` refusals, then success | **Passed.** Amethyst at tier 1 → `[Toast] Shatter a Quartz to unlock`. At tier 2: 5 Amethyst with 176 coins → `[Toast] Not enough coins`, no sync; 1 Amethyst → coins 176 → 136, bag `Amethyst = 1`. `BuyUpgrade("Lamp")` with 223 coins → `Not enough coins`. |
| 3 | `BuyUpgrade("Pedestal")` with 100+ coins → pedestal 4 unlocked in the world | **Passed.** Coins 276 → 176, `UnlockedPedestals` 4; on the client `Pedestal_4` has `Unlocked = true` and the unlocked colour (120, 120, 140). The `BuyUpgrade` goal moved 0 → 1. |
| 4 | `ClaimDaily` → Day 1, +100; again → already claimed | **Passed.** Coins 136 → 236, streak `Day 1, 2026-11-21`, `[Toast] Day 1 reward claimed!`. Second claim → `Already claimed today`, no change and no sync. |
| 5 | A shatter moves a goal's progress | **Passed.** Goals drawn for 2026-11-21: Shatter20, BuyUpgrade, Earn5000. After 3 shatters: 3 and 53. **Claims:** `ClaimGoal(2)` → +600 (10 × Amethyst's 60), `[Toast] +600 coins`, `Claimed`. `ClaimGoal(1)` (3/20) and `ClaimGoal("Bonus")` → nothing, no sync. |
| 6 | Surge: more mutations during :00–:04 | **Not checked.** The run was at about :14–:20 UTC. It's a statistical check only; `Surge.spec` covers the rule. |
| 7 | New weekly best → the hub board shows your name within 2 minutes | **Passed.** An Amethyst at **2.00 ct** beat the stored 1.83 (`newBest = true`; it also unlocked Citrine). 32 s later the board's row 1 read your display name and "2.0 ct"; rows 2–10 "—"; title "Biggest Crystal This Week". So the flush, `UpdateAsync`, `GetSortedAsync` and the name lookup all worked against the DEV DataStore. |
| — | Board in the phone view at Dark, Normal and Bright | **Passed** (your check, 2026-11-21): "readable at all three levels, keep the current size". A screenshot from the spawn side shows the gold title, row 1 and rows 2–10. |

**Found and fixed: today's goals weren't drawn on join.** After loading, `DailyGoals` was still `{Date = "", Goals = {}}`. **Cause:** `DataService.ProfileLoaded` is a `BindableEvent`, and its table argument reaches listeners as a copy, so `ProgressionService` drew the goals into the copy. The [official guide](https://create.roblox.com/docs/scripting/events/bindable.md) says "Tables passed as arguments to bindable events and callbacks are copied" (checked 2026-11-21). **Fix:** `onProfileLoaded` now reads the live profile with `DataService:GetData(player)`, and `DataService`'s comment on `ProfileLoaded` warns about the copy. In this run the goals were drawn at the first shatter instead (through `Track`, which already used `GetData`). **The fix is checked in the 2-player test**, because the test profiles have no goals yet. Tests 154/154, StyLua and `rojo build` pass after the fix.

**Explained, not a bug:** 2 extra `StateSync`s with no gameplay change were brightness changes (Dark → Normal → Bright, ☀ taps).

**Test notes:**
- `screen_capture` with a camera position leaves out `SurfaceGui` text. A capture of the real client camera shows it.
- The default camera script switches a Scriptable camera back to Custom, and an unfocused Studio window returns a stale frame (as in batch 2).

**Dev data changed:** your DEV profile now has highest tier 3 (Citrine), pedestal 4, today's daily claimed (Day 1), goal 2 claimed, Codex Quartz and Amethyst (None), weekly best 2.00 ct, 954 coins. The DEV leaderboard `BiggestCrystal_2026W47` has your entry at 200.

### Task 10: Studio local server, 2 players (2026-11-21)

Server and 2 clients (Player1 = test profile `Player_-1`, Player2 = `Player_-2`), started by you. Calls were fired from each client's command bar through the MCP; the debug announcement from the server's command bar.

| # | Check | Result |
|---|---|---|
| 1 | Goals drawn on join (the fix from Play Solo) | **Passed.** Neither test profile had goals before (batch 3 had never run on them). After joining, each had 3 different goals dated 2026-11-21 at progress 0 (Player1: FindMutation, PlantUncommon5, ShatterBig; Player2: FindMutation, PlantUncommon5, Shatter20). |
| 2 | Friend bonus = 0 | **Passed.** Server: `[Social] friends Player2 & Player1 = false`, one check for the pair (test IDs, no API call). `FriendBonus = 0` on both clients. |
| 3 | No leaderboard write for `UserId < 0` | **Passed.** Player1 (ID −1) shattered a Quartz at 1.51 ct with `newBest = true`. Two later board refreshes, the last more than 150 s after the shatter (so after several 30-s flushes), still read `1 entries`: only your Play Solo entry, no row for −1. No write warning in the server Output. |
| 4 | Announcement reaches both Outputs | **Passed.** `workspace:SetAttribute("DebugAnnounce", true)` on the server → `[Social] debug announcement test from Player1`. Both clients received `Announce.RareFind` and printed `[Announce] Player1 found a Colossal Prismatic Quartz!`. The attribute reset itself to false. |
| — | Player1's first shatter | `[Toast]` `CodexNew` (Quartz) and `SeedUnlocked` (Amethyst), as in Play Solo. |

**Not checked here:** a real Molten or Prismatic find (too rare; the debug test uses the same `Announce` call).

**Dev data changed:** `Player_-1` has tier 2, a weekly best of 1.51 ct (profile only, not on the leaderboard) and 22 coins. Both test profiles have Brightness `Normal` (switched Bright → Normal to trigger state updates).

### Task 10: published DEV experience, your phone (2026-11-21)

You ended the test sessions, published, checked File → Version History and joined from the DEV place link.

- **New version running: passed.** The server log on the phone shows `[Server] Started 11 services` (the old version had 7), with 0 errors and 0 warnings.
- **Hub board readable on the phone: passed** (your check).
- **Request budgets on a live server** (Decision 4), from the developer console's Server command line at 16:38 server time: **`OrderedList = 17`**, `OrderedRead = 215`, `OrderedWrite = 102`. So the docs' note that `OrderedList` returns 0 is wrong for live servers too. 17 = 5 + 2 × 6, the list limit for this server's 6-player maximum. **Decision 4 stands:** reads stay unchecked, because one read per 120 s is far below 17 per minute. A read check could now be added safely if ever needed.

## Outcome (2026-11-21)

- **Built as specified**, with these differences (details in Progress and Findings):
  - **Decision 4:** leaderboard writes are budget-checked, reads aren't. The docs said the read budget returns 0; on the live DEV server it returned 17.
  - **`IsFriendsWithAsync`** is used instead of the deprecated `IsFriendsWith`.
  - **Contract additions:**
    - `Surge.nextStart(now, minutes)` takes the window length.
    - `Streak.claim(..., cycle?)` takes an optional cycle length.
    - `Goals.EventGoal` maps event names to goal IDs.
    - `Codex.Variants` lists the 4 variants.
    - `LeaderboardService:Submit(player, carats, instantGrown?)` does the instant-grown check.
  - **No double space in messages:** mutation "None" is sent as `""`, and the Studio print collapses the space. Batch 4's toasts need the same.
  - **The board** stands inside the hub rim, 30° from plot 1's path, facing the spawn. `LightInfluence = 0` keeps it readable at every brightness level.
  - **3 extra `Config.spec` cases** check the new config names and labels.
- **Bugs found and fixed:**
  - **Review of task 8:** a stale friendship check could overwrite a newer one after a leave and rejoin. Fixed with a per-check token.
  - **Play Solo:** today's goals weren't drawn on join, because `ProfileLoaded` (a `BindableEvent`) passes a copy of the profile. `ProgressionService` now uses `GetData`, and `DataService` documents the copy.
- **Who did what:**
  - **DeepSeek Flash:** tasks 2, 3 and 8. 2 was accepted first time; 3 needed one comment fix; 8 needed the token fix. Every recovery journal was checked and acknowledged.
  - **Haiku:** task 4, accepted first time.
  - **Orchestrator:** tasks 0, 1, 5, 6, 7, 9 and 10, plus both bug fixes.
  - Nothing went to DeepSeek Pro.
- **Tests:** `lune run tests` gives **154 passed, 0 failed** (104 existing + 50 new). `stylua --check` is clean (Vendor skipped), and `rojo build` succeeds.
- **Each place checked:**

  | Where | What | Result |
  |---|---|---|
  | Studio Play Solo (your DEV profile) | Unlock, codex, shop refusals and buys, pedestal, daily, goals and claims, weekly best on the board | All passed except check 6 (surge, not checked) |
  | Studio Device Simulator (phone, landscape) | Board readable at Dark, Normal and Bright | Passed (your check; size kept) |
  | Studio local server, 2 players | Goals on join (the fix), friend bonus 0, no write for negative IDs, announcement to both | All passed |
  | Published DEV experience, your phone | New version, board readable, live request budgets | Passed. OrderedList 17, OrderedRead 215, OrderedWrite 102 |

- **Not verified:**
  - **The Crystal Surge in play** (plant during :00–:04 UTC). The unit tests prove the rule; the in-game check is statistical only.
  - **A real Molten or Prismatic announcement:** only the debug path, which calls the same `Announce`.
  - **A real friend bonus above 0:** it needs two Roblox accounts that are friends in one server.
  - **The Codex completion bonus in play** (all 4 variants of one crystal) and **`Toast.MaxLevel`** (pedestal 10 or lamp 5): covered by unit tests and code review only.
  - **The `BindToClose` flush:** not observed. In Studio the queue was empty or skipped at shutdown.
- **Leftovers:**
  - **Dev data:** your DEV profile is at tier 3 with pedestal 4, today's daily claimed and 954 coins. The DEV leaderboard `BiggestCrystal_2026W47` has your entry (2.00 ct). `Player_-1` and `Player_-2` were used.
  - **The DEV experience is published with batch 3.**
  - **Git:** committed as `c0d07d3` on `batch-3-progression`, pushed; pull request into `batch-1-setup`. The record fix is a follow-up commit.
  - **Still running:** the Rojo server on port 34872. The Device Simulator is still on.
  - **`rojo build` output** is in the session scratchpad, outside the repo.
- **Lessons:**
  - **`BindableEvent` arguments are copies;** change profiles only through `DataService:GetData`.
  - **The MCP command bar has its own module copies;** read live state from the client's remote events.
  - **`screen_capture` with a camera position drops `SurfaceGui` text.**
