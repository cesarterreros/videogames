# Specification: Batch 5, monetization (passes, developer products, receipts, rewarded ads, offers, store UI)

Status: approved 2026-11-18. Not started; implemented in its own session.

## Context

After batch 4 ([record](2026-11-18-batch-4-ui-and-onboarding.md)), the game is fully playable for free. This batch implements the approved [monetization spec](2026-11-18-crystal-grove-monetization.md) exactly:
- **5 game passes:** Fast Grow, Double Coins, Extra Pedestals, Auto Shatter, VIP.
- **10 developer products:** Instant Grow S/M/L, Grow All, Luck Boost, Coin Pouch S/M/L, Seed Bundle, Starter Pack.
- **Receipt handling:** safe against double grants.
- **3 rewarded-ad placements,** hidden until Roblox makes ads available.
- **The offer funnel** (one popup per session).
- **The store UI** in the HUD's reserved slot.
- **Paid-random-items policy handling.**

Passes **must exist before launch** (your rule). It follows the architecture build-order item 11.

### Context for a new session (read before task 1)

1. [README.md](README.md): **Starting a new session** and **Delegation lessons**.
2. This record.
3. The [monetization spec](2026-11-18-crystal-grove-monetization.md), **all of it, including its Decisions**. It is the source of every price, benefit, cap and guardrail.
4. The [batch 1 record](2026-11-18-batch-1-project-data-setup.md): **Task 1 findings, correction 2.** `profile:Save()` doesn't yield, so receipts must wait for the save to finish.
5. The batch 2–4 records: their contracts and Findings/Outcome sections (the `CrystalService` shatter and plant paths, `TutorialService`, the UI `Screen.new(ctx)` contract, the `MonetizationSlot`).
6. **Code to read:**
   - server: `Services/CrystalService.luau`, `DataService.luau`, `RemoteService.luau`, `ShopService.luau`, `SettingsService.luau`, `TutorialService.luau`, `LeaderboardService.luau`
   - shared: `Config/Monetization.luau`, `Logic/ProfileTemplate.luau` (the `Monetization` fields), `Logic/Growth.luau`, `Logic/Rolls.luau`
   - client: `UI/Components.luau`, `UI/Screens/Hud.luau`, `Odds.luau`, `Controllers/UIController.luau`, `TapController.luau`
7. **Starting state:** the batch 4 branch is committed; tests pass. Create `batch-5-monetization`.

### Outside facts

**Checked on 2026-11-18** (there are also the facts recorded in the monetization spec):
- **`MarketplaceService:GetProductInfo` is deprecated**, superseded by **`GetProductInfoAsync`** ([MarketplaceService reference](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService.md)). **Correction to the monetization spec:** the UI reads prices with `GetProductInfoAsync`.
- **The ProcessReceipt `receiptInfo` fields** (same page): `PurchaseId`, `PlayerId`, `ProductId`, `PlaceIdWherePurchased`, `CurrencySpent`, `CurrencyType`, `ProductPurchaseChannel` (a `ProductPurchaseChannel` enum).
- **`PromptProductPurchase(player, productId)`, `PromptGamePassPurchase(player, gamePassId)`, `UserOwnsGamePassAsync(userId, gamePassId): boolean`** (same page).
- **`PolicyService:GetPolicyInfoForPlayerAsync(player)`** ([PolicyService reference](https://create.roblox.com/docs/reference/engine/classes/PolicyService.md)) returns keys including `ArePaidRandomItemsRestricted` and `AreAdsAllowed`. The docs show a client call for the local player; calling from the client for another player errors.

**To check in task 1:**
- the `GetProductInfoAsync` signature;
- whether `GetPassOwnershipAsync` exists (the passes guide mentioned it, but the class reference page read so far didn't show it);
- the exact `Enum.ProductPurchaseChannel` value for ads (expected `AdReward`);
- the `Enum.AdAvailabilityResult` and `Enum.ShowAdResult` values;
- whether `GetPolicyInfoForPlayerAsync` works from the server.

## Behaviour

Everything in the monetization spec's **Behaviour** section applies as written. The tables there are the source; they are not repeated here. The details below are the implementation choices.

### Store UI
- **Opening it:** the HUD's `MonetizationSlot` becomes two buttons, **🛍️ Store** and **🍀 Luck**.
- **The Store panel** has three sections, with every price read via `GetProductInfoAsync` and shown as "R$ 249":
  1. **Passes:** 5 cards with name, benefit line and price, or "OWNED".
  2. **Boosts:** Luck Boost and Grow All.
  3. **Coins & Seeds:** Coin Pouch S/M/L, each showing its exact coin amount for you (computed on the server from your highest unlocked seed and sent in the snapshot); the Seed Bundle; and the Starter Pack until it is bought.
- **Crystal menu** (tap a growing crystal):
  - **"Finish now R$ 9/29/59"**, with the server choosing the tier;
  - **"📺 Finish free"**, only when 15 min or less are left, an ad is available and you are under your cap;
  - **"Use token (S/M/L)"** when you have a token of a fitting tier.
- **The 🍀 Luck slot:**
  - **Boost active:** "🍀 12:30", the time left.
  - **No boost, ad available:** "📺 Free Luck".
  - **No boost, no ad:** the Robux price, plus "Next free Surge in mm:ss".
- **Daily popup:** "📺 Bonus coins" under the Claim button, after claiming, if an ad is available and not used today.
- **Odds panel:** shows the boosted mutation odds while a Luck Boost and/or Surge is active (capped at ×3 in total), as the paid-random-items policy requires.

### Pass benefits (all applied on the server)
- **Fast Grow:** `speedMult = 0.5` in `Growth.growSeconds` at plant time. It doesn't affect overgrowth.
- **Double Coins:** `coinMult × 2` on shatter coins only.
- **Extra Pedestals:** pedestals 11–13 become `Unlocked` while ownership is confirmed. If ownership is lost, crystals already growing on them finish, but nothing new can be planted there.
- **Auto Shatter:**
  - An HUD toggle "🤖 Auto" appears next to Shatter All for owners. It fires `SetSetting("AutoShatter", bool)`, now accepted only for owners.
  - A server loop every 2 s, for online owners with the toggle on, shatters ready crystals and **replants the same seed if the bag has one**. It never runs offline.
- **VIP:**
  - a gold "VIP" name tag (a BillboardGui above the head);
  - a sparkle `Trail` on the character;
  - a gold trim on the cave sign;
  - a "👑" in your leaderboard row.

### Developer products
Each product grants exactly the content in the monetization spec, through one `ProcessReceipt`.
- **Instant Grow:**
  1. The client calls `RequestInstantGrow(pedestal)` (a RemoteFunction).
  2. The server checks the crystal is yours and growing, picks S (15 min or less left), M (2 h or less) or L, stores a **pending target** for 60 s, and returns the product ID.
  3. The client prompts the purchase.
  4. On the receipt, the target crystal's `ReadyAt = os.time()` and `InstantGrown = true`.
  5. If there is no valid target any more, it becomes `InstantGrowTokens[tier] += 1`.
- **Grow All:** every growing crystal you own becomes ready, and each is marked instant-grown.
- **Luck Boost:** `LuckBoostEndsAt = max(now, LuckBoostEndsAt) + 15 min`, capped at now + 60 min. Plants made while it is active get `chanceMult = min(3, luck(2) × surge(2 if active))`, where luck and surge multiply and the cap is ×3.
- **Coin Pouch:** `Mult × BaseValue(highest unlocked seed)` coins, computed **at receipt time**.
- **Seed Bundle:** 3 of your highest unlocked seed.
- **Starter Pack:** 1,000 coins, 3 Citrine and 30 min of luck; `StarterPackBought = true`. A second purchase converts to coins of the same value, with a toast.

### Receipts (the double-grant-proof flow)
`ReceiptService` sets `MarketplaceService.ProcessReceipt` **once**. For each receipt:
1. **Player missing or profile not loaded:** return `NotProcessedYet`.
2. **`PurchaseId` already in `ProcessedReceipts`:** return `PurchaseGranted` without granting.
3. **Unknown `ProductId`:** warn and return `NotProcessedYet`.
4. **Grant:** run the product's grant function and append the `PurchaseId` (keeping the last 100).
5. **Save:** call `profile:Save()`, then wait up to 15 s for `profile.OnAfterSave`, until **`LastSavedData.Monetization.ProcessedReceipts` contains the `PurchaseId`** → return `PurchaseGranted`.
6. **Timeout:** return `NotProcessedYet`. Roblox retries later, and step 2 stops a double grant.

**Ad rewards** arrive through the same handler, with `ProductPurchaseChannel` = the ad channel (exact value from task 1), and are granted the same way.

### Rewarded ads
- **The flow:**
  1. The client checks `AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)` before showing any ad button, and again before each ad.
  2. Tapping the button fires `RequestAd(placement, pedestal?)`.
  3. The server checks the profile, the policy (`AreAdsAllowed`), the placement cap, the daily total of 9, the 60-second cooldown and that no ad is already running for you. For FinishNow, it also checks the target (yours, growing, 15 min or less), which is stored as a pending target.
  4. The server calls `AdService:CreateAdRewardFromDevProductId(productId)` and `AdService:ShowRewardedVideoAdAsync(player, reward)` inside `pcall`.
  5. The reward comes only through `ProcessReceipt`. The `ShowAdResult` is used only for a toast ("No ad right now, try later").
- **Counting:** `AdCounts` (Date, FinishNow, Luck, CoinPouch) and `LastAdAt` count when the server **requests** the ad, so cancelled ads still use the cooldown. This is anti-abuse; record it in the outcome.
- **Before eligibility:** all ad buttons stay hidden because availability isn't `IsAvailable`. This is expected until the experience reaches 2,000 monthly visitors.

### Offers (one popup per session, never during the tutorial or a result popup)

| Condition | Popup |
|---|---|
| Tutorial done, **10th shatter of the session**, Starter Pack not bought, no popup yet this session | **Starter Pack** card (49 R$) |
| Day 2 or later (`FirstJoinAt` before today), no pass owned, no popup yet | **Double Coins** card |

- **Every popup:** a big ✕; no countdown.
- **Analytics:** `OfferShown`, `OfferPurchased` (custom events), and the funnel `FirstPurchase`: OfferShown → PromptOpened → Purchased.

### Paid-random-items policy
- **Restricted players:** when `ArePaidRandomItemsRestricted` is true, **Coin Pouches, Seed Bundle, Starter Pack and Luck Boost are hidden in the UI and refused by the server** (approved Decision 2). Passes, Instant Grow and Grow All stay available.
- **Proof 1(a):** reads the full Randomized Virtual Items policy. If crystal rolls bought indirectly with Robux **don't** count, relax this rule (and record it). If they do, keep it.

### Edge cases
- **Purchase while the profile isn't loaded:** `NotProcessedYet`.
- **Pass bought on the website or another server:** picked up at the next join, and by the 60-second re-check during the first 5 minutes.
- **Refunded pass:** the benefit is off at the next join.
- **Test purchases in Studio:** free, and processed normally.
- **Your own live test purchases:** filtered out of the metrics by your user ID, which is kept in local notes, **not in the repo**.

## Not included

- **Subscriptions, private servers, gifting, trading, mystery products, sales events.**
- **Join with Reward and other ad formats.**
- **Leaderboard prizes** (v1.1).
- **Managed Pricing setup:** that is a Creator Dashboard step at launch (batch 6 checklist); the code only reads live prices.
- **Pass and product icons:** you make them in task 2. The code doesn't need them.

## Design

**Stored data:** no schema change. It uses the version 1 `Monetization` fields and `Pedestals[n].InstantGrown`.

### Product IDs per experience (dev and live are different universes)

```lua
-- Config/Monetization.luau gains (filled by you; universe IDs are public, not personal data):
Monetization.IdsByGameId = {
  [<dev GameId>]  = { Passes = { FastGrow = 0, ... }, Products = { InstantGrowS = 0, ... } },
  [<live GameId>] = { Passes = { ... }, Products = { ... } },   -- added at launch (batch 6)
}
-- MonetizationIds.get(): the table for game.GameId; in Studio for an unpublished place → all zeros (features hidden).
```

### Shared contract

```lua
-- Logic (pure, NO requires)
Receipts.isProcessed(list: {string}, purchaseId: string): boolean
Receipts.record(list: {string}, purchaseId: string, max: number): {string}      -- keeps the newest `max`
InstantGrow.tierFor(secondsLeft: number, cfg): "S" | "M" | "L"                   -- ≤900 S, ≤7200 M, else L
LuckBoost.extend(endsAt: number, now: number, minutes: number, maxBankMinutes: number): number
LuckBoost.chanceMult(now: number, endsAt: number, surgeActive: boolean, luckMult: number, surgeMult: number, maxTotal: number): number
AdCaps.check(adCounts, today: string, placement: string, now: number, lastAdAt: number, cfg): (boolean, reason: string?)
AdCaps.recordRequest(adCounts, today: string, placement: string): adCounts       -- resets counts on a new date
Economy.coinPouchAmount(seeds, highestTier: number, mult: number): number        -- add to Logic/Economy

-- Server services
PassService:Owns(player, passKey: string): boolean          -- from the per-session ownership table
PassService.OwnershipChanged: signal (player, passKey, owns)
ReceiptService:RegisterGrant(productKey: string, fn: (player, data, receipt) -> ())   -- one per product
RewardedAdService                                            -- handles RequestAd
OfferService                                                 -- popup triggers; remote "Offer" (new ToClient remote)
MonetizationIds.get(): { Passes: {[string]: number}, Products: {[string]: number} }
-- New remotes (added to Net/Remotes.luau): "Offer" (Event, ToClient), "PolicyInfo" (Event, ToClient)
-- CrystalService changes: speedMult (Fast Grow), coinMult (Double Coins), chanceMult (luck/surge), pedestals 11–13,
--   InstantGrown handling, AutoShatter loop entry point CrystalService:AutoShatter(player)
```

### Files

| File (under `roblox/`) | Change | Task |
|---|---|---|
| `src/shared/Config/Monetization.luau` | Add `IdsByGameId` (dev IDs from task 2) | 2 |
| `src/shared/Logic/Receipts.luau`, `InstantGrow.luau`, `LuckBoost.luau`, `AdCaps.luau`; `Economy.coinPouchAmount` + specs | New | 3, 4 |
| `src/shared/Net/Remotes.luau` | Add `Offer` and `PolicyInfo` | 1 |
| `src/shared/Strings/en.luau` | Store, pass, product and offer texts; ad button texts; toasts ("No ad right now, try later", "Token saved for later", "Already bought — converted to coins") | 1 |
| `src/server/Services/MonetizationIds.luau`, `PassService.luau` | New | 5 |
| `src/server/Services/ReceiptService.luau` | New | 6 |
| `src/server/Services/RewardedAdService.luau` | New | 7 |
| `src/server/Services/OfferService.luau` | New | 8 |
| `src/server/Services/CrystalService.luau`, `SettingsService.luau`, `LeaderboardService.luau` (VIP 👑), `PlotService.luau` (VIP sign trim) | Integration | 9 |
| `src/server/Services/VipService.luau` | New: name tag and trail | 10 |
| `src/client/UI/Screens/Store.luau`, `CrystalMenu.luau` | New | 11 |
| `src/client/UI/Screens/OfferPopup.luau`; changes to `Hud.luau` (slot buttons, Auto toggle, Luck slot), `Daily.luau` (ad button), `Odds.luau` (boosts) | New / changed | 12 |
| `src/client/Controllers/PurchaseController.luau` | New: price cache via `GetProductInfoAsync`, prompts, ad availability checks | 11 |
| `src/server/Main.server.luau`, `src/client/Main.client.luau` | Order updates | 9, 12 |

## Task breakdown and model assignment

| # | Task | Model | Why this model | Depends on |
|---|---|---|---|---|
| 0 | Branch and save the record status | Orchestrator | — | — |
| 1 | **Proofs:** (a) read the Randomized Virtual Items policy in full and decide guardrail 5; (b) check the "to check" APIs; (c) in Studio, test what `GetAdAvailabilityNowAsync` and `ShowRewardedVideoAdAsync` return. Add the remotes and strings. | Orchestrator | Policy and API judgment | 0 |
| 2 | **Create the 5 passes and 10 products in the DEV experience** (Creator Dashboard → your experience → Monetization), keep free trials **off**, and give the IDs and the dev `GameId` to the session | You | Your account | 1 |
| 3 | `Logic/Receipts`, `Logic/InstantGrow` + specs | DeepSeek Flash | Pure functions | 1 |
| 4 | `Logic/LuckBoost`, `Logic/AdCaps`, `Economy.coinPouchAmount` + specs | DeepSeek Flash | Pure functions | 1 |
| 5 | `MonetizationIds`, `PassService` | Orchestrator | Ownership is security-critical | 2 |
| 6 | `ReceiptService` + every product grant | Orchestrator | Money (project rule) | 3, 4, 5 |
| 7 | `RewardedAdService` | Orchestrator | Money and anti-abuse | 4, 6 |
| 8 | `OfferService` | DeepSeek Flash | Trigger rules, no grants | 5 |
| 9 | `CrystalService`, `SettingsService`, Leaderboard and Plot integrations + Auto Shatter loop | Orchestrator | Coin path | 5, 6 |
| 10 | `VipService` | Haiku | Small cosmetic file, fully specified | 5 |
| 11 | `PurchaseController`, `Store`, `CrystalMenu` screens | DeepSeek Flash | UI against the batch 4 contract | 5, 6 |
| 12 | `OfferPopup`, HUD/Daily/Odds changes, client order | DeepSeek Flash | UI | 8, 11 |
| 13 | Review, tests, StyLua, build, Studio test purchases and checks with you; findings and outcome | Orchestrator | — | all |

Escalation: as in earlier batches. **If proof 1(c) shows the ad APIs error in Studio**, keep every call in `pcall` and treat errors as "not available". **If `GetPassOwnershipAsync` doesn't exist**, use `UserOwnsGamePassAsync` only; trials stay off, so it is reliable.

### Acceptance criteria

- **Tasks 3 and 4:** unit tests for the tier boundaries (900 s and 7,200 s), receipt history trimming at 100, Luck banking to 60 min, the chance cap ×3 with Surge, ad caps of 5/3/1 and a total of 9, the cooldown of 60 s, the reset on a new date, and Coin Pouch amounts at tiers 1 and 10.
- **Task 6:**
  - `ProcessReceipt` is set exactly once.
  - Every product grants its spec content exactly once, including a replay of the same `PurchaseId` (simulated in Studio by calling the handler twice with a saved receipt table).
  - `PurchaseGranted` is returned only after the saved data contains the ID.
- **Task 7:** no ad is shown without passing every check; counts persist across a rejoin; ad rewards go through `ProcessReceipt`.
- **Task 9:**
  - A code search confirms that **nothing paid touches `SizeRoll` or overgrowth**.
  - Instant-grown crystals never reach `LeaderboardService:Submit`.
  - Auto Shatter only runs for online owners with the toggle on.
- **Tasks 11 and 12:**
  - A search finds **no price numbers in the UI code**; prices come only from `GetProductInfoAsync`.
  - Ad buttons appear only when available.
  - Restricted players never see the coin-feeding products.
  - The Odds panel shows the boosted odds.
- **Task 13:** all tests pass, StyLua is clean, the build succeeds, and the checks below pass.

## Verification

- **Automated tests:** `Receipts.spec`, `InstantGrow.spec`, `LuckBoost.spec`, `AdCaps.spec`, the `Economy.spec` additions, plus all earlier ones.
- **Backup first:** not needed. There is no schema change; dev data only.
- **Studio (dev experience; test purchases are free):**
  1. Buy each pass → its benefit appears without rejoining:
     - Fast Grow: a new Quartz takes 10 s;
     - Double Coins: coins ×2;
     - Extra Pedestals: 11–13 unlocked;
     - Auto: the toggle appears and works;
     - VIP: the tag, trail and 👑.
  2. Buy each product → the exact content once. Instant Grow on a crystal you then shatter before the purchase completes → a token.
  3. Starter Pack twice → the second one converts to coins, with a toast.
  4. The 10th shatter after the tutorial → the Starter Pack popup, only once per session.
  5. With ads unavailable (expected now), **no 📺 button anywhere**; the Luck slot shows the Robux price and the Surge countdown.
- **Studio 2-player server:** A's Instant Grow can't target B's crystal; B sees A's VIP tag.
- **Real phone (dev experience):** one **real** purchase of a 9 R$ product by you → granted once; rejoin → not granted again; check the Creator Dashboard sales.

## Decisions (confirmed by the user 2026-11-18, recommended options chosen)

1. **Ad requests count toward the caps and cooldown even when you close the ad early.** Rejected: counting only completed ads, which is easier to abuse by spam-opening ads.
2. **Product IDs are kept per experience (`IdsByGameId`)** so the dev and live experiences each use their own items. Rejected: one set of IDs edited before each publish, which is error-prone.
3. **Prices are read with `GetProductInfoAsync`** (correcting the monetization spec, which named the deprecated `GetProductInfo`). There is no alternative; this is a correction for you to note.
