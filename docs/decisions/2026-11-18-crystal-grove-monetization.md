# Specification: Crystal Grove monetization (passes, developer products, rewarded ads)

Status: approved 2026-11-18.

## Context

The approved MVP spec, [2026-11-18-crystal-grove-mvp.md](2026-11-18-crystal-grove-mvp.md), defines the game loop (plant → grow → shatter → buy) and reserves UI slots for monetization. You set three rules: passes must exist **before launch**, rewarded ads must be a real mechanic, and **money may make crystals grow faster but never bigger**. This spec defines what is sold, where it is offered, and how it is validated. It writes no code; it is implemented in batch 5.

**Terms used here (Roblox's official terms):**

- **Game pass ("pass"):** a one-time Robux purchase that gives a permanent privilege.
- **Developer product:** an item that can be bought more than once (consumables, boosts, coins).
- **Rewarded video ad:** a full-screen ad of 6–30 seconds that the player chooses to watch for a reward.
- **ProcessReceipt:** the server callback that Roblox calls to confirm each developer product purchase.

### Outside facts checked (2026-11-18)

- **Passes** ([Creator Hub: Passes](https://create.roblox.com/docs/production/monetization/game-passes)):
  - **Ownership:** check it with `MarketplaceService:UserOwnsGamePassAsync(userId, passId)`, wrapped in `pcall`. `GetPassOwnershipAsync` returns an `Owned` field that is the reliable answer for permanent grants.
  - **Purchase:** the prompt is `PromptGamePassPurchase(player, passId)`, called from the client. The completion event is `PromptGamePassPurchaseFinished(player, passId, success)`.
  - **Free trials:** free trials make `UserOwnsGamePassAsync` return true. They are off by default for new passes.
  - **Promotion:** passes that are promoted must cost more than 49 and less than 801 Robux.
  - **Cross-game sales:** disabled since 2026-05-30.
- **Developer products** ([Creator Hub: Developer products](https://create.roblox.com/docs/production/monetization/developer-products)):
  - **Price:** from 1 to 1,000,000,000 Robux.
  - **ProcessReceipt:** it is set **once**, by one server script. It returns `Enum.ProductPurchaseDecision.PurchaseGranted` only after the item has been granted, or `NotProcessedYet` so Roblox retries later.
  - **Double grants:** the docs **do not** prevent double grants, so we must record each purchase ID ourselves.
  - **Wrong signal:** never grant items from `PromptProductPurchaseFinished`.
  - **Displayed price:** read it with `GetProductInfo` (the receipt contains the price actually paid).
- **Rewarded video ads** ([Creator Hub](https://create.roblox.com/docs/production/promotion/rewarded-video-ads), [AdService reference](https://create.roblox.com/docs/en-us/reference/engine/classes/AdService.md)):
  - **Experience eligibility:** the experience must be public and unrestricted, average **at least 2,000 unique visitors per month**, and have an approved maturity questionnaire.
  - **Publisher eligibility:** you need 2-step verification and ID verification, and you must be 13+.
  - **Reward rules:** the reward must be a **developer product that is normally sold in the shop**, must **not be randomized**, and must be granted immediately after the ad finishes.
  - **Flow:**
    1. The client calls `GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)`. The result is valid for one ad only.
    2. The server calls `CreateAdRewardFromDevProductId` and then `ShowRewardedVideoAdAsync(player, reward)`. This can return `AdNotReady`.
    3. The reward arrives through `ProcessReceipt`, on the `AdReward` purchase channel.
  - **Disclosure:** ads must be opt-in and clearly disclosed.
- **Paid random items** ([Creator Hub: Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items)):
  - **What counts:** random outcomes bought with Robux, **or with in-game currency bought with Robux**.
  - **Odds:** for these, the numerical odds must be shown before purchase, and updated live while an enhancement (such as a luck boost) is active.
  - **Restricted players:** where `PolicyService` reports `ArePaidRandomItemsRestricted = true`, the player must not be able to use paid random-item generators.
- **Managed Pricing** ([Creator Hub](https://create.roblox.com/docs/production/monetization/managed-pricing)):
  - **Enrollment:** new games and new items are enrolled by default.
  - **What it does:** it runs price tests and applies regional prices, which are bound to 30–100% of the default price.
  - **Hard-coded prices:** prices hard-coded in the game block it, so the UI must always read prices from `GetProductInfo`.

**Note on the coin economy:** since coins can be bought with Robux, and crystals have random size and mutation rolls, the crystal rolls **may** count as paid random items. This spec takes the safe path: show the odds everywhere, and limit restricted players. Proof task 1 confirms this by reading the full policy.

## Behaviour

### Guardrails (they apply to everything below)

1. **No item increases crystal size or overgrowth.** Size rolls and overgrowth are the same for every player.
2. **Crystals finished with Instant Grow do not count for the weekly leaderboard.** They still pay coins and fill the Codex. Their result popup says "Instant-grown crystals don't count for the board." (See Decision 1.)
3. **No paid random items for sale.** Every Robux product has a fixed, stated content. The random parts (crystal rolls) show their odds in a "🎲 Odds" panel, which updates live when a Luck Boost or Crystal Surge is active.
4. **Kid-safe selling:**
   - At most **one popup offer per session**, and none during the tutorial or during a shatter result.
   - Every offer has a big close button.
   - No fake countdowns.
   - No "you'll lose it" pressure.
   - Prices are always shown in Robux as Roblox reports them.
5. **Restricted players:** where `ArePaidRandomItemsRestricted` is true, the Coin Pouches, Seed Bundles, Starter Pack and Luck Boost are hidden. These are the products that feed random rolls. Passes and Instant Grow stay available. (See Decision 2.)
6. **Every ad reward is also available another way:** buying it for Robux, or a free in-game alternative.

### Game passes (5)

| Pass | Price | Exact benefit | Why players want it | Where it's shown | Purchase trigger |
|---|---|---|---|---|---|
| **⚡ Fast Grow** | 249 R$ | Crystals grow ×2 faster during the **growth phase only**. It stacks with the Growth Lamp by multiplying (for example lamp −25% and Fast Grow give 37.5% of the base time). Overgrowth is not affected. | Long crystals (15 min to 8 h) are the main wait | Store tab; a "⚡" chip on the billboard of crystals with more than 10 min left | Tapping a crystal with more than 10 min left (after the first Emerald unlocks) |
| **💰 Double Coins** | 199 R$ | ×2 coins from shattering. It doesn't apply to daily rewards, goals or Coin Pouches. | Faster seed unlocks | Store tab; the shatter result popup shows "×2 with Double Coins" once per session | The first time you can't afford a seed you have unlocked |
| **🪨 Extra Pedestals** | 149 R$ | +3 pedestals (11–13), beyond the 10 you can buy with coins. They appear as gold-edged stone. | More crystals at once | Upgrades panel, below the coin pedestal card | Buying pedestal 6 with coins, or when all pedestals are full and you tap a locked one |
| **🤖 Auto Shatter** | 299 R$ | A HUD toggle (off by default). While you are in the game, ready crystals shatter automatically, and if you have the same seed in your bag it is replanted. It never runs while you are offline, so overgrowth stays a real choice. | Convenience on phones | Store tab; the "Shatter All Ready" button shows a small "Auto" badge | Using "Shatter All Ready" 5 times in one session |
| **👑 VIP** | 99 R$ | Cosmetic and social only: a gold name tag, a sparkle trail, a gold owner sign on your cave, and a "VIP" badge in the leaderboard row. No gameplay effect. | Showing off; the cheapest pass | Store tab; the cave sign | Visiting another player's cave for the first time |

- **Server-side validation (all passes):**
  - On join, the server checks each pass with `UserOwnsGamePassAsync`, using `pcall` and up to 3 tries with backoff. If it fails, the benefit is off until a re-check, which runs every 60 seconds for up to 5 minutes.
  - On `PromptGamePassPurchaseFinished` with `success == true`, the server confirms with a fresh ownership call before turning the benefit on.
  - **Ownership is never read from the client or saved as truth in the player's data.** The server's ownership table is rebuilt every session.
  - Free trials stay **off** for every pass.
- **Validation per benefit:**
  - **Fast Grow:** the grow-time multiplier is applied only on the server, when the crystal is planted or a pass is bought.
  - **Extra Pedestals:** pedestals 11–13 can only be used while ownership is confirmed. If ownership disappears (a refund), crystals already growing on them finish but no new ones can be planted.
  - **Auto Shatter:** runs from a server loop every 2 seconds, only for players who are online, own the pass, and have the toggle on.

### Developer products

| Product | Price | Content (fixed, non-random) | Where it's shown | Notes |
|---|---|---|---|---|
| **Instant Grow S** | 9 R$ | Finishes 1 crystal with **≤ 15 min** left | Crystal tap menu: "Finish now" | **Rewarded-ad reward #1** |
| **Instant Grow M** | 29 R$ | Finishes 1 crystal with **≤ 2 h** left | Crystal tap menu | The server picks S, M or L from the time left |
| **Instant Grow L** | 59 R$ | Finishes 1 crystal with **> 2 h** left | Crystal tap menu | |
| **Grow All** | 99 R$ | Finishes every growing crystal in your cave | Store tab; shown when 5 or more crystals are growing | |
| **🍀 Luck Boost (15 min)** | 25 R$ | Mutation chances ×2 for crystals planted during the next 15 min. It stacks with Crystal Surge up to ×3 total, and buying again adds 15 min (at most 60 min banked). It does not affect size. | HUD reserved slot (bottom right); Store tab | **Rewarded-ad reward #2**. The Odds panel shows the boosted odds. |
| **Coin Pouch S / M / L** | 19 / 99 / 249 R$ | Coins equal to 5 / 30 / 100 × the base value of your highest unlocked seed. The exact number is shown on the card before you buy. | Store tab; "Not enough coins" toast has a "Get coins" link | S is **rewarded-ad reward #3** |
| **Seed Bundle** | 39 R$ | 3 seeds of your highest unlocked type (never locked tiers) | Store tab; the seed picker when your bag is empty | |
| **🎁 Starter Pack** | 49 R$ | 1,000 coins + 3 Citrine seeds + 30 min of Luck Boost. **One purchase per account**, enforced by the server. | One popup offer, then always in the Store tab until bought | The first-purchase product |

- **Pricing rule:** all prices are defaults. Managed Pricing may test and regionalize them, so **the UI never hard-codes a price**. It reads prices with `MarketplaceService:GetProductInfo` (`Enum.InfoType.Product` or `GamePass`).
- **Why there are 3 Instant Grow products:** a developer product has one price, so tiers by time left keep the price fair for short and long crystals.

### Purchase handling (developer products)

1. The client sends an **intent** to the server ("Instant Grow pedestal 4"). The server checks that the pedestal is yours and growing, and works out which tier applies. It stores a short-lived pending target (60 s) and replies with the product ID. The client then calls `PromptProductPurchase`.
2. **ProcessReceipt** is one handler in one server script. In order, it:
   1. Finds the player and returns `NotProcessedYet` if they are not in this server or their data is not loaded.
   2. Checks that the `PurchaseId` is not already in the player's `ProcessedReceipts` list. If it is, it returns `PurchaseGranted` again without granting anything.
   3. Grants the content.
   4. Appends the `PurchaseId` (the list keeps the last 100).
   5. Saves the player's data, and returns `PurchaseGranted` only if that save succeeded.
3. **Instant Grow with no target:** if the target crystal is gone (already shattered, or the pending target expired), the purchase becomes an **Instant Grow token** of that tier, stored in the player's data. A "Use token" button appears on the next eligible crystal. **Nothing paid is ever lost.**
4. **Starter Pack bought twice:** the second purchase is converted to its value in coins (1,000 coins + 3 Citrine seeds), and a toast explains this. The Store hides the card after the first purchase, so this only happens in a race between two prompts.

### Rewarded video ads

| # | Trigger | Reward (developer product) | Frequency cap | UI placement | When no ad is available | Anti-abuse |
|---|---|---|---|---|---|---|
| 1 | You tap a growing crystal with **≤ 15 min** left | **Instant Grow S** (sold for 9 R$) | 5 per day | "📺 Finish free" button next to "Finish now 9 R$" in the crystal menu | The ad button is hidden. Robux and waiting remain. | Server checks the target before the ad; 60 s cooldown between any two ads; if the target is gone, the reward becomes a token |
| 2 | You tap the HUD 🍀 slot when no Luck Boost is active | **Luck Boost (15 min)** (sold for 25 R$) | 3 per day | HUD bottom-right reserved slot: "📺 Free Luck" | It shows the Robux price and "Next free Surge in mm:ss" (Crystal Surge is the free alternative) | Can't be watched while a boost has more than 5 min left |
| 3 | After claiming the daily streak reward | **Coin Pouch S** (sold for 19 R$) | 1 per day | Button "📺 Bonus coins" on the daily reward popup | The button is hidden | Once per UTC day, counted in saved data |

- **Total cap:** 9 ads per player per day, counted in UTC days and saved, so rejoining doesn't reset it.
- **Server-side flow:**
  1. The client checks `GetAdAvailabilityNowAsync` **before showing any ad button**. Players who aren't eligible (for example under 13) never see one.
  2. Tapping the button sends an intent to the server. The server checks the cap, the cooldown, the target, and that this player has no ad request already running. Only then does it call `ShowRewardedVideoAdAsync`.
  3. The reward is granted **only in ProcessReceipt**, on the `AdReward` channel, through the same handler as purchases. That handler already prevents double grants.
  4. The `ShowAdResult` value is only used for UI messages.
- **Before eligibility (launch):** all three placements are coded and tested, but invisible. The game behaves as if no ad is available, so the Robux and free paths are what players see. Once the experience reaches 2,000 monthly visitors and you enable Rewarded Video in Game Settings, the buttons appear without a code change.
- **Disclosure:** each ad button has the 📺 icon and a "Watch a short ad" subtitle.

### Monetization funnel: from free player to first purchase

| Moment | What the player sees | Goal |
|---|---|---|
| 0–60 s (tutorial) | No offers, no Store button highlight | Hook first; no selling |
| First crystal with more than 5 min left (Rose Quartz, about minute 4–6) | Crystal menu: "Finish now 29 R$" (and "📺 Finish free" once ads are live) | The first small, specific desire to skip waiting |
| About minute 6, after the 10th shatter | **The one popup offer of the session: Starter Pack (49 R$)** | First purchase; high perceived value |
| First "Not enough coins" | Toast with a "Get coins" link to Coin Pouches | Coins on demand |
| Buying pedestal 6 | Extra Pedestals card highlighted | First pass |
| First Emerald (15 min) or longer | ⚡ chip on the billboard → Fast Grow | The highest-value pass |
| Day 2 or later, first join | If no pass is owned, the session's popup offer is **Double Coins** instead of the Starter Pack; otherwise no popup | A second purchase |

**Targets** (Roblox Creator Dashboard; re-tested in Step 8):

| Metric | Fail | OK | Good |
|---|---|---|---|
| Payer conversion (share of daily users who buy) | < 0.5% | 0.5–1.5% | > 1.5% |
| Starter Pack take rate (purchases ÷ times shown) | < 1% | 1–3% | > 3% |
| ARPDAU (Robux per daily user) | < 0.5 | 0.5–1.5 | > 1.5 |
| Ad views per ad-eligible daily user (after ads go live) | < 0.5 | 0.5–1.5 | > 1.5 |

### Price and offer testing after launch

- **Week 1:** keep the default prices so there is a baseline. Watch conversion for each product, and ad views once ads are live.
- **From week 2:** let **Managed Pricing** run price tests on the Starter Pack, Double Coins and Fast Grow. One item group at a time, so results don't mix. While a test runs, don't change those prices by hand.
- **Offer experiments you run yourself** (one at a time, 7 days each, compared with the previous week):
  1. Starter Pack timing: after the 10th shatter versus after the first Rare unlock.
  2. Instant Grow M at 29 versus 19 R$, through Managed Pricing.
  3. A "Fast Grow" chip from 10 min left versus from 30 min left.
- **Decision rule:** keep a change only if ARPDAU goes up **and** D1 retention doesn't drop by more than 1 percentage point.

### Edge cases

- **Purchase while data isn't loaded:** `NotProcessedYet`, and Roblox retries on the next join.
- **Pass bought on another server or on the website:** picked up at the next join, and by the 60-second re-check during the first 5 minutes.
- **Refund or lost pass ownership:** the benefit turns off at the next join. Already-granted products stay.
- **Ad closed early:** no receipt, so no reward. The button stays available within the cap.
- **Studio test purchases:** Studio purchases are free tests. The developer's own test purchases in the live game are counted and filtered out of the metrics by user ID.

## Not included

- **Subscriptions, private servers, Premium Payouts tuning, paid random items (no "mystery" products), gifting, trading, cosmetic shop beyond VIP.** These can be reconsidered after week 2 data.
- **Leaderboard prizes** (deferred to v1.1 in the MVP spec).
- **Join with Reward, sponsored portals and other ad formats** besides rewarded video. Paid ads to bring players in are covered in Step 5.
- **A second currency (gems).**
- **Sales events and limited-time bundles.** These come in the iteration plan (Step 8).

## Design

- **Server authority:** pass ownership, the product grants, the ad caps, the Starter Pack flag and the Instant Grow targets all live on the server. The client only sends intents and displays prices it got from `GetProductInfo`.
- **Config:** pass and product IDs, default prices (used only for analytics labels, never shown), caps and cooldowns all live in the config module in `src/shared/Config/`. IDs are filled in after you create the passes and products in the Creator Dashboard. The IDs for the dev experience and the live experience are kept separately.
- **Pure, testable logic** (Lune): choosing the Instant Grow tier from the time left; Coin Pouch amounts; ad-cap and cooldown decisions; the receipt double-grant check; Luck Boost stacking up to the 60-minute cap; whether a crystal can enter the leaderboard.
- **Stored data:** these fields join the player profile **version 1**, which isn't live yet, so no migration is needed. They are:
  - `ProcessedReceipts` (last 100 purchase IDs)
  - `InstantGrowTokens {S, M, L}`
  - `LuckBoostEndsAt`
  - `StarterPackBought`
  - `AdCounts {Date, FinishNow, Luck, CoinPouch}` and `LastAdAt`
  - `OfferShownSession`
  - a per-crystal `InstantGrown` flag

  The exact schema comes in the architecture spec.
- **Analytics:**
  - `LogEconomyEvent` with transaction type "IAP" for coins from Pouches.
  - `LogCustomEvent` names: "OfferShown", "OfferPurchased", "AdRequested", "AdRewarded", "PassPurchased".
  - The funnel "FirstPurchase", with steps: OfferShown → PromptOpened → Purchased.

### Files

These are set in the batch 5 implementation plan.

## Task breakdown and model assignment

| # | Task | Model | Depends on |
|---|---|---|---|
| 0 | Save this decision record | Orchestrator | — |
| 1 | **Proofs:** (a) read the full Randomized Virtual Items policy and confirm whether coin-bought crystal rolls count, which confirms or changes guardrail 5; (b) in the dev experience, create 1 test pass and 1 test product, then check in Studio that the purchase prompt, `ProcessReceipt` and `GetProductInfo` work; (c) check what `GetAdAvailabilityNowAsync` and `ShowRewardedVideoAdAsync` return in Studio and in the unpublished dev experience, so the hidden-button path is proven. | Orchestrator (you create the items in the Creator Dashboard) | — |
| 2 | Create the 5 passes and 10 products in the dev and live experiences; record the IDs in config. Icons: 512 × 512, with the subject inside a circle. | You | 1 |
| 3 | Implementation: batch 5, via its own `/write-spec` implementation plan | Set in that plan | Batches 1–4, 2 |

Escalation: if task 1(a) shows the crystal rolls **don't** count as paid random items, guardrail 5 is relaxed so restricted players see everything (odds stay shown). If task 1(c) shows the ad APIs error in Studio instead of returning "not available", batch 5 wraps them in `pcall` and treats any error as "not available".

### Acceptance criteria

- **Passes:** each benefit turns on after a test purchase without rejoining; the benefit disappears in a test where ownership returns false.
- **Products:** each product grants its exact stated content once. Calling the receipt handler twice with the same `PurchaseId` (a Lune test of the double-grant check) grants once.
- **Fairness:** a code review confirms nothing changes size rolls or overgrowth, and that instant-grown crystals never reach the leaderboard store.
- **Ads:** with ads unavailable, no ad button appears anywhere. The caps (5, 3, 1, total 9) and the 60-second cooldown hold across a rejoin.
- **Prices:** a search of the code finds no price numbers in UI code.
- **Odds panel:** it shows the size and mutation odds, and updates while a Luck Boost or Surge is active.

## Verification

- **Automated tests** (`lune run tests`): Instant Grow tier selection at 15 min and 2 h boundaries; Coin Pouch amounts for tiers 1 and 10; the ad cap reset at UTC midnight; the 60-second cooldown; receipt double-grant check; Luck Boost stacking to a ×3 total and a 60-minute bank; leaderboard eligibility of an instant-grown crystal (rejected).
- **Backup first:** not needed. There is no live data yet.
- **Studio Play Solo:** buy each pass and product with test purchases → each benefit appears, and the Output shows no errors.
- **Studio 2-player server:** player A's Instant Grow can't target player B's crystal (the intent is rejected); A's VIP sign is visible to B.
- **Device emulator (phone):** the Store tab, the crystal menu and the Starter Pack popup fit; prices are readable; the close button is at least 48 px.
- **Real phone (dev experience):** one real purchase of a 9 R$ product by you → granted once; rejoin → not granted again.

## Decisions for you before approval

1. **Instant-grown crystals don't count on the leaderboard.** Alternative: they count. Then Robux buys more leaderboard attempts per hour. Fast Grow and Extra Pedestals still give more attempts either way; this just stops the most direct case. **Recommended: they don't count.**
2. **Hide coin-feeding products from restricted players** (guardrail 5) until proof 1(a) says otherwise. Alternative: sell everything everywhere and only show odds. **Recommended: hide them.** It's the safe side of a Roblox policy.
3. **Prices** as in the tables (passes 99–299 R$, products 9–249 R$, Starter Pack 49 R$). Alternative: higher pass prices (for example Fast Grow 399). **Recommended: these prices.** They're low enough for a first purchase by a 9–15 audience, and Managed Pricing will tune them.

## Decisions (confirmed by the user 2026-11-18)

1. **Instant-grown crystals do not count for the weekly leaderboard.** Rejected: letting them count.
2. **Coin-feeding products (Coin Pouches, Seed Bundle, Starter Pack, Luck Boost) are hidden for players with `ArePaidRandomItemsRestricted = true`** until proof 1(a) says otherwise. Rejected: selling everything to everyone with odds shown.
3. **Prices as in the tables** (passes 99–299 R$, products 9–249 R$, Starter Pack 49 R$). Rejected: higher pass prices such as Fast Grow at 399 R$.
