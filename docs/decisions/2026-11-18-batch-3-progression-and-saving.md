# Specification: Batch 3, progression and saving (shop, upgrades, unlocks, codex, daily, social, leaderboard)

Status: approved 2026-11-18. Not started; implemented in its own session.

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
- **Budget guard:** before every leaderboard call, the request budget is checked, and that cycle is skipped if it is too low.
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
- **Task 7:** writes only when beating the weekly best; never for instant-grown crystals or `UserId <= 0`; `UpdateAsync` keeps the maximum; the budget is checked; the queue is flushed on shutdown; the board is updated after each read; nothing is called more often than the architecture allows.
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

## Decisions (confirmed by the user 2026-11-18, recommended options chosen)

1. **The Surprise Seed is the next tier's seed, not random.** Rejected: a random seed, which would need odds shown and could count as a random item.
2. **Goal rewards scale with your highest unlocked seed (×10 its base value).** Rejected: fixed coin amounts, which become worthless late in the game.
3. **The Growth Lamp affects only new plantings.** Rejected: re-timing crystals that are already growing, which is more complex and has a double-dip risk.
