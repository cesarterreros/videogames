# Specification: Crystal Grove technical architecture

Status: approved 2026-11-18.

## Context

The approved specs fix what the game does:
- [MVP](2026-11-18-crystal-grove-mvp.md): the loop, progression, retention hooks, 6-player servers.
- [Monetization](2026-11-18-crystal-grove-monetization.md): passes, products, rewarded ads, receipts.

This spec fixes **how it is built**, so every batch plan (1–6) follows the same structure and rules. The repository has only [docs/decisions/](README.md) so far; [roblox/](../../roblox/) is empty.

### Terms used here
- **Rojo:** a tool that syncs files from `roblox/` on disk into Roblox Studio, so the code lives in git.
- **Rokit:** installs pinned versions of command-line tools (Rojo, Lune, StyLua) per project.
- **Lune:** runs Luau scripts outside Roblox. We use it for unit tests.
- **ModuleScript:** a Luau file that returns a table and is loaded with `require`.
- **RemoteEvent / RemoteFunction:** the only channels between a player's device (client) and the server.
- **Session lock:** a marker saying "this player's data is open on server X", so a second server cannot load and overwrite it at the same time.
- **Service / Controller:** our names for a server module (Service) and a client module (Controller) that each own one area.

### Outside facts checked (2026-11-18)

- **Require by string** ([DevForum announcement](https://devforum.roblox.com/t/introducing-require-by-string/3405078)): Roblox now supports `require("./Module")`. Lune resolves the same strings relative to the *file*. The Rojo layout and the file system differ, so the same string can mean different things in the two places.
  **Decision:** pure logic and config modules contain **no `require` at all**. Tests load them by file path; game code loads them by instance. That way they work the same in both places.
- **ProfileStore** ([DevForum](https://devforum.roblox.com/t/profilestore/3190543), [repository listing](https://awesome.ecosyste.ms/projects/github.com%2FMadStudioRoblox%2FProfileStore)):
  - **Who:** the successor of ProfileService, by the same author.
  - **What it does:** session locking, auto-save and conflict handling in one `UpdateAsync` call.
  - **License:** Apache-2.0.
  - **Limit:** the author says it is **not** for leaderboards or global state.
- **DataStore limits** ([Error codes and limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits)), all per server per minute:

  | Request type | Budget |
  |---|---|
  | Standard reads and writes | 60 + 40 × players each |
  | Ordered writes | 30 + 5 × players (90 with 6 players) |
  | `GetSortedAsync` | 5 + 2 × players (17 with 6 players) |

  Keys can be up to 50 characters.
- **AnalyticsService, AdService, MarketplaceService:** the API names were checked in the monetization spec and are used unchanged.

## Behaviour

Players see no change from this spec itself. The rules below decide how the game behaves when something goes wrong.

- **Data won't load** (DataStore outage or a session lock held too long): the player is kicked with "Couldn't load your cave. Please rejoin in a minute." Nothing is ever saved over their data.
- **Data loads late:** every action from that player is ignored until their data is loaded. The client shows "Loading your cave…".
- **Server shuts down:** all profiles are saved and released before it closes. ProfileStore handles this with `game:BindToClose`.
- **Cheating client:** a request with wrong types, out-of-range numbers, someone else's pedestal, or too many requests per second is dropped silently and counted as an anomaly. It never changes data.
- **Text:** everything a player reads comes from one string table, so translation can be added later without code changes.

## Not included

- **Gameplay, UI and monetization code.** Those come in batches 2–6, each with its own plan.
- **Any Roblox translation (LocalizationTable) beyond English.** Only the string-table structure is built.
- **Cross-server messaging (MessagingService).** Server announcements of rare finds stay within one server in v1.
- **Packages via Wally.** The one library we use (ProfileStore) is copied into the repo with its license file, which keeps the toolchain small.
- **CI pipelines.** Tests run locally with `lune run tests`.

## Design

### Project structure (Rojo)

```
roblox/
  rokit.toml                 tool versions (rojo, lune, stylua), pinned in batch 1 task 1
  default.project.json       maps folders below into the Roblox data model
  stylua.toml                formatting
  src/
    shared/      → ReplicatedStorage.Shared
      Config/    pure data tables, NO requires: Seeds, Rolls, Economy, Progression, Monetization, Game
      Logic/     pure functions, NO requires (config passed as arguments)
      Strings/   en.luau (key → English text) + Strings.luau (lookup with {placeholders})
      Net/       Remotes.luau: the list of remote names and argument schemas (a pure table)
    server/      → ServerScriptService.Server
      Main.server.luau       the only server Script: requires and starts services in order
      Services/  one ModuleScript per area (see the build order below)
      Vendor/    ProfileStore.luau + LICENSE (Apache-2.0)
    client/      → StarterPlayer.StarterPlayerScripts.Client
      Main.client.luau       the only LocalScript: starts controllers in order
      Controllers/
      UI/        UI components built in code (no Studio-made ScreenGuis in v1)
  tests/
    run.luau                 Lune entry: finds and runs every *.spec.luau, prints pass/fail, exits 1 on failure
    lib/expect.luau          small assertion helper
    *.spec.luau
```

- **Map:** the hub, caves and pedestals are built **by code** at server start (`MapService`, batch 2) from simple parts, so the map lives in git and stays procedural like the crystals. Only Lighting settings and the spawn are set in code too. The place file holds nothing that git doesn't know about.
- **Service pattern:**
  - **Server:** every Service is a ModuleScript returning a table with `:Init()` (wire up, no yielding) and `:Start()` (may yield). `Main.server.luau` calls every `Init` in build order, then every `Start`.
  - **Client:** Controllers use the same pattern.
  - **Communication:** services talk to each other by requiring each other directly, without a framework.

### Server/client split

| Concern | Server | Client |
|---|---|---|
| Coins, seed bag, pedestals, upgrades, codex, streak, goals | **Owns and saves** | Displays the snapshot it receives |
| Rolls (size, mutation), timers, prices, coin amounts | **Decides** (`os.time()`, `Random.new()`) | Never computes any of it |
| Crystal visuals and growth animation | Sets **attributes** on each pedestal: `SeedId`, `PlantedAt`, `ReadyAt`, `Mutation` (size stays secret) | **Builds and animates** the crystal parts locally from the attributes; plays shatter effects |
| Pass ownership, receipts, ad caps | **Owns** | Shows buttons; reads prices with `GetProductInfo`; checks `GetAdAvailabilityNowAsync` |
| Leaderboard | Reads and writes the OrderedDataStore; puts the top 10 in a `StringValue` (JSON) | Renders the board |
| Input | Validates every request | Sends intents only |

**Why the client builds crystals:** with 60 crystals × 3–7 prisms each, animating them on the server would send a constant stream of updates. Each client builds them from 4 attributes per pedestal instead, which is cheap on the network and on the server.

### Data architecture

**Player profiles (ProfileStore):**
- **Store and key:** store name `PlayerData`, key `Player_<UserId>`. The dev and live experiences are separate universes, so they never share data.
- **On join:**
  1. `StartSessionAsync` loads the profile with session locking.
  2. `Reconcile()` fills any missing fields from the template.
  3. `Migration.migrate(data)` upgrades older versions.
  4. If the player left while their data was loading, the session is ended immediately.
- **Saving:** auto-save comes from ProfileStore. On leave, `EndSession()` saves and releases the lock. After a purchase grant, the receipt handler calls `profile:Save()` and waits for it (batch 5).
- **Retries:** ProfileStore handles these. Our own extra rule: if loading fails, the player is kicked and nothing is written.
- **Safe defaults:** the template below is the only source of defaults, and it is unit-tested.

**Profile schema, version 1.** This is the **shared contract** for every batch.

```lua
{
  Version = 1,
  Coins = 0,
  SeedBag = { Quartz = 1 },              -- [seedId] = count
  Pedestals = {},                          -- ["1".."13"] = Crystal (string keys: no array holes)
  UnlockedPedestals = 3,                   -- coin-bought pedestals, max 10
  LampLevel = 0,                           -- 0..5
  HighestUnlockedTier = 1,                 -- 1..10
  Codex = {},                              -- [seedId] = { None=true, Glowing=true, ... }
  Stats = { Shatters = 0, CoinsEarned = 0 },
  Streak = { Day = 0, LastClaimDate = "" },          -- "YYYY-MM-DD" UTC
  DailyGoals = { Date = "", Goals = {}, BonusClaimed = false },
                                           -- Goals = { {Id=string, Progress=number, Claimed=boolean} } x3
  WeeklyBest = { WeekId = "", Carats = 0 },          -- "2026W47"
  Tutorial = { Step = 0, Done = false },
  Monetization = {
    ProcessedReceipts = {},                -- last 100 PurchaseIds
    InstantGrowTokens = { S = 0, M = 0, L = 0 },
    LuckBoostEndsAt = 0,
    StarterPackBought = false,
    AdCounts = { Date = "", FinishNow = 0, Luck = 0, CoinPouch = 0 },
    LastAdAt = 0,
  },
  Settings = { AutoShatter = false, Music = true },
  FirstJoinAt = 0, LastJoinAt = 0, Sessions = 0,
}
-- Crystal = { SeedId=string, PlantedAt=number, ReadyAt=number, SizeRoll=number,
--             Mutation="None"|"Glowing"|"Molten"|"Prismatic", InstantGrown=boolean, Shape=number }
```

**Weekly leaderboard (OrderedDataStore, not ProfileStore):**
- **Store and key:** one store per week, `BiggestCrystal_<WeekId>` (for example `BiggestCrystal_2026W47`). Key: the player's `UserId` as a string. Value: `math.floor(carats * 100)`.
- **Writes:** only when a shatter beats the player's `WeeklyBest`. Pending writes are queued and flushed every 30 seconds with `UpdateAsync`, keeping the larger value. At most about 12 writes per minute with 6 players, against a budget of 90.
- **Reads:** `GetSortedAsync(false, 10)` every 120 seconds, against a budget of 17 per minute. Names are resolved with `UserService:GetUserInfosByUserIdsAsync` and cached.
- **Budget guard:** before any non-urgent DataStore call, check `DataStoreService:GetRequestBudgetForRequestType`, and skip this cycle if the budget is low.

### Remote security rules

1. **Remotes are created only by the server**, from the list in `Shared/Net/Remotes.luau`, in a `ReplicatedStorage.Remotes` folder. The client waits for them.
2. **Client → server** uses RemoteEvents. Client → server RemoteFunctions are allowed only where the client needs an answer (for example asking which Instant Grow product applies). **Server → client RemoteFunctions (`InvokeClient`) are never used**, because a client can hang them forever.
3. **Every handler is registered through `RemoteService:On(name, handler)`**. Before the handler runs, it:
   1. checks the profile is loaded;
   2. applies a per-player, per-remote **rate limit** (a token bucket from `Remotes.luau`, default 8 per second with a burst of 12);
   3. **validates the arguments against the schema** for that remote (type, integer, range, a value from a fixed list such as a seed ID);
   4. wraps the handler in `pcall`, so an error in one request can't break the service.

   Rejected calls are counted per player. More than 50 in a minute logs an `Anomaly` analytics event. Players are **not kicked automatically** in v1, so honest players with lag are never punished.
4. **The client never sends amounts, prices, rolls, times or user IDs.** It sends indexes and IDs, and the server looks up everything else.
5. **Ownership:** every pedestal action checks that the pedestal belongs to the caller's plot.

**Remote list.** Names are fixed now; each is implemented in the batch shown.

| Remote | Kind | Arguments | Batch |
|---|---|---|---|
| `StateSync` | Event, server → client | `snapshot` (the player's public profile fields) | 1 |
| `Toast` | Event, server → client | `stringKey, params` | 1 |
| `Plant` | Event | `pedestal: int 1–13, seedId: SeedId` | 2 |
| `Shatter` | Event | `pedestal: int 1–13` | 2 |
| `ShatterAll` | Event | — | 2 |
| `ShatterResult` | Event, server → client | `{pedestal, coins, carats, mutation, newBest, instantGrown}` | 2 |
| `BuySeed` | Event | `seedId: SeedId, qty: 1 or 5` | 3 |
| `BuyUpgrade` | Event | `kind: "Pedestal" or "Lamp"` | 3 |
| `ClaimDaily` | Event | — | 3 |
| `ClaimGoal` | Event | `index: int 1–3` or `"Bonus"` | 3 |
| `Announce` | Event, server → client | `stringKey, params` | 3 |
| `TutorialAction` | Event | `step: int 1–8` (the server only accepts the expected next step) | 4 |
| `SetSetting` | Event | `key: "AutoShatter" or "Music", value: boolean` | 4 / 5 |
| `RequestInstantGrow` | Function | `pedestal: int 1–13` → `productId` or `nil` | 5 |
| `UseToken` | Event | `pedestal: int 1–13` | 5 |
| `RequestAd` | Event | `placement: "FinishNow", "Luck" or "CoinPouch"; pedestal?: int` | 5 |

### Anti-exploit considerations

- **Speed and teleport hacks** gain nothing: no action depends on where the player is standing, and walking is only for looking around.
- **Auto-clickers** gain only what the "Shatter All" button already gives. The rate limit caps them.
- **Remote spam and fuzzing** are stopped by rule 3. **Duplication bugs** are prevented because grants are server-side and receipts are recorded.
- **Time manipulation is impossible:** only the server's `os.time()` is used.
- **Leaderboard faking is impossible:** carats are computed on the server from stored rolls, and instant-grown crystals are excluded.
- **Profile sanity:** after loading, `Migration.sanitize(data)` clamps impossible values, such as negative coins, more than 13 pedestals or unknown seed IDs, and logs them.

### Localization-ready text

- **Lookup:** all player-visible text goes through `Strings.get(key, params)`. Keys look like `Shop.Title` and `Toast.NotEnoughCoins`, and placeholders like `{coins}`.
- **No hard-coded text:** no UI code contains literal English text, and a search check enforces this.
- **Numbers:** they are formatted by `Logic/Format.luau` (12.4K, 3.1M). Translations can replace the suffixes later.
- **Later:** add a LocalizationTable or Roblox automatic translation. The string keys stay the same.

### Analytics events

They all go through one `AnalyticsService` wrapper, `Services/Analytics.luau`, which also enforces Roblox's limits (5 currency types, 20 transaction types, 100 item SKUs, 10 funnels).

| Event | Call | Batch |
|---|---|---|
| Onboarding steps 1–8 | `LogOnboardingFunnelStepEvent` | 4 |
| Coin sources and sinks | `LogEconomyEvent` | 2–3 |
| Seed tier unlocked | `LogProgressionEvent` | 3 |
| MutationFound, WeeklyBest, StreakClaim, GoalsComplete, SessionEnd | `LogCustomEvent` | 2–4 |
| OfferShown, OfferPurchased, AdRequested, AdRewarded, PassPurchased | `LogCustomEvent` | 5 |
| FirstPurchase funnel | `LogFunnelStepEvent` | 5 |
| Anomaly | `LogCustomEvent` | 1 |

### Build order (scripts, modules, assets)

| # | Item | Batch |
|---|---|---|
| 1 | `rokit.toml`, `default.project.json`, `stylua.toml`, `.gitignore`, test runner | 1 |
| 2 | `Config/*` (all balance data from the approved specs) | 1 |
| 3 | `Logic/ProfileTemplate`, `Logic/Migration`, `Logic/WeekId`, `Logic/Format`, `Logic/RateLimiter`, `Logic/Validate` | 1 |
| 4 | `Strings/en`, `Strings/Strings`, `Net/Remotes` | 1 |
| 5 | `Vendor/ProfileStore` + LICENSE | 1 |
| 6 | `Services/DataService`, `Services/RemoteService`, `Services/Analytics`, `Main.server` | 1 |
| 7 | `client/Main.client`, `Controllers/StateController` (receives `StateSync`) | 1 |
| 8 | `Logic/Growth`, `Logic/Rolls`, `Services/MapService`, `Services/PlotService`, `Services/CrystalService`, `Controllers/CrystalRenderer`, `Controllers/EffectsController` | 2 |
| 9 | `Logic/Economy`, `Logic/Streak`, `Logic/Goals`, `Logic/Codex`, `Services/ShopService`, `Services/ProgressionService`, `Services/LeaderboardService`, `Services/SocialService` (friend bonus, announcements), `Services/SurgeService` | 3 |
| 10 | `UI/*` (HUD, Shop, Upgrades, Codex, Daily, Goals, Toasts, Result, Odds), `Controllers/UIController`, `Services/TutorialService`, `Controllers/TutorialController`, sounds | 4 |
| 11 | `Logic/Receipts`, `Logic/AdCaps`, `Services/PassService`, `Services/ReceiptService`, `Services/RewardedAdService`, `Services/OfferService`, Store UI | 5 |
| 12 | Polish (juice, lighting), analytics completion, anti-exploit review, a dev-only admin command, launch checklist | 6 |
| Assets | Sound IDs from Roblox's licensed library (batch 4); pass and product icons at 512×512 (monetization task 2); thumbnails and icon (Step 5, day 6) | — |

### Files

This spec creates only itself. Each batch plan lists its own files.

## Task breakdown and model assignment

| # | Task | Model | Depends on |
|---|---|---|---|
| 0 | Save this decision record | Orchestrator | — |
| 1 | Batch 1 implementation plan (separate record) | Orchestrator | 0 |
| 2–7 | Batches 1–6 | Set in each batch plan | In order |

Escalation: if a batch shows a rule here doesn't work (for example ProfileStore's API differs from what is assumed), the batch adds a dated **findings** section to this record with corrections, rather than quietly diverging.

### Acceptance criteria

- Every later batch plan follows the folder layout, the service pattern, the profile schema, the remote list and the security rules above. Any change to them is recorded as an amendment here first.

## Verification

This is an architecture record. It is verified through batch 1, which proves the toolchain, the profile load and save with session locking, the remote rules and the tests.

## Decisions for you before approval

1. **Use ProfileStore** (Apache-2.0, widely used, copied into the repo) for session-locked player data. Alternative: our own session-locking code. That is more code to get exactly right, with no gain in behaviour. **Recommended: ProfileStore.**
2. **Map built by code** at server start. Alternative: build the hub and caves by hand in Studio, which looks richer but keeps the map outside git and needs your Studio time. **Recommended: code for v1**, with hand-built decoration as an optional polish later.
3. **Crystals rendered on each client** from pedestal attributes. Alternative: the server builds the parts, which is simpler but heavy on the network for growth animation. **Recommended: client-rendered.**

## Decisions (confirmed by the user 2026-11-18)

1. **ProfileStore** (copied into the repo with its Apache-2.0 license) handles session-locked player data. Rejected: our own session-locking code.
2. **The map is built by code** at server start. Rejected: a hand-built Studio map for v1.
3. **Crystals are rendered on each client** from pedestal attributes. Rejected: server-built crystal parts.
