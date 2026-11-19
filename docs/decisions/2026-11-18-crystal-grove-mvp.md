# Specification: Crystal Grove MVP (first shippable version)

Status: approved 2026-11-18.

## Context

You are starting a new Roblox game from an empty repository ([roblox/](../../roblox/) has no files yet). You chose the **Grow & Collect Incremental** genre and the **Crystal Grove** idea: players grow glowing crystals in their own cave, shatter them for coins, buy rarer seeds and more pedestals, hunt rare mutations, and compete on a weekly **Biggest Crystal** leaderboard.

Constraints you set:

- **Workflow:** Rojo + VS Code. Source files live in `roblox/` and sync into Studio.
- **Art:** procedural only. Crystals are built by code from Neon and Glass parts, lights and particles. No custom meshes.
- **Audience:** all ages, with a 9–15 core. UI is icon-heavy with very little reading.
- **Fairness:** crystal **size** comes from luck and time only. Anything bought may make crystals **grow faster**, never **bigger**.
- **Ship in days:** a small, polished loop beats a long feature list.

This spec covers the **product** only. Monetization (game passes, developer products, rewarded ads) and the technical architecture each get their own spec later (Steps 4 and 6). This MVP spec only reserves places in the UI for them.

### Outside facts checked (2026-11-18)

- **Rewarded video ads** ([Creator Hub: Rewarded video ads](https://create.roblox.com/docs/production/promotion/rewarded-video-ads)): an experience only qualifies once it is public, averages **at least 2,000 unique visitors per month**, has an approved maturity questionnaire, and has no free-form user creation or private social hangouts. The publisher needs 2-step verification and ID verification. Ads are 6–30 seconds. The reward must be a **developer product** that is normally sold in the shop, must **not be randomized**, and must be granted immediately after the ad finishes.
  **What this means for the plan:** the game **cannot show rewarded ads on day 1**. Every ad button is hidden until the ad is actually available, and every ad reward has a non-ad path. Before launch, the monetization spec (Step 4) must design for this.
- **AdService** ([reference](https://create.roblox.com/docs/en-us/reference/engine/classes/AdService.md)): the client calls `GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)`. The server calls `CreateAdRewardFromDevProductId` and `ShowRewardedVideoAdAsync`. The reward arrives through `MarketplaceService.ProcessReceipt`.
- **DataStore limits** ([Error codes and limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits)), per server per minute:
  - Standard reads and writes: 60 + 40 × players each.
  - Ordered writes: 30 + 5 × players.
  - Ordered list reads (`GetSortedAsync`): 5 + 2 × players.
  - Keys can be at most 50 characters, and values at most 4 MB.
- **AnalyticsService** ([reference](https://create.roblox.com/docs/en-us/reference/engine/classes/AnalyticsService.md)): `LogOnboardingFunnelStepEvent`, `LogFunnelStepEvent`, `LogEconomyEvent`, `LogProgressionEvent`, `LogCustomEvent`. Limits per experience: 10 funnels, 5 currency types, 20 transaction types, 100 item SKUs.

## Behaviour

### Title options (10)

These avoid the naming pattern of existing hits (no "Grow a ___"). Before you pick one, search Roblox and a trademark database for it.

| # | Title | Angle |
|---|---|---|
| 1 | **Crystal Grove** 💎 | Brand name, clean |
| 2 | Grow Glowing Crystals | Says the verb and the reward |
| 3 | Crystal Cave Collector | Collection fantasy |
| 4 | Shatter Crystals! | The satisfying action |
| 5 | My Crystal Cave | Ownership |
| 6 | 1 in 10,000 Crystal | Rarity hook |
| 7 | Giant Crystal Hunt | Size competition |
| 8 | Glow Gem Grove | Bright, kid-friendly |
| 9 | Crystal Grove: Rare Gems | Brand plus hook |
| 10 | Gem Grower Cave | Plain search keywords |

**Recommendation:** use **Crystal Grove 💎** as the permanent name. Test hook variants (for example "Crystal Grove 💎 [1 in 10,000!]") in the title after launch (Step 8).

### Product vision and target player

- **Vision:** "Every crystal could be the one." A calm, glowing cave you own, where every shatter is a small lottery moment and a giant rare crystal is something to show off.
- **Target player:** ages 9–15, mostly on phones, short sessions (5–15 minutes), several visits a day. They like collecting, rare reveals, and watching numbers go up.
- **Secondary:** older collectors who chase the weekly leaderboard.

### Core loop (every 30–90 seconds)

1. **Plant:** tap an empty pedestal and pick a seed from your seed bag.
2. **Grow:** the crystal visibly grows on the pedestal, with a countdown above it.
3. **Shatter:** when it's ready, it pulses. Tap it and it bursts into shards, and coins fly to your counter. **Shattering sells the crystal at once.** There is no separate selling station.
4. **Reveal:** the result popup shows the coins earned, the size in carats ("14.2 ct"), any mutation, and "NEW BEST!" when it beats your weekly best.
5. **Spend:** buy seeds and pedestal or lamp upgrades, then plant again.

### Seeds (the starting values live in a config file and get tuned after launch)

| # | Crystal | Rarity | Seed price | Grow time | Base value | Base size (ct) |
|---|---|---|---|---|---|---|
| 1 | Quartz | Common | 10 | 20 s | 15 | 1.0 |
| 2 | Amethyst | Common | 40 | 45 s | 60 | 1.5 |
| 3 | Citrine | Uncommon | 150 | 2 min | 240 | 2.5 |
| 4 | Rose Quartz | Uncommon | 500 | 5 min | 800 | 4 |
| 5 | Emerald | Rare | 2,000 | 15 min | 3,500 | 6 |
| 6 | Sapphire | Rare | 7,500 | 30 min | 13,000 | 9 |
| 7 | Ruby | Epic | 30,000 | 1 h | 55,000 | 14 |
| 8 | Moonstone | Epic | 120,000 | 2 h | 230,000 | 20 |
| 9 | Starfire Opal | Legendary | 500,000 | 4 h | 1,000,000 | 30 |
| 10 | Voidheart | Legendary | 2,500,000 | 8 h | 5,500,000 | 45 |

- **Rarity colours:** Common grey-white, Uncommon green, Rare blue, Epic purple, Legendary gold. The same colours are used everywhere in the UI.
- **Seed shop:** every seed is always in stock. In v1 a seed becomes buyable once you have shattered at least one crystal of the tier below it. Locked seeds show a silhouette and "Shatter a ___ to unlock".

### Rolls: size, mutation, overgrowth

The server rolls these **when the crystal is planted** and stores them. The client only learns them when the crystal is shattered, so they can't be peeked at or rerolled.

- **Size roll (multiplies both carats and value):**

  | Tier | Multiplier | Chance |
  |---|---|---|
  | Normal | 1.0–1.4 | 88% |
  | Big | 1.4–2.0 | 10% |
  | Huge | 2.0–4.0 | 1.8% |
  | Colossal | 4.0–8.0 | 0.2% |

- **Mutation roll (multiplies value only, not carats):**

  | Mutation | Value multiplier | Chance |
  |---|---|---|
  | Glowing | ×2 | 6% |
  | Molten | ×5 | 1.2% |
  | Prismatic | ×20 | 0.15% |
  | None | ×1 | the rest |

  Mutations are visible while the crystal grows (colour, particles), which is part of the show-off moment. The size stays hidden until the shatter.
- **Overgrowth (the time factor):** a ready crystal that is left unshattered keeps growing: +10% carats and value per hour, up to +50% after 5 hours. This creates a real choice between shattering now and coming back later. **Speed boosts never apply to overgrowth**, so money can't buy size.
- **Final size:** carats = base size × size roll × overgrowth factor. Shown with one decimal.

### Player progression

- **Coins:** the only currency in v1.
- **Seed tiers:** 10 crystals unlocked one after another (see the table).
- **Pedestals (slots):** you start with 3, up to 10. The 4th through 10th cost 100, 500, 2,000, 8,000, 30,000, 120,000 and 500,000 coins.
- **Growth Lamp:** 5 levels, each −5% grow time (−25% at most). Costs 1,000; 10,000; 100,000; 1,000,000; 5,000,000. It speeds up growth only, never overgrowth.
- **Crystal Codex (collection):** 10 crystals × 4 variants (no mutation, Glowing, Molten, Prismatic) = 40 entries. Completing all 4 variants of a crystal gives a permanent +10% value bonus for that crystal. Undiscovered entries show as dark silhouettes.

### Retention hooks

| Hook | v1 behaviour |
|---|---|
| **Offline growth** | Crystals grow on real time (server timestamps). Epic and Legendary crystals take 1–8 h, so they finish while you're away. |
| **Daily streak** | A 7-day cycle based on the UTC date: day 1: 100 coins, day 2: 250, day 3: a free Citrine seed, day 4: 1,000, day 5: 2,500, day 6: 5,000, day 7: a free Emerald seed. Missing a day resets the streak to day 1. A popup appears on the first join of the day. |
| **Daily goals** | 3 goals per day, drawn from a pool of 6 (shatter 20 crystals; plant 5 Uncommon or better; find 1 mutation; earn 5,000 coins; buy an upgrade; shatter a Big or larger crystal). Each pays coins scaled to your best unlocked seed. Finishing all 3 gives 1 Surprise Seed, a random seed one tier above your best. |
| **Collection** | Codex silhouettes and per-crystal completion bonuses. |
| **Upgrades** | Pedestals and Growth Lamp. |
| **Social** | (a) **Friend bonus:** +10% coins for each Roblox friend in the server, up to +30%. (b) **Server announcements** for Molten, Prismatic and Colossal finds. (c) You can walk into other players' caves to look (no interaction). (d) The weekly leaderboard. |
| **Event** | **Crystal Surge:** during the first 5 minutes of every UTC hour, mutation chances are doubled for crystals planted then. A countdown in the HUD shows when the next surge starts. |
| **Weekly leaderboard** | **Biggest Crystal This Week:** your largest shattered crystal in carats, global. It resets Monday 00:00 UTC. It is shown on a large board in the hub, top 10, refreshed every 2 minutes. Your own weekly best is shown in the HUD. No prizes in v1 (see Not included). |

### Map and layout

- **Server size:** 6 players, so 6 cave plots.
- **Hub (centre):** spawn point, Seed Shop stall, Upgrade stall, the Biggest Crystal leaderboard board, and a decorative giant "Heart Crystal".
- **Caves:** 6 cave mouths arranged in a ring around the hub, each about 15 seconds' walk from the hub. Each cave has an owner sign (avatar headshot and name) and 10 pedestals in a 2 × 5 grid. Locked pedestals are dim stone with a padlock and price.
- **Spawn:** you appear **inside your own cave** (not in the hub), so the first action is right in front of you.
- **Travel:** HUD buttons "My Cave" and "Shop" teleport you instantly. You can also walk.
- **Lighting:** dark cave ambience (blue-purple), with crystals as the main light source.
- **Performance budget:** at most 1 PointLight per Epic or Legendary crystal. Lower tiers use only Neon material, which glows without a light. At most 1 ParticleEmitter per crystal. The proof is task 1.

### UI screens and user flows

All buttons use Scale sizing with a minimum touch size of 48 × 48 px. Icons come first, with short labels (at most 2 words).

| Screen | Content | Opens from |
|---|---|---|
| **HUD** | Top centre: coin counter. Left side: My Cave, Shop, Upgrades, Codex. Right side: Daily (with a red dot when claimable), Goals, Surge countdown. Top right: weekly best ("🏆 18.4 ct"). Bottom right: an empty slot reserved for the monetization spec. | Always visible |
| **Seed picker** | Horizontal strip of owned seeds with counts; tap one to plant it. | Tapping an empty pedestal |
| **Crystal billboard** | Above each crystal: countdown, or "READY!" with a pulse, and a mutation icon. | World |
| **Shatter result** | Popup for 2 seconds: "+12,400", "14.2 ct", mutation badge, "NEW BEST!". It doesn't block play. | Shattering |
| **Seed Shop** | Grid of 10 seed cards: crystal colour, price, grow time, lock state. One tap buys 1; a "×5" button buys 5. | HUD or the hub stall |
| **Upgrades** | Two cards: Pedestals (next slot price) and Growth Lamp (next level). | HUD or the hub stall |
| **Codex** | 10 × 4 grid with silhouettes and per-crystal bonus progress. | HUD |
| **Daily reward** | 7 day tiles, today highlighted, a "Claim" button. | Automatically on the first join of the day, and from HUD |
| **Daily goals** | 3 goal rows with progress bars and claim buttons; the Surprise Seed when all 3 are done. | HUD |
| **Toast** | Short messages at the top: server announcements, "Not enough coins", "Seed unlocked!". | System |
| **Leaderboard board** | 3D SurfaceGui in the hub: rank, avatar, name, carats, crystal type. | World |

**Main flow:** join → (daily popup) → in your cave → tap a pedestal → pick a seed → wait or explore → tap the ready crystal → result → Shop → buy → plant.

### Sound and visual style

- **Visual:** high-contrast glow against darkness. Crystals are a cluster of 3–7 angled hexagonal prisms (Neon core inside a Glass shell), and the cluster shape is generated from the crystal type plus a random seed, so every crystal looks a little different. Post-processing: Bloom, Atmosphere and ColorCorrection, kept moderate for mobile. The UI uses rounded corners, chunky outlined text, and the rarity colours.
- **Feel ("juice"):** growing crystals scale up with an easing curve; a ready crystal pulses; shattering bursts into 6–10 shard parts that fade out within 1 s; coins fly to the HUD counter, which ticks up; Huge or larger crystals add a short camera shake.
- **Sound:** only Roblox's licensed audio library and sounds you make yourself. Glass "ting" on shatter (pitch rises with rarity), coin clink, rising chime when a crystal is ready, fanfare for mutations and NEW BEST, soft cave drips and wind as ambience, and one calm licensed music loop with a mute toggle.

### Mobile-first controls

- **Tap to act:** each pedestal and crystal has a `ProximityPrompt` (on a phone you tap the prompt; on PC you press E; on a gamepad you press a button). Activation range is 10 studs. On mobile, crystals in your own cave can also be tapped directly with a `ClickDetector`, so you don't have to stand next to each one.
- **"Shatter All Ready" button:** appears in the HUD when 2 or more crystals are ready. It shatters every ready crystal in your cave at once, which saves a lot of tapping on a phone.
- **No precise platforming, no keyboard-only actions.** Landscape layout; nothing important in the bottom-left (Roblox's thumbstick) or the top-left (Roblox menu buttons).

### Onboarding: the first 60 seconds (new players only)

| Time | What happens | Analytics step |
|---|---|---|
| 0 s | You spawn in your own cave. One free Quartz seed is in your bag, and a glowing arrow points to pedestal 1. | 1 Spawned |
| ~5 s | You tap the pedestal and plant. This tutorial Quartz grows in **8 s** (instead of 20). | 2 Planted |
| ~15 s | "READY!" pulse, and the arrow points at the crystal. You tap it; shards and coins burst out; you get +50 coins (tutorial bonus). | 3 FirstShatter |
| ~20 s | The arrow points to the Shop button, with a "Buy seeds!" bubble. | 4 OpenedShop |
| ~25 s | You buy 2 Quartz seeds (you can afford 5). | 5 BoughtSeed |
| ~30 s | Back in your cave, you plant both. | 6 PlantedTwo |
| ~45 s | Second and third shatters. **The third shatter is a guaranteed Glowing mutation** ("Lucky! GLOWING ×2"), so every new player sees the rare moment once. | 7 FirstMutation |
| ~55 s | Tip bubble: "Rare crystals keep growing while you're offline!" The tutorial ends and the daily-reward popup appears (day 1). | 8 TutorialDone |

You can't skip the tutorial, but it only blocks the HUD buttons it isn't currently pointing at. Players who return before finishing continue at the step they reached.

### Analytics events and success metrics

| Event | API | When |
|---|---|---|
| Onboarding steps 1–8 | `LogOnboardingFunnelStepEvent` | Each step above |
| Coins in (sources: Shatter, Daily, Goal) | `LogEconomyEvent` (Source) | Each grant |
| Coins out (sinks: Seed, Pedestal, Lamp) | `LogEconomyEvent` (Sink), `itemSku` = seed or upgrade ID | Each purchase |
| Seed tier unlocked | `LogProgressionEvent`, path "SeedTier", level 1–10 | When a new tier unlocks |
| Mutation found | `LogCustomEvent` "MutationFound", value = multiplier | Each mutation |
| Weekly best set | `LogCustomEvent` "WeeklyBest", value = carats | Each new weekly best |
| Daily streak claimed | `LogCustomEvent` "StreakClaim", value = day | Claim |
| Daily goals completed | `LogCustomEvent` "GoalsComplete" | All 3 done |
| Session length | `LogCustomEvent` "SessionEnd", value = minutes | On leaving |

**Success metrics for the MVP** (Roblox Creator Dashboard):

| Metric | Fail | OK | Good |
|---|---|---|---|
| Tutorial completion (step 8 / step 1) | < 70% | 70–85% | > 85% |
| D1 retention | < 10% | 10–20% | > 20% |
| D7 retention | < 2% | 2–5% | > 5% |
| Average session length | < 6 min | 6–12 min | > 12 min |
| Sessions per daily user | < 1.3 | 1.3–2 | > 2 |

The monetization KPIs (conversion rate, ARPDAU, ad engagement) are set in the monetization spec and the launch plan.

### Edge cases

- **Server full:** at most 6 players, so there is always a free plot. Matchmaking handles overflow by sending players to other servers.
- **Player leaves:** their plot is cleared and released. Their crystals live on in their saved data with timestamps, so they keep growing offline.
- **Rejoining quickly into another server:** data is locked to one server at a time (session locking). The details are in the architecture spec.
- **Save fails:** the game retries with backoff. If loading fails, the player sees "Couldn't load your cave, rejoining…" and **nothing is saved** for that session, so a failed load can never overwrite good data.
- **Clock changes:** all timers use the server's `os.time()`, never the client's clock.
- **Not enough coins:** a toast message and a short shake of the button. Nothing else happens.
- **Very large numbers:** coins are shown with suffixes (12.4K, 3.1M, 2.5B). Values stay below 2^53, the largest whole number Luau stores exactly.
- **Week rollover during a session:** the leaderboard key is computed at each write from the shatter time, so records always go to the correct week.

## Not included (v1)

- **Monetization implementation:** game passes, developer products and rewarded ads are the next spec (Step 4). They are **required before launch**, not after. v1 UI only reserves their slots.
- **Rewarded ads on day 1:** not possible until the experience meets Roblox's 2,000-monthly-visitor eligibility. They will be wired up but hidden until available.
- **Leaderboard prizes:** a crown or nameplate for last week's top players. Planned for v1.1 when the data shows the board gets engagement.
- **Trading, gifting, pets, rebirth/prestige, a second currency, crafting or fusing crystals.**
- **Rotating shop stock, cave decoration, multiple worlds, quests beyond the 3 daily goals.**
- **Interacting with other players' crystals** (stealing, helping). You can only look.
- **Languages other than English.** All text goes through a string table so translation can be added later.
- **Custom meshes, animated characters, voice or chat features.**
- **Admin panel.** A minimal dev-only command for testing comes in a later batch.

## Design

This is the product spec. The technical design (folders, modules, the DataStore schema with session locking, remote events, anti-exploit rules) is its own spec in Step 6. Fixed here so later specs follow it:

- **Server authority:** the server decides every roll, timer, price and coin change. The client only sends intents ("plant seed X on pedestal N", "shatter pedestal N", "buy item Y") and plays the effects.
- **Pure game logic** (growth timing, rolls, overgrowth, prices, week ID, streak and goal logic) lives in testable modules under `src/shared/Logic/`. All balance numbers live in one config module (`src/shared/Config/`), so tuning after launch means editing data, not logic.
- **Stored data:** a new player profile, `Version = 1`: coins, seed bag, pedestals (seed ID, planted-at time, stored rolls), slots, lamp level, codex, streak, daily goals, weekly best, tutorial step. Leaderboard: an OrderedDataStore per ISO week, named `BiggestCrystal_<YYYY>W<WW>`, value = carats × 100 (whole number). Exact fields come in the architecture spec.

### Files

Defined in the architecture spec and the per-batch implementation plans. This spec creates only itself.

## Task breakdown and model assignment

This spec is implemented through the six batches you defined. **Each batch gets its own narrow implementation plan (via `/write-spec`) and your approval before any code.** The per-file model assignments are set in each plan.

| # | Task | Model | Depends on |
|---|---|---|---|
| 0 | Save this decision record | Orchestrator | — |
| 1 | **Proofs:** (a) install Rokit, Rojo and Lune, run `rojo serve` with Studio and a trivial `lune run tests`; (b) create the dev experience and enable Studio API access to DataStores; (c) **performance stress place:** 6 plots × 10 Epic crystals (Neon + Glass + 1 PointLight + 1 ParticleEmitter each) plus Bloom, on the emulator and on a real phone. Target ≥ 30 FPS. | Orchestrator (you run the Studio and phone steps) | — |
| 2 | Monetization spec (Step 4) | Orchestrator | 0 |
| 3 | Technical architecture spec + batch 1 plan (Step 6) | Orchestrator | 1, 2 |
| 4 | Batch 1: project setup and core data architecture | Set in its plan | 3 |
| 5 | Batch 2: core gameplay loop (plant, grow, shatter, rolls) | Set in its plan | 4 |
| 6 | Batch 3: progression and saving (shop, upgrades, codex, streak, goals, leaderboard) | Set in its plan | 5 |
| 7 | Batch 4: UI and onboarding | Set in its plan | 6 |
| 8 | Batch 5: monetization (passes, products, rewarded ads) | Set in its plan | 7, 2 |
| 9 | Batch 6: polish, analytics, anti-exploit hardening, launch checklist | Set in its plan | 8 |

Escalation: if a batch fails review, it goes back once with the specific defects, then to a stronger model, or the orchestrator fixes it. **If proof 1(c) runs below 30 FPS on the phone:** remove PointLights from Epic crystals (Legendary only), lower particle rates, and cap visible pedestals at 8. If it is still too slow, drop the Glass shell and use Neon only.

### Prioritized day 1–7 plan

| Day | Goal | Done when |
|---|---|---|
| 1 | Proofs (task 1); monetization and architecture specs approved; batch 1 (project, config, data, session locking) | Profile loads, saves and survives a rejoin in the dev experience |
| 2 | Batch 2: core loop | Plant → grow → shatter → coins works in Play Solo and on a 2-player server |
| 3 | Batch 3: progression | Shop, pedestals, lamp, codex, streak, goals and leaderboard work and persist |
| 4 | Batch 4: UI and onboarding | Every screen works in the phone emulator; the 60-second tutorial plays through |
| 5 | Batch 5: monetization | Passes and products work with test purchases in Studio; the ad button stays hidden when ads are unavailable |
| 6 | Batch 6: polish, analytics, hardening; thumbnail and icon made (Step 5) | Launch checklist complete in the dev experience |
| 7 | Real-phone test session with 2–3 people; fix blockers; publish to the live experience | Launch acceptance criteria below met |

### Acceptance criteria for launch

- **Core loop:** a new player completes the tutorial in ≤ 75 seconds in the phone emulator without instructions.
- **Saving:** coins, seeds, pedestals, codex, streak and planted crystals (with their remaining time) survive leaving and rejoining, and a server shutdown (`BindToClose`). Joining a second server while the first is still saving never loses or duplicates data.
- **Offline growth:** a crystal planted, followed by leaving for longer than its grow time, is ready on return.
- **Fairness:** no product or pass changes size rolls or overgrowth. A code review confirms boosts touch growth speed only.
- **Security:** a modified client firing remotes with wrong arguments (another player's pedestal, negative counts, unknown seed IDs, spam) cannot gain coins or affect another player. Checked with a test script in Studio.
- **Leaderboard:** a new weekly best appears on the hub board within 2 minutes, and goes into the correct week's store.
- **Performance:** ≥ 30 FPS on a real mid-range phone with 6 full caves.
- **Monetization present:** the game passes and developer products from the approved monetization spec are live and tested before publishing.
- **Analytics:** onboarding funnel steps 1–8 and the economy events appear in the Creator Dashboard from a test session.
- **Content:** no copyrighted names or assets; all audio from Roblox's library or made by you; the maturity questionnaire is completed (it is also needed later for ad eligibility).
- **Lune tests pass** for every pure logic module.

## Verification

- **Automated tests** (`lune run tests` from `roblox/`): growth time with lamp levels; size-roll and mutation-roll distributions (100,000 rolls each, within ±10% of the stated chances); overgrowth cap at +50%; boosts don't change the overgrowth or size result; seed unlock rules; streak continuation and reset across UTC midnight; ISO week ID at year boundaries (for example 2026-12-31 → 2026W53; 2027-01-04 → 2027W01); profile defaults and migration from an empty profile.
- **Backup first:** not needed for v1 (no existing data). From v2 on, follow [README.md](README.md).
- **Studio Play Solo:** play through the tutorial → all 8 steps complete with no errors in Output.
- **Studio 2-player local server:** player A tries to shatter player B's crystal through a remote → rejected; both players see the other's crystals grow.
- **Device Emulator (phone, landscape):** every HUD button and popup is reachable and readable; nothing overlaps the thumbstick or the Roblox menu.
- **Real phone (dev experience):** ≥ 30 FPS with full caves; the tutorial plays through by touch only.

## Decisions for you before approval

1. **Shattering sells instantly** (no separate selling station). The alternative is a "carry crystals to the sell stall" step, which adds walking but slows the loop. **Recommended: instant.**
2. **Overgrowth** (+10%/hour up to +50%) as the "time" part of size. The alternative is no overgrowth, where size is luck only. **Recommended: keep it.** It is the strongest "come back later" reason for the leaderboard.
3. **Leaderboard prizes deferred to v1.1.** The alternative is a crown for last week's top 10 in v1, which adds a weekly job and more DataStore reads. **Recommended: defer.**
4. **Server size 6.** The alternative is 8, which gives a busier hub but 33% more crystals to render on phones. **Recommended: 6.**

## Decisions (confirmed by the user 2026-11-18)

1. **Shattering sells instantly.** Rejected: a separate sell stall that crystals must be carried to.
2. **Overgrowth is kept** (+10% carats and value per hour after ready, capped at +50%; never affected by speed boosts). Rejected: size from luck only.
3. **Leaderboard prizes deferred to v1.1.** Rejected: a crown for last week's top 10 in v1.
4. **Server size locked at 6 players / 6 caves.** Rejected for now: 8 players. You chose not to test 8 in the performance proof; task 1(c) tests 6 full caves only.

## Amendment (2026-11-18): truthful odds in titles and thumbnails

- **Behaviour:** title option 6, "1 in 10,000 Crystal", is withdrawn because it is false under the approved odds (Prismatic ≈ 1 in 667, Colossal 1 in 500, both together ≈ 1 in 333,000). It is replaced by **"Prismatic Crystal Hunt"**. From now on, any odds in titles, thumbnails or ads must match `Config.Rolls`.
- **Design:** no code change.
- **Task:** none. It applies to Step 5 (thumbnail concept B uses "1 in 333,000").
- **Acceptance:** every number in marketing text can be derived from the config.
