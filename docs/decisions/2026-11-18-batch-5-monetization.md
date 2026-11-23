# Specification: Batch 5, monetization (passes, developer products, receipts, rewarded ads, offers, store UI)

Status: approved 2026-11-18. **Done 2026-11-22:** tasks 0–13 complete; see **Outcome** at the end (findings T1–T5 go to batch 6). Committed as `57dec18` (tasks 0–12) and `4b26e8a` (task 13) on `batch-5-monetization`; pull request into `batch-1-setup`.

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

**Batch finished:** task 13's results are under **Task 13 checks** (end of Findings) and the **Outcome** follows it.

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

## Resume here: task 13 (hand-off written 2026-11-22)

The first session (tasks 0–12) ended here because its context was full. A new session continues with **task 13** (review, Studio checks with you, publish and the phone, Outcome). Read the README, this section, then Progress and Findings as needed (both are in task order).

### State

- **Tasks 0–12 done**, committed on `batch-5-monetization` (the commit after `ceeb4bb`; not pushed). Pull request #4 (batch 4) was already merged into `batch-1-setup`.
- `lune run tests` **239 passed, 0 failed**; StyLua clean (`stylua src tests --glob '!**/Vendor/**'`); `rojo build` succeeds; Remotes **19**; the vendored ProfileStore untouched.
- **Pass and product IDs (DEV, universe 10777641396)** are in `Config/Monetization.IdsByGameId`; created through Open Cloud (Progress → task 2). The live experience gets its own entry at launch (batch 6).

### Plan changes, all confirmed by you on 2026-11-22 (details in Progress and Findings)

| | Change |
|---|---|
| G | Screens reach purchases only through `ctx.Purchase` (PurchaseController); `Screens.spec` `ALLOWED` unchanged |
| H | HUD slot 128 × 56: 🛍️ Store + 🍀 Luck, hint label above, 🤖 Auto left of Shatter All |
| I | Daily: "📺 Bonus coins" right of "Claimed" on the same row |
| J | Tapping a growing crystal opens the CrystalMenu when it has an option and the tutorial is done; otherwise the old bubble |
| K | Tutorial overrides beat Fast Grow / Luck / Surge; Auto Shatter skips players in the tutorial |
| L | Instant-grown crystals skip the weekly best entirely |
| M | `Result.luau` shows "Instant-grown crystals don't count for the board" |
| N | The offer popup waits for a clear screen (no result card, no panel, tutorial done), up to 30 s |
| O | Double Coins is hidden from and refused to restricted players (an owner keeps it) |
| P | Rewarded ads aren't gated on `AreAdsAllowed` (it's for immersive ads) |
| Q | Studio reports ads available and plays test ads; "no 📺 anywhere" is checked on the published DEV place |
| R | Your account owns every pass (creator): passes are tested with the Studio switch `DebugPass_<Key>` and with local-server test players |
| S | A restricted player's coin-feeding receipt is granted and logged, not kept |

Smaller decisions recorded in Progress: the IDs live only in `IdsByGameId` (no `Id = 0` fields); Coin Pouch amounts are computed on the client with the same pure function; the funnel's "PromptOpened" is logged when the offered item's prompt closes (no server event for opening); Grow All with nothing growing keeps an L token; a day-2 player never gets the Starter Pack popup.

### Contract additions (for later work)

- **Server services** (18, in `Main.server` order): Analytics, RemoteService, DataService, **PassService**, **PolicyInfoService**, SettingsService, TutorialService, MapService, PlotService, CrystalService, ShopService, ProgressionService, SocialService, LeaderboardService, **ReceiptService**, **RewardedAdService**, **OfferService**, **VipService**; `MonetizationIds` is a plain module.
- **PassService:** `Owns(player, key)`, `OwnsAny(player)`, `OwnershipChanged (player, key, owns)`; Player attributes **`Pass_<Key>`** (bool) for the client. **PolicyInfoService:** `IsRestricted(player)` (true until known or on failure); sends `PolicyInfo { paidRandomItemsRestricted }`. **ReceiptService:** `Granted (player, productKey, isAd)`. **CrystalService:** `SecondsLeft`, `InstantGrowTier`, `SetPendingTarget` / `TakePendingTarget`, `FinishNow`, `FinishAll`, `AutoShatter`; handlers `RequestInstantGrow` (RemoteFunction) and `UseToken`. **OfferService:** `NoteShatter(player)`, `ShownKind(player)`.
- **Client:** `ctx.Purchase` (PurchaseController: `HasPass/HasProduct`, `OwnsPass`, `IsRestricted`, `IsHidden`, `Price/PriceText`, `PromptPass`, `PromptProduct`, `InstantGrow`, `UseToken`, `CheckAd`, `RequestAd`, `InstantGrowKey`, `Changed`); `ctx.Config.Monetization`; `ctx.Logic.InstantGrow/AdCaps/LuckBoost`; `Theme.Icons.Ad/Store/Luck/Auto`; new screens **Store**, **CrystalMenu**, **OfferPopup** (all panels); `Hud.Buttons` gains Store, Luck, Auto; client order: State → Lighting → Sound → **Purchase** → UI → Brightness → CrystalRenderer → Effects → Tap → Tutorial.
- **Studio-only test hooks:** the player attribute `DebugPass_<Key>` (bool, set from the server command bar) forces a pass on or off and holds against the re-checks; `ServerStorage.DebugProcessReceipt` (BindableFunction) runs the real receipt handler with a receipt table.

### Task 13: steps (list them to you again before starting)

1. **Play Solo taps (you, by mouse in the game view: simulated clicks don't reach these buttons):** Store opens from the HUD (prices, OWNED); one product bought from the Store, e.g. Small Coin Pouch (free sandbox prompt; say so before the click); Luck "📺 Free" → test ad → boost; a growing crystal → CrystalMenu → Finish now (sandbox), 📺 Finish free, Use token; Auto toggle on/off (switch it **off** at the end: you own the pass); the offer popup's buy button and X. Also look at the 🛍️ / 🍀 icon size on the 60 px buttons and the VIP trail while walking.
2. **Starter Pack popup on a day-1 profile:** temporarily `Config.Game.ProfileStoreName = "PlayerData_Test5"` (Test1–Test4 used up), drive the tutorial and 10 shatters through the remotes (as in batch 4), check the popup appears once, you tap buy (sandbox) → granted, funnel steps 1–3 in Output; **revert the store name** afterwards and check the file is identical to the committed one.
3. **Local server, 2 players (you start it: Test tab → Clients and Servers, 2 players; click into each window so the MCP sees it):** A's `RequestInstantGrow` on B's pedestal returns nil; force `DebugPass_VIP` on A → B sees A's tag and trail; a pass bought by a test player (sandbox) → the server confirms or the Studio fallback warns (change R); optionally a restricted check isn't possible (no restricted account).
4. **Publish and phone:** remind you first: end every test session, check File → Version History, join on the phone from the DEV place link. Checks: no 📺 button anywhere (change Q); Store, Luck, Auto, CrystalMenu by touch; emoji icons; the VIP trail; then **one real 9 R$ purchase** (Instant Grow S on a crystal with 15 min or less) → granted once; rejoin → not granted again; the sale in the Creator Dashboard.
5. Then review (code search for price numbers in UI code, nothing paid touching size/overgrowth, `ProcessReceipt` set once), final tests/StyLua/build, the **Outcome** section, personal-data scan, and a commit when you ask; ask before opening a pull request.

### Still unchecked (from the Findings)

Taps on every new button (step 1); the Starter Pack popup and funnel steps 2–3; a restricted player (no test account; the checks are one line each); the ad tutorial refusal; a 15-second save timeout on a receipt; a pass bought by a non-owner; two players; the published DEV place and the real phone; how the 👑 and the sign trim look (no screenshot yet).

### Open items (not bugs; decide in task 13 or batch 6)

- The 🛍️ / 📺 / 🍀 emoji render small (14 px, two-line 60 px buttons); readable in Studio.
- Daily's ad button appears up to 1 s after the panel opens (its first refresh runs before the panel is visible).
- With both boosts on, an Odds row reads "⚡ ×2 Luck ×2" while the percentages use the capped ×3 (the numbers are the true odds).
- Batch 4's open item still stands: a crystal's "READY!" label can sit behind the HUD's top row.

### Environment and leftovers

- **Studio:** "Crystal Grove DEV" open; the Device Simulator on the **Galaxy A06**; no test GUI left in StarterGui. Rojo served on port 34872 during this session; after a restart, run `rojo serve` and ask you to click Connect.
- **MCP permissions you switched on:** `game-pass:write`, `developer-product:write` (can go off until icons are added), the upload folder `C:\Projects\videogames\uploads` (permanent; `uploads/tmp/blank.png` is the git-ignored placeholder), and possibly still the session scratchpad folder (can go).
- **Dev data changed this session:** your DEV profile: coins about 1.5K, today's ad counts used (FinishNow 2–3, Luck 1, CoinPouch 1; they reset at UTC midnight), a Luck Boost from a test receipt (expired by the next session), `Settings.AutoShatter = false`, session count 55. Test profile `Player_-1`: about 10.6K coins, tokens S2 M1 L2, `StarterPackBought = true`. Store `PlayerData_Test5` is still unused.

## Progress (2026-11-22)

- **Task 0 done:** branch `batch-5-monetization` created from `batch-4-ui-onboarding` (`ceeb4bb`, pushed). Pull request #4 was merged into `batch-1-setup` on 2026-11-22. Starting state: `lune run tests` **179 passed, 0 failed**; StyLua clean (Vendor skipped). The Rojo server from the last session is still listening on port 34872. The batch 4 record's Leftovers line now names pull request #4.
- **Plan changes G–N (2026-11-22)**, from the batch 4 work done after this plan was approved; **confirmed by you on 2026-11-22**:
  - **G. Screens reach purchases through `ctx.Purchase`.** `PurchaseController` (a controller) owns `RequestInstantGrow` (the RemoteFunction), `UseToken`, `RequestAd`, every `Prompt…Purchase` call, the price cache and the ad-availability check. UIController passes it to screens as `ctx.Purchase` (`Price(kind, key)`, `PromptPass(key)`, `PromptProduct(key)`, `InstantGrow(pedestal)`, `UseToken(pedestal, tier)`, `RequestAd(placement, pedestal?)`, `AdAvailable()`). So Store, CrystalMenu and OfferPopup use **no remotes**; `Screens.spec` stays as it is (no InvokeServer, no require in screens), and `ALLOWED` gains no entries. The HUD keeps `SetSetting` for the Auto toggle.
  - **H. HUD slot layout.** The 100 × 64 slot can't hold two ≥ 48 px buttons with readable labels. Proposal: the slot becomes **128 × 56** at the same anchor (`(1, −104, 1, −8)`), with **🛍️ Store** and **🍀 Luck** as two 60 × 56 buttons (icon over a short label: "Store"; "12:30" / "Free" (📺) / the price). "Next free Surge in mm:ss" sits as a small label just above the slot. Computed from the batch 4 measurements: the slot spans x 434–562 on the iPhone 7 (jump button at 571, Shatter All ends at 423) and 453–581 on the S25 Ultra (jump at 590). **🤖 Auto** is an 80 × 52 toggle directly left of Shatter All (x 155–235 on the iPhone 7; the thumbstick ends at 103), owners only. All three go into `Hud.Buttons`, so the tutorial lock disables them. To be measured on the three phones before it counts.
  - **I. Daily ad button.** After claiming (and only if an ad is available and unused today), the disabled "Claimed" button moves left (centre −108 px) and a 200 × 52 **"📺 Bonus coins"** button with a "Watch a short ad" subtitle takes the right half of the same row (y 98). "Come back tomorrow!" stays at y 156–178, so the content height stays 184 px. Checked in a 685 × 280 frame in every state before it counts.
  - **J. Crystal menu.** Tapping a growing crystal opens the **CrystalMenu panel** (in the panel set) when at least one option exists (Finish now with a non-zero product ID, a fitting token, or an available ad) and the tutorial isn't active; otherwise the existing "Ready in m:ss" bubble shows, as now. The panel shows the seed, the time left and up to 3 buttons in one row.
  - **K. Tutorial overrides win.** The tutorial's 8 s first grow is not halved by Fast Grow, and its forced Glowing is not re-rolled; Fast Grow, Luck Boost and Surge apply to every other plant. The Auto Shatter loop skips players whose tutorial is active.
  - **L. Instant-grown crystals don't touch the weekly best (a bug found while reading).** `CrystalService` currently updates `WeeklyBest` for an instant-grown crystal and only `Submit` skips it. A big instant-grown crystal would then raise your weekly best and **block a later, smaller but legitimate best from being submitted**, and the HUD's 🏆 would show it. Fix: skip the weekly-best step for instant-grown crystals (`newBest` stays false).
  - **M. `Result.luau` joins the Files table (task 12)** for the guardrail 2 line "Instant-grown crystals don't count for the board" on instant-grown cards.
  - **N. Offers wait for a clear screen.** The 10th shatter always shows a result card, so `OfferService` sends `Offer` (and logs `OfferShown`, marking the session's popup as used), and `OfferPopup` waits until no result card is showing, no panel is open and the tutorial isn't active (up to 30 s, otherwise it's dropped for this session).
  - **Unchanged:** `LuckBoost.chanceMult` = min(×3, luck × surge); Double Coins multiplies the shatter coins only (not the tutorial bonus); `SetSetting("AutoShatter")` accepted for owners only; remotes 17 → 19.
- **Product and pass IDs:** needed **before task 5** (tasks 1, 3 and 4 don't need them). Task 1 checks whether Open Cloud (via the Studio MCP) can create game passes and developer products in the DEV universe and what API key scopes that needs; you then choose between that and Creator Dashboard steps.
- **Task 1 done (2026-11-22, orchestrator); plan changes O–Q from it confirmed by you on 2026-11-22** (Findings → Task 1).
  - **Remotes:** `Offer` and `PolicyInfo` (both Event, ToClient) added to `Net/Remotes.luau`: **19 entries**. `SetSetting` already accepted `"AutoShatter"`; its handler changes in task 9.
  - **Strings:** 56 new keys in `en.luau`: the HUD slot (Store, Luck, the time left, Free, "Next free Surge in {time}", Auto), `Price.Robux` = "R$ {price}" (the number always comes from `GetProductInfoAsync`), the Store sections, 5 pass names and benefit lines, the product names and content lines (with `{coins}`, `{count}`, `{seed}`, `{minutes}`, `{mult}` filled from config and the snapshot, so no amount is typed twice), the crystal menu, the ad button and its "Watch a short ad" subtitle, the offer titles, the result line "Instant-grown crystals don't count for the board", and 9 toasts (the plan's three plus no-more-ads-today, ad cooldown, token used, purchase added, luck time left, unavailable in your region). Emoji stay in `Theme.Icons` (batch 4 rule).
  - **Changed string:** `Odds.Note` "The same odds for every player." → "Base odds are the same for every player.", since a Luck Boost now changes one player's odds; plus `Odds.LuckBoost` "Luck ×{mult}" and `Odds.BoostedNote`.
  - Tests **179 passed, 0 failed**; StyLua clean; `rojo build` succeeds.

- **Task 2 done (2026-11-22, orchestrator through Open Cloud, at your choice; you switched on `game-pass:write` and `developer-product:write` and approved the upload folder):** the 5 passes and 10 products exist in the DEV experience (GameId / universe **10777641396**). You approved the exact list (names, prices, descriptions) before the first create call.
  - **Settings, all 15:** on sale; default prices as in the monetization spec; regional pricing off and managed pricing off (fixed prices for testing; Managed Pricing is a launch step, batch 6); free trials off on every pass. Checked afterwards with the two list endpoints: 5 passes, 10 products, every name, price and flag as approved.
  - **Request format:** both create endpoints accept only `multipart/form-data` (a JSON body gave 415), and the MCP tool sends multipart only with a media file attached. A 68-byte 1 × 1 transparent PNG from the session scratchpad was attached under an unused field name, so it was ignored: every pass shows the same default icon asset and every product another, which a real upload (a new asset each time) wouldn't give. **No icons are set; yours go in later** (Creator Dashboard, or a PATCH with `imageFile`).
  - **IDs** (public; not personal data): passes FastGrow 2096118369, DoubleCoins 2092536394, ExtraPedestals 2093706287, AutoShatter 2092686441, VIP 2092878404; products InstantGrowS 3734749807, InstantGrowM 3734749816, InstantGrowL 3734749821, GrowAll 3734749828, LuckBoost 3734749833, CoinPouchS 3734749994, CoinPouchM 3734749998, CoinPouchL 3734750007, SeedBundle 3734750013, StarterPack 3734750019.
  - **[Config/Monetization.luau](../../roblox/src/shared/Config/Monetization.luau):** `IdsByGameId[10777641396]` holds these IDs. **Small change from the plan:** the old `Id = 0` field on each pass and product was removed, so there's one place for IDs (two would drift). `Config.spec`'s old "numeric Id" test became a new one: every experience in `IdsByGameId` has a whole-number ID above 0 for every pass and product key, with no ID repeated.
  - **Product names in the game now match the prompts:** "Small / Medium / Large Coin Pouch" (task 1 had "Coin Pouch" and "Big Coin Pouch").
  - Tests **239 passed, 0 failed**; StyLua clean; `rojo build` succeeds.
  - **Leftover for you:** the two write permissions and the scratchpad upload approval can be switched off again; nothing else in this batch needs them (icons later would need the write scope again).
- **Upload folder (2026-11-22, at your request):** a permanent `uploads/` folder at the repo root, outside the Rojo tree, for files the Studio MCP uploads: `uploads/icons/` (committed, for your real icons) and `uploads/tmp/` (git-ignored; holds the `blank.png` placeholder). README → Starting a new session lists it. You approve `C:\Projects\videogames\uploads` in MCP Permissions; the scratchpad approval can go.
- **Task 3 done (2026-11-22, DeepSeek Flash, accepted with one comment fix):** [Logic/Receipts.luau](../../roblox/src/shared/Logic/Receipts.luau), [Logic/InstantGrow.luau](../../roblox/src/shared/Logic/InstantGrow.luau), with [Receipts.spec](../../roblox/tests/Receipts.spec.luau) (9 tests) and [InstantGrow.spec](../../roblox/tests/InstantGrow.spec.luau) (12 tests).
  - `Receipts.isProcessed`, `Receipts.record` (a new list; no duplicate; trims the oldest to `max`, at least 1). `InstantGrow.tierFor` (≤ 900 s S, ≤ 7,200 s M, else L; 0 or less is S), plus two helpers beyond the contract: `productKey(tier)` ("InstantGrowM") and `pickToken(tokens, needed)` (the smallest owned token tier at or above the needed one, for the crystal menu's "Use token").
  - Tests cover the 900 / 901 and 7,200 / 7,201 boundaries and history trimming at 100 (the 101st id drops only the oldest). Review fix: a comment said 0 or less maps to L; the code (correctly) returns S.
  - Recovery journal (5 entries; one "uncertain" first write of `Receipts.spec`, superseded by a committed edit; the file on disk is the tested one) checked and acknowledged. Tests **200 passed**.
- **Task 4 done (2026-11-22, DeepSeek Flash; the job stopped on its token budget after writing every file and passing its tests; nothing was missing, so no retry was needed; accepted as is):** [Logic/LuckBoost.luau](../../roblox/src/shared/Logic/LuckBoost.luau), [Logic/AdCaps.luau](../../roblox/src/shared/Logic/AdCaps.luau), `Economy.coinPouchAmount` in [Logic/Economy.luau](../../roblox/src/shared/Logic/Economy.luau), with [LuckBoost.spec](../../roblox/tests/LuckBoost.spec.luau) (14 tests), [AdCaps.spec](../../roblox/tests/AdCaps.spec.luau) (21 tests) and 3 new tests in `Economy.spec`.
  - **LuckBoost:** `extend` (banks to at most 60 min), `chanceMult` = min(×3, luck × surge), plus `isActive`, `secondsLeft` and `canWatchAd` (the free-luck ad only with 5 min or less left; monetization spec, ad #2).
  - **AdCaps:** `check` in a fixed order (unknown placement → placement cap → daily total → cooldown), `recordRequest` (a new date resets the counts first; never mutates its input), plus `countsFor`, `total` and `cooldownLeft` (for the "Next free one in n s" toast).
  - **`coinPouchAmount`** reuses `goalReward` (same seed lookup and fallback): tier 1 gives 75 / 450 / 1,500, tier 10 gives 27,500,000 / 550,000,000.
  - Tests cover the caps 5 / 3 / 1, the total of 9 (with the placement caps raised so only the total applies), the cooldown at 59 / 60 s, the reset on a new date, banking to 60 min and the ×3 cap with Surge.
  - The temporary `_tmp_check.luau` the job wrote was already deleted. Recovery journal (8 entries) checked and acknowledged. Tests **238 passed, 0 failed** (179 + 59); StyLua clean.
  - **Delegation lesson:** in DeepSeek's shell `%USERPROFILE%` is the workspace, not your user folder, so `set PATH=%USERPROFILE%\.rokit\bin;…` hides Lune; `lune` and `stylua` are already on its PATH (README updated).
- **Task 5 done (2026-11-22, orchestrator; Studio results in Findings → Task 5; change R proposed):** [MonetizationIds.luau](../../roblox/src/server/Services/MonetizationIds.luau), [PassService.luau](../../roblox/src/server/Services/PassService.luau), and one addition, [PolicyInfoService.luau](../../roblox/src/server/Services/PolicyInfoService.luau).
  - **MonetizationIds** (a plain module, no lifecycle): `get()`, `passId(key)`, `productId(key)` and the reverse `passKey(id)` / `productKey(id)` for incoming events and receipts. It reads `IdsByGameId[game.GameId]` and keeps only config keys with whole-number IDs above 0 (frozen tables). Any other experience, including an unpublished place (GameId 0), gets none.
  - **PassService:**
    - On join it checks every pass with `UserOwnsGamePassAsync` (3 tries, 1 s and 2 s backoff, in parallel), and again every 60 s for the first 5 minutes for passes not yet owned.
    - On the **server-side** `PromptGamePassPurchaseFinished` with `wasPurchased`, a fresh ownership call must confirm before the pass turns on; it then logs `PassPurchased` (CustomField01 = the pass key).
    - Ownership only turns on during a session, never off: a refund is off at the next join. Nothing is read from the client or saved in the profile.
    - API: `Owns(player, key)`, `OwnsAny(player)` (for the Day-2 offer), `OwnershipChanged` (player, key, owns).
  - **How the client learns ownership (contract addition):** Player attributes **`Pass_<Key>`** (bool), set to false on join and true when confirmed, the same way `FriendBonus` already works. The snapshot is unchanged.
  - **Studio-only parts:**
    - (1) If a Studio test purchase isn't confirmed by `UserOwnsGamePassAsync`, the server event alone turns the pass on for that session, with a warning. Whether Studio confirms it is checked in Play.
    - (2) A test can switch a pass on or off by setting the player attribute `DebugPass_<Key>` from the server command bar (for the "benefit disappears when ownership is false" check).
  - **PolicyInfoService (not in the Files table; the plan names the `PolicyInfo` remote but no service that sends it):** reads `GetPolicyInfoForPlayerAsync` on the server at join (3 tries), keeps `IsRestricted(player)` and sends `PolicyInfo { paidRandomItemsRestricted }`. **A player counts as restricted until the lookup succeeds, and if it fails** (the safe side of the policy). Receipts (task 6) and the offers use `IsRestricted`.
  - `Main.server`: PassService and PolicyInfoService after DataService (14 services). Tests **239 passed**; StyLua clean; `rojo build` succeeds; Vendor untouched.
  - **Fix after the Studio check:** the Studio switch `DebugPass_<Key>` didn't hold (the 60-second re-check turned a forced-off pass back on for an owner). A forced value now holds against the join check and re-checks until that pass is bought. Also a Studio print of every prompt result (`wasPurchased`).
- **Task 6 done (2026-11-22, orchestrator; Studio results in Findings → Task 6):** [ReceiptService.luau](../../roblox/src/server/Services/ReceiptService.luau), plus the Instant Grow part of [CrystalService.luau](../../roblox/src/server/Services/CrystalService.luau) (moved here from task 9, because the Instant Grow receipt needs it).
  - **ReceiptService:** `ProcessReceipt` is set once, in `Start` (a code search finds one assignment).
    - Per receipt: player missing or profile not loaded → `NotProcessedYet`. A recorded `PurchaseId` skips the grant. An unknown product → warning and `NotProcessedYet`.
    - Otherwise it grants (no yields between the check and the record), records the ID (newest 100), then sends one toast and one `StateSync`.
    - It then calls `profile:Save()` and polls `profile.LastSavedData` every 0.25 s for up to 15 s. `PurchaseGranted` comes back only once the **saved** data holds the ID; otherwise `NotProcessedYet`. A recorded-but-unsaved ID (a replay before the save) also waits for the save instead of returning at once.
    - Ad rewards go through the same path, with an `AdRewarded` event when the channel is `AdReward`. A `Granted` signal (player, productKey, isAd) is there for the offers (task 8).
  - **Grants (exact spec content):**
    - **Instant Grow S/M/L:** finishes the pending target, or adds a token of that tier ("Token saved for later").
    - **Grow All:** finishes every growing crystal. **Small addition:** with nothing growing (a race with shattering) it keeps an L token, so nothing paid is lost.
    - **Luck Boost:** +15 min, banked to 60.
    - **Coin Pouch S/M/L:** `coinPouchAmount` at receipt time (economy event type IAP).
    - **Seed Bundle:** 3 of the highest unlocked seed.
    - **Starter Pack:** 1,000 coins, 3 Citrine and 30 min of luck, once. A second one becomes 1,000 + 3 × 150 = **1,450 coins**, with "Already bought — converted to coins".
    - **Change S:** a coin-feeding receipt for a restricted player is granted, with a warning and an `Anomaly` event (`RestrictedPurchase`).
  - **Config:** the Starter Pack contents (`Coins`, `SeedId`, `Count`, `LuckMinutes`), `PendingTargetSeconds = 60` and `ReceiptSaveTimeoutSeconds = 15` moved into `Config/Monetization`, so no amount is typed in the code. New strings: `Product.InstantGrowS/M/L`.
  - **CrystalService:** `SecondsLeft`, `InstantGrowTier`, `SetPendingTarget` / `TakePendingTarget` (60 s, per tier), `FinishNow` (`ReadyAt` = now, `InstantGrown` = true, pedestal attributes; no sync) and `FinishAll`.
    - The `RequestInstantGrow` handler (RemoteFunction) checks the crystal is the caller's and growing, picks the tier, stores the target and returns the product ID. It returns nothing during the tutorial or without IDs.
    - The `UseToken` handler spends the smallest token that covers the crystal.
  - **Studio-only:** a `ServerStorage.DebugProcessReceipt` BindableFunction runs the real handler with a receipt table, for the replay test.
  - `Main.server`: ReceiptService last (15 services). Tests **239 passed**; StyLua clean; `rojo build` succeeds; no `SizeRoll` or overgrowth in any monetization service.

- **Task 7 done (2026-11-22, orchestrator; Studio results in Findings → Task 7):** [RewardedAdService.luau](../../roblox/src/server/Services/RewardedAdService.luau).
  - **`RequestAd(placement, pedestal?)` checks, in this order:**
    1. the tutorial isn't active;
    2. the placement's reward product exists in this experience (FinishNow → Instant Grow S, Luck → Luck Boost, CoinPouch → Coin Pouch S);
    3. for Luck and CoinPouch, the player isn't restricted;
    4. no ad is already playing for this player;
    5. `AdCaps.check` passes (a toast with the seconds left for the cooldown, "No more free ones today" for a cap);
    6. the placement's own rule: **FinishNow**, your crystal with 15 min or less left (stored as the S pending target); **Luck**, 5 min or less of boost left; **CoinPouch**, today's daily reward claimed.
  - **Then:** it counts the request (`AdCaps.recordRequest`, `LastAdAt`) and syncs, logs `AdRequested`, and calls `CreateAdRewardFromDevProductId` + `ShowRewardedVideoAdAsync` in `pcall`. Only ReceiptService grants the reward. Any result other than `ShowCompleted` or `ShowInterrupted` (closed early) gives "No ad right now, try later". No `AreAdsAllowed` check (change P).
  - **Fix after the Studio check:** `ShowRewardedVideoAdAsync` yields for the whole ad (about 20 s in Studio). So the "ad already playing" guard now forgets a request after 120 s; an ad call that never returned can't block ads for the rest of the session.
  - `Main.server`: RewardedAdService last (16 services). Tests **239 passed**; StyLua clean; `rojo build` succeeds.

- **Task 8 done (2026-11-22, DeepSeek Flash, accepted first time; wiring by the orchestrator):** [OfferService.luau](../../roblox/src/server/Services/OfferService.luau).
  - **One popup per session, never during the tutorial.** Day 1 (the first join is today, UTC): the **Starter Pack** card at the **10th shatter of the session**, if not bought, the player isn't restricted, and the product exists. Day 2 or later: the **Double Coins** card **30 s after the profile loads** (so pass checks and the UI have settled), if no pass is owned, the player isn't restricted (change O), and the pass exists.
  - **Reading of the specs:** a day-2 player never gets the Starter Pack popup (the monetization spec: "the session's popup offer is Double Coins instead of the Starter Pack; otherwise no popup"); the Starter Pack stays in the Store.
  - **Analytics:** `OfferShown` and `OfferPurchased` (CustomField01 = kind); funnel `FirstPurchase` 1 OfferShown → 2 **PromptOpened** → 3 Purchased. **No server event exists for a prompt opening** (MarketplaceService has none), so step 2 is logged when the offered item's purchase prompt **closes** (any outcome), via `PromptProductPurchaseFinished` / `PromptGamePassPurchaseFinished`. Step 3 comes from `ReceiptService.Granted` (Starter Pack) or `PassService.OwnershipChanged` (Double Coins).
  - It changes no data and grants nothing; `ShownKind(player)` for tests.
  - **Wiring (orchestrator):** `CrystalService` calls `OfferService:NoteShatter(player)` after the tutorial step of every shatter (step 6c; required on first use, so no require cycle); `Main.server`: OfferService last (17 services).
  - Recovery journal (2 entries; the "uncertain" first write superseded by a committed formatting edit) checked and acknowledged. Tests **239 passed**; StyLua clean; `rojo build` succeeds; DeepSeek's `build_check.rbxlx` deleted.

- **Task 9 done (2026-11-22, orchestrator; Studio results in Findings → Task 9):** [CrystalService.luau](../../roblox/src/server/Services/CrystalService.luau), [SettingsService.luau](../../roblox/src/server/Services/SettingsService.luau), [LeaderboardService.luau](../../roblox/src/server/Services/LeaderboardService.luau), [PlotService.luau](../../roblox/src/server/Services/PlotService.luau), `Config/Monetization` (`DoubleCoins.CoinMult = 2`).
  - **Plant** (split into `plantOne`, which changes data only, and the `Plant` handler, which syncs):
    - mutation `chanceMult = LuckBoost.chanceMult(now, LuckBoostEndsAt, surge, 2, 2, 3)`, so luck and surge multiply, capped at ×3;
    - **Fast Grow** gives `speedMult = 0.5` in `Growth.growSeconds` (multiplies with the lamp);
    - the tutorial's 8 s grow and forced Glowing still win over both (change K).
  - **Pedestals 11–13** are unlocked only while Extra Pedestals is owned. Growing crystals there can still be shattered; new plants are refused. `PassService.OwnershipChanged` redraws the plot.
  - **Double Coins:** the shatter `coinMult × 2`. Not applied to the tutorial bonus, carats, daily rewards, goals or pouches.
  - **Change L:** instant-grown crystals skip the weekly-best step entirely (no `newBest`, no `Submit`).
  - **Auto Shatter:** `CrystalService:AutoShatter(player)` runs from a server loop every 2 s over the players in the server (so never offline). It needs the pass, the setting on and no tutorial running. It shatters every ready crystal (one `ShatterResult` each), replants the same seed if the bag has one, and sends one `StateSync`. `SettingsService` accepts `SetSetting("AutoShatter")` only from pass owners; the loop re-checks the pass on every run.
  - **VIP:**
    - **👑** before the name in a board row: `PassService` for players in this server, otherwise one cached `UserOwnsGamePassAsync` per user, during the board refresh.
    - A **gold trim** (a 10 px gold `UIStroke` border, `VipTrim`, made on first use in the sign's SurfaceGui) on the cave sign, set at plot assignment and on `OwnershipChanged`.
  - **Code search (acceptance):** `Rolls.size` and `Growth.overgrowth` receive only config values; no pass, boost or instant-grow value reaches them; `Submit` is reached only for crystals that aren't instant-grown.
  - Tests **239 passed**; StyLua clean; `rojo build` succeeds; Vendor untouched.

- **Task 10 done (2026-11-22, Haiku, accepted first time; start order by the orchestrator):** [VipService.luau](../../roblox/src/server/Services/VipService.luau).
  - For VIP owners, on every spawn and on `PassService.OwnershipChanged`: a gold **"VIP" name tag** (`BillboardGui` "VipTag" on the head, 4 × 1.2 studs, 2.6 studs up, FredokaOne, black outline, **`AlwaysOnTop = false`** (batch 4 lesson), max distance 80) and a gold-to-white **sparkle Trail** (`VipTrail` between two attachments on the root part, lifetime 0.6 s, light emission 1). Idempotent; removed when ownership turns off (Studio switch). Cosmetic only.
  - `Main.server`: VipService last (18 services). Tests **239 passed**; StyLua clean; `rojo build` succeeds; Haiku's temporary build file removed.

- **Task 11 done (2026-11-22, DeepSeek Flash in three jobs, all accepted, two with small orchestrator fixes; wiring by the orchestrator):** [PurchaseController.luau](../../roblox/src/client/Controllers/PurchaseController.luau), [Screens/Store.luau](../../roblox/src/client/UI/Screens/Store.luau), [Screens/CrystalMenu.luau](../../roblox/src/client/UI/Screens/CrystalMenu.luau).
  - **Job A, PurchaseController (accepted first time):** the only client code touching Marketplace, AdService and the purchase remotes (change G). Its API, `ctx.Purchase`:
    - `HasPass/HasProduct`, `OwnsPass` (the `Pass_*` attributes), `IsRestricted` (true until `PolicyInfo` arrives);
    - `IsHidden(kind, key)` (no ID, or restricted and coin-feeding, including Double Coins, change O);
    - `Price/PriceText` (a cache filled by concurrent `GetProductInfoAsync` calls; "…" until loaded);
    - `PromptPass`, `PromptProduct` (refuses Instant Grow), `InstantGrow(pedestal)` (`RequestInstantGrow:InvokeServer` → prompt; one at a time), `UseToken`;
    - `CheckAd` (`GetAdAvailabilityNowAsync`), `RequestAd` (refuses Luck/CoinPouch when restricted; re-checks availability right before each request), `InstantGrowKey` (display only), and a `Changed` event.
  - **Job B, Store (the job stopped on its token budget after writing the whole file; nothing was missing, so no retry was needed):** one scrolling list with three sections: Passes, Boosts (Luck Boost; Grow All only with 5+ crystals growing, as in the monetization spec) and Coins & Seeds (the pouches with their exact coin amount, the Seed Bundle with the seed's name, and the Starter Pack until bought). Each card has a name, a description and a live price button; owned passes show "OWNED" (disabled). Hidden items and empty section headers disappear. **Review fix (orchestrator):** card names and descriptions now shrink to fit (names at most 17 px, descriptions at most 12 px); six texts were cut off in the phone-size check.
  - **Job C, CrystalMenu (also stopped on its budget after writing the whole file):** the seed name, a live "Ready in m:ss", and up to three buttons: Finish now (the tier's live price), 📺 Finish free with the "Watch a short ad" subtitle (15 min or less left, an available ad, and the caps allow it, a cooldown included), and Use token (the smallest covering token). It closes itself when the crystal ripens or disappears. **Review fix (orchestrator):** don't start the 0.5 s tick when opening a crystal that has already ripened.
  - **Coin Pouch amounts are computed on the client** with the same pure `Economy.coinPouchAmount` the receipt uses, instead of a new snapshot field (the plan said "computed on the server and sent in the snapshot"; the number is identical).
  - **Wiring (orchestrator):**
    - `UIController` adds `ctx.Purchase`, `ctx.Config.Monetization` and `ctx.Logic.InstantGrow/AdCaps/LuckBoost`, plus Store and CrystalMenu in the screen order and the panel set.
    - `Main.client`: PurchaseController before UIController.
    - `Theme.Icons` gains Ad 📺, Store 🛍️, Luck 🍀, Auto 🤖.
    - **`TapController`:** a growing crystal opens the crystal menu when the tutorial is done and there's an option (a Finish-now product ID or a covering token), otherwise the old bubble (change J). **Also fixed:** a locked pedestal can still be tapped to shatter a crystal on it (Extra Pedestals lost); before, any tap on a locked pedestal was ignored.
  - **Acceptance (code search):** no price numbers in the UI code (the only hit was a comment's "R$ 249" example, reworded); Store and CrystalMenu use no remotes and no `require` (`Screens.spec` passes, `ALLOWED` unchanged).
  - Recovery journals (A: 2 entries, B: 1, C: 1) checked and acknowledged. Tests **239 passed**; StyLua clean; `rojo build` succeeds; no build files left behind.

- **Task 12 done (2026-11-22, DeepSeek Flash in four jobs plus one retry, all accepted, one with a small orchestrator fix; wiring by the orchestrator):** [Screens/OfferPopup.luau](../../roblox/src/client/UI/Screens/OfferPopup.luau), [Hud.luau](../../roblox/src/client/UI/Screens/Hud.luau), [Daily.luau](../../roblox/src/client/UI/Screens/Daily.luau), [Result.luau](../../roblox/src/client/UI/Screens/Result.luau), [Odds.luau](../../roblox/src/client/UI/Screens/Odds.luau), [UIController.luau](../../roblox/src/client/Controllers/UIController.luau).
  - **Job A, OfferPopup (accepted first time):** a panel with the offer title (gold), the content line, a live-price buy button (Starter Pack → `PromptProduct`, Double Coins → `PromptPass`) and an **enlarged 56 px X**. No countdown. It won't open for an item that's hidden, already bought or owned.
  - **Job B, HUD (layout H): the first job stopped on its token budget with the work half done** (the refresh function and its calls written with one syntax error; the buttons and state missing). **Retried with DeepSeek, as your rule says;** the retry completed it.
    - **Buttons:** the slot is now 128 × 56 with **🛍️ Store** (opens the Store) and **🍀 Luck**, plus an 80 × 52 **🤖 Auto** toggle left of Shatter All (owners only; green when on; `SetSetting("AutoShatter")`). All three are in `Hud.Buttons`, so the tutorial lock disables them.
    - **The Luck button's four states:** hidden (restricted or no product); boost active "🍀 12:30" (opens Odds); "📺 Free" when an ad is available and the caps allow it (ad availability re-checked at most every 30 s), with "Watch a short ad" above it; otherwise the live price, with "Next free Surge in mm:ss" above it.
  - **Job C, Daily (layout I) and Result (M) (accepted):**
    - **Daily:** after claiming, if today's Coin Pouch ad is unused and an ad is available, "Claimed" moves left and **"📺 Bonus coins / Watch a short ad"** takes the right half of the same row.
    - **Result:** an instant-grown crystal's card grows taller with **"Instant-grown crystals don't count for the board"**. **Review fix (orchestrator):** the note was squeezed to about 8 px on one 18 px line; it now has 26 px and two lines at 11 px (card 140 × 100).
  - **Job D, Odds (accepted first time):** the mutation odds use `LuckBoost.chanceMult` (luck × surge, capped at ×3, the same as the server roll). Rows show "⚡ ×2" and/or "Luck ×2". The note switches to "Boost active: these are your odds right now." (gold).
  - **Orchestrator:** OfferPopup in the screen order and the panel set. The **`Offer` routing** (change N): the event is held until the tutorial is done, no panel is open and no result card is showing, for up to 30 s (otherwise dropped), then opens the popup. The popup screen needs no remote (`Screens.spec` unchanged).
  - **Cleanup:** a stray `roblox/tests_out.txt` (a test log from an earlier job that stopped on its budget) was deleted; new README lesson: check `git status` after every job. All five recovery journals checked and acknowledged.
  - Tests **239 passed**; StyLua clean; `rojo build` succeeds; Remotes 19; Vendor untouched.

## Findings

### Task 1: outside facts (checked 2026-11-22)

Pages read through the Studio MCP doc fetcher (each shows `last_updated: 2026-11-20`).

| Question | Official page | What it says | Effect on this plan |
|---|---|---|---|
| (a) Do coin-bought crystal rolls count as paid random items? | [Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items.md) | Random items bought "directly or indirectly with Robux", **including with paid in-game currency**, count. **"Luck boosts" are listed by name** as probability modifier items. Boost effects "must be numerically explained" before purchase, and boosted odds shown live. Odds must be percentages summing to 100 %. For `ArePaidRandomItemsRestricted` players, allowed treatments include hiding the item or blocking it with "Sorry, this item is unavailable for users in your region". | **Guardrail 5 stays** (no relaxing). The Luck Boost card states "Mutation chances ×2 … next 15 min". **Gap (change O):** Double Coins also turns Robux into coins. |
| (b) `GetProductInfoAsync` | [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService.md) | `GetProductInfoAsync(assetId: int64, infoType?: InfoType): Dictionary`; `PriceInRobux` is the price to show; it **throws** for an unknown ID; concurrent calls are batched. | As planned, in `pcall`. IDs of 0 are never queried. |
| (b) `GetPassOwnershipAsync` | same page | **Not on the page.** `UserOwnsGamePassAsync(userId, gamePassId): boolean` is cached; the cache updates on `PromptGamePassPurchaseFinished`; it "always returns true" on the first join after a purchase; a purchase made outside the experience reaches a running session "eventually … several minutes". | The plan's escalation applies: **`UserOwnsGamePassAsync` only**. The 60-second re-check in the first 5 minutes stays (it may not catch a website purchase; the next join does). |
| (b) `ProcessReceipt` | same page | Set once. **No time-based retry:** a `NotProcessedYet` receipt comes back only on the player's next purchase or rejoin. It may yield as long as the server runs. It can run on two servers at once if the player joins a second server mid-callback. `BindReceiptHandler` is a newer alternative; `ProcessReceipt` isn't deprecated. | As planned (the save-confirmed flow). Wording fix: after a timeout the receipt comes back **at the next join or purchase**, not "later". The session lock means a second server can't load the profile, so it returns `NotProcessedYet`. |
| (b) Ad purchase channel | [ProductPurchaseChannel](https://create.roblox.com/docs/reference/engine/enums/ProductPurchaseChannel.md) | `InExperience` 1, `ExperienceDetailsPage` 2, **`AdReward` 3**, `CommerceProduct` 4. | As expected: `Enum.ProductPurchaseChannel.AdReward`. |
| (b) Ad enums | [AdAvailabilityResult](https://create.roblox.com/docs/reference/engine/enums/AdAvailabilityResult.md), [ShowAdResult](https://create.roblox.com/docs/reference/engine/enums/ShowAdResult.md), [AdService](https://create.roblox.com/docs/reference/engine/classes/AdService.md) | Availability: `IsAvailable`, `DeviceIneligible`, `ExperienceIneligible`, `InternalError`, `NoFill`, `PlayerIneligible`, `PublisherIneligible`. Show: `ShowCompleted`, `AdNotReady`, `AdAlreadyShowing`, `InternalError`, `ShowInterrupted`, `InsufficientMemory`. `GetAdAvailabilityNowAsync` is **client only**; `ShowRewardedVideoAdAsync(player, reward, placementId?)` is **server only**; the reward arrives through `ProcessReceipt` on `AdReward`. | As planned. |
| (b) Policy from the server | [PolicyService](https://create.roblox.com/docs/reference/engine/classes/PolicyService.md) | `GetPolicyInfoForPlayerAsync(player)` works on the server (only a client asking about another player errors). **`AreAdsAllowed` is documented as required for immersive ads**, not rewarded video. | The server reads the policy and sends `PolicyInfo`. **Change P:** don't gate rewarded video on `AreAdsAllowed`. |
| Creating the items | [Game passes](https://create.roblox.com/docs/cloud/reference/features/game-passes.md), [Developer products](https://create.roblox.com/docs/cloud/reference/features/developer-products.md) (Open Cloud) | `POST /game-passes/v1/universes/{id}/game-passes` (scope `game-pass:write`) and `POST /developer-products/v2/universes/{id}/developer-products` (`developer-product:write`), on apis.roblox.com, with name, description, price, `isForSale`, regional/managed pricing and (passes) trial flags; icons optional and can be added later. | **Possible through the Studio MCP.** Read scopes are granted (the DEV universe has 0 passes and 0 products); the two write scopes are **not granted** (Money & monetization, high risk). Passes and products **can't be deleted**. |

### Task 1(c): ad and policy APIs in Studio (Play Solo, 2026-11-22)

Your DEV profile; started and stopped by the orchestrator; no code changed.

| Call | Where | Result |
|---|---|---|
| `GetAdAvailabilityNowAsync(RewardedVideo)` | client | **`IsAvailable`** (0.35 s), no error. **Not what the plan expected** (it assumed "not available" before eligibility). |
| `GetPolicyInfoForPlayerAsync` | client and server | Both work: `ArePaidRandomItemsRestricted = false`, `AreAdsAllowed = true`. |
| `CreateAdRewardFromDevProductId(0)` | server | Returns an `AdReward` (no error). |
| `ShowRewardedVideoAdAsync(player, reward)` | server | Returns **`ShowAdResult.InternalError`** after 0.08 s, no error thrown. |
| Output | — | "Rewarded video ads are not enabled for this universe" (twice), plus the known `rbxassetid://203785492` warning. |

**Effect (change Q):** in Studio the 📺 buttons would show and every ad request would end in the "No ad right now" toast, so verification check 5 ("no 📺 button anywhere") can't pass in Studio as written. Whether the published DEV place also reports `IsAvailable` is still to check (task 13, on the phone).

### Task 5: Studio Play Solo (2026-11-22)

Rojo reconnected by you (Studio sizes matched the files on disk); your DEV profile; Device Simulator Galaxy A06; three short Play Solo runs started and stopped by the orchestrator.

| Check | Result |
|---|---|
| Start | **Passed.** `[Server] Started 14 services`, no new errors (only the known `rbxassetid://203785492` warning). `game.GameId` = 10777641396, so the DEV IDs are used. |
| Ownership on join | All 5 passes reported **owned** for your account, all within a second (`Pass_*` attributes true on the server and the client). |
| Policy | **Passed.** `paidRandomItemsRestricted = false` from the server lookup. A client listener connected **after** the event was sent still received it (remote events queue until a listener connects). |
| Studio switch `DebugPass_FastGrow = false` | **Failed, then fixed and passed.** First run: off at once, the client saw it, but back on within a minute (the re-check; it can't have been the prompt, see below). After the fix: still off 70 s later (past the re-check); forcing it on worked. |
| Fast Grow purchase prompt | Roblox showed **"Error: You already own this item. Your account has not been charged."** (your screenshot); there was no Buy button. |

**Finding (affects verification):** your account owns every pass in the DEV experience. Roblox's own purchase prompt says so too, so it isn't a bug in the check. The likeliest reason is that your account created them (the docs page read doesn't say). So with your account:
- every pass benefit is always on;
- the purchase → confirm path can't run;
- the Day-2 Double Coins offer ("no pass owned") never appears.

**Dev data changed:** your DEV profile's session count went 41 → 43; nothing else.

### Task 6: Studio local server, 1 test player (2026-11-22)

Option A, chosen by you: you started the local server with 1 player (`Player1`, ID −1, test profile `Player_-1`, tutorial already done); your DEV profile wasn't used. Receipts went through the real handler via `ServerStorage.DebugProcessReceipt` (server window); results read from Player1's `StateSync` and `Toast` (client window). The MCP saw the two test windows only after you clicked into each.

| # | Check | Result |
|---|---|---|
| — | Start | **Passed.** 15 services, no new errors; Player1 owns no pass (all `Pass_*` false, as change R expects for a non-creator); not restricted. Baseline: 50 coins, tier 2 (Amethyst, base 60), 5 Quartz, no tokens, no luck, Starter Pack not bought. |
| 1 | Coin Pouch S / M / L, each sent twice with the same `PurchaseId` | **Passed.** +300 / +1,800 / +6,000 (5 / 30 / 100 × 60) → 8,150; each replay granted nothing ("replay … not granted again"); each first receipt returned `PurchaseGranted` after 0.5–0.8 s (the save confirmed), each replay at once (already saved). |
| 2 | Seed Bundle, Luck Boost, Starter Pack (1st, its replay, a 2nd purchase) | **Passed.** +3 Amethyst (the highest tier); luck 15 + 30 = 45 min from the start; Starter Pack +1,000 coins, +3 Citrine, `StarterPackBought = true`; the 2nd became +1,450 coins with "Already bought — converted to coins"; total 10,600. |
| 3 | Instant Grow S / M / L and Grow All with nothing growing | **Passed.** One token each (S1, M1, L1) and an L token from Grow All (L2), "Token saved for later"; replays added nothing. |
| 4 | Real Instant Grow path: plant 3, `RequestInstantGrow(1)` | **Passed.** Returned the S product (3734749807) for 18 s left; an empty pedestal returned nil. The receipt finished pedestal 1 with `InstantGrown = true` ("Instant Grow S added!"). |
| 5 | `UseToken(2)` | **Passed.** The S token was spent (S1 → S0); pedestal 2 finished, instant-grown; "Token used!". |
| 6 | Target gone before the receipt (verification check 2) | **Passed.** `RequestInstantGrow(3)`, then Grow All finished pedestal 3, Player1 shattered it (65 coins, `instantGrown = true`, `newBest = false`), then the Instant Grow receipt → an S token, "Token saved for later". |
| 7 | Ad-channel receipt; unknown product; player not in the server | **Passed.** The ad Coin Pouch S was granted (`ad=true`, `AdRewarded` logged); the other two returned `NotProcessedYet`. |
| 8 | A real Studio purchase prompt (Instant Grow S for a fresh Quartz) | **Passed.** You clicked Buy (free sandbox); Roblox's own `ProcessReceipt` call arrived with a real purchase ID and was granted. The crystal had already finished by itself (you clicked after its 19 s), so it became an S token (S2), as designed. |

**Acceptance criteria (task 6):** `ProcessReceipt` set once (code search: one assignment) — **passed**; every product grants its spec content exactly once, including a replay of the same `PurchaseId` — **passed** (all 10); `PurchaseGranted` only after the saved data contains the ID — **passed** (the handler polls `LastSavedData`; first receipts waited 0.5–0.8 s for it).

**Not checked yet:** a save that doesn't finish within 15 s (`NotProcessedYet`, then a replay at the next join); a restricted player's receipt (change S; no restricted test account); a real purchase on the phone (task 13).

**Dev data changed:** test profile `Player_-1` now has about 10,600 coins (+ shatter coins), 3 Amethyst, Citrine (seeds and the tier unlock), tokens S2 M1 L2, luck banked until about 45 min after the test, `StarterPackBought = true`, and a few `ProcessedReceipts`. Your DEV profile was not touched.

### Task 7: Studio Play Solo, ads (2026-11-22)

Your DEV profile (only today's ad counters, `LastAdAt` and luck changed; see below); four short Play Solo runs started and stopped by the orchestrator; requests fired from the client command bar; results from `StateSync`, `Toast` and the server Output. No steps from you.

| # | Check | Result |
|---|---|---|
| 1 | Luck ad (no boost) | **Passed, and more than expected:** counted at once (Luck 1, `LastAdAt` set). Studio then **played a test ad**; after about 20 s `ShowRewardedVideoAdAsync` returned **`ShowCompleted`**, and Roblox called `ProcessReceipt` on the **`AdReward`** channel with a real purchase ID → Luck Boost granted ("Luck Boost added!", `ad=true`). |
| 2 | Requests while that ad played (Luck again; FinishNow without a pedestal) | **Passed.** Both refused: "an ad is already running" (no count, no toast). |
| 3 | CoinPouch 10 s before the cooldown ends | **Passed.** Refused with "Next free one in 10 s". |
| 4 | Luck with 14 min of boost left | **Passed.** Refused ("boost has more than 5 min left"), no count. |
| 5 | CoinPouch after the cooldown (daily reward claimed today) | **Passed.** Counted (CoinPouch 1); the ad returned **`AdNotReady`** → "No ad right now, try later"; the count and cooldown stay (Decision 1). This request skipped the client's availability check; the real client calls it before every request (task 11). |
| 6 | A 2nd CoinPouch today | **Passed.** "No more free ones today" (`PlacementCap`). |
| 7 | FinishNow on a fresh Quartz (18 s left), after the client's availability check (`IsAvailable`) | **Passed.** Counted (FinishNow 1); test ad → `ShowCompleted` → `AdReward` receipt → the crystal finished **before** its own time, `InstantGrown = true`, "Instant Grow S added!". |
| 8 | Rejoin (Play stopped and started) | **Passed.** `AdCounts` = 2026-11-22, FinishNow 1, Luck 1, CoinPouch 1 and `LastAdAt` unchanged; another CoinPouch → "No more free ones today". |
| 9 | After the 120 s guard fix: two FinishNow requests 1.5 s apart | **Passed.** The 2nd refused ("already running"); the 1st completed and its receipt was granted. |

**Acceptance criteria (task 7):** no ad without passing every check — **passed** (refusals 2–6 and 8 never called the ad API; caps, cooldown and the daily total are also unit-tested); counts persist across a rejoin — **passed** (8); ad rewards go through `ProcessReceipt` — **passed** (1, 7, 9: `AdReward` receipts with real purchase IDs).

**Finding (refines change Q):** Studio doesn't just show the buttons: it **plays a test ad and delivers the reward through `ProcessReceipt`**, so the whole ad path is testable in Studio. Output still logs "Rewarded video ads are not enabled for this universe" each time. A request that skips the client's availability check can get `AdNotReady`.

**Not checked yet:** the tutorial and restricted-player refusals (no such profile in this run; the checks are one line each); the published DEV place, where the buttons must not appear (task 13, change Q).

**Dev data changed:** your DEV profile: today's ad counts FinishNow 2, Luck 1, CoinPouch 1 and `LastAdAt` (reset tomorrow); a 15-minute Luck Boost (expired by now); two instant-grown Quartz on pedestals 1–2 (ready to shatter); Quartz 5 → 4 after the Studio top-up; session count 44 → 46.

### Task 8: Studio Play Solo, offers (2026-11-22)

Your DEV profile (first join before today → day 2 or later; tutorial done; owns every pass); two short Play Solo runs started and stopped by the orchestrator. No steps from you.

| # | Check | Result |
|---|---|---|
| 1 | As you are (all passes owned), listening 38 s | **Passed.** No offer (`OwnsAny`). `[Server] Started 17 services`, no new errors. |
| 2 | All 5 passes forced off with `DebugPass_*` right after joining (change R), listening 40 s | **Passed.** Exactly **one** `Offer { kind = "DoubleCoins" }`, about 30 s after the profile loaded; Output `[Offer] … shown DoubleCoins` with `LogCustomEvent` (OfferShown) and `LogFunnelStepEvent` (step 1). |

**Not checked yet:** the Starter Pack popup at the 10th shatter of a day-1 session (needs a fresh profile that has finished the tutorial: store `PlayerData_Test5`); funnel steps 2–3 (a prompt and a purchase after an offer); both in task 13, with the popup UI.

**Dev data changed:** your DEV profile's session count 46 → 48; the Studio top-up refilled Quartz to 5.

### Task 9: Studio Play Solo, pass benefits (2026-11-22)

Your DEV profile (owns every pass; lamp 0, so a Quartz takes 20 s); one Play Solo run started and stopped by the orchestrator; passes forced off and on with `DebugPass_*` (change R). No steps from you.

| # | Check | Result |
|---|---|---|
| 1 | Shatter the two instant-grown Quartz left from task 7 | **Passed.** Both `newBest = false`; the weekly best stayed 2.00 ct (change L). Both were below 2.00 ct (1.15 and 1.58), so this run alone doesn't prove a bigger one would be ignored; the code review does. |
| 2 | Double Coins (owned) | **Passed.** Coins ≈ 2 × 15 × carats (ratios 1.97 and 1.98, the gap is the rounding down); with the pass forced off, ≈ 1× (0.96, 0.95). |
| 3 | Fast Grow (owned) | **Passed.** Quartz on pedestals 3 and 11: `ReadyAt − PlantedAt` = **10.0 s**; with the pass forced off, **20.0 s** (verification check 1: "a new Quartz takes 10 s"). |
| 4 | Extra Pedestals | **Passed.** Pedestals 11–13 `Unlocked = true` on join (9–10 still locked by coins); a plant on 11 worked. Forced off: 11–13 `Unlocked = false` at once, a plant on 12 refused, and the crystal already on 11 could still be shattered. |
| 5 | Auto Shatter on (`SetSetting(true)` as an owner) | **Passed.** Saved; pedestal 4 was shattered within the 2 s loop and replanted from the bag (Quartz 2 → 1). |
| 6 | Auto Shatter pass forced off | **Passed.** `SetSetting("AutoShatter", false)` refused (the setting stayed true); a ripe crystal was left alone for 5 s (no auto shatter). Forcing the pass back on resumed it at once (the setting was still on). |
| 7 | VIP | **Passed.** Your cave sign's `VipTrim` visible (10 px gold stroke); your board row `#1  👑 <name>  2.0 ct` from the board's second refresh (the first ran before the VIP check had finished). |
| — | Output | No errors (only the known `rbxassetid://203785492` warning). |

**Not checked yet:** the Luck + Surge mutation multiplier in play (random; covered by the `LuckBoost.chanceMult` unit tests and the code); how the 👑 and the trim look (no screenshot; with the VIP tag and trail in task 10/13); a non-owner's pass bought in a session turning a benefit on (change R: a test player in task 13).

**Dev data changed:** your DEV profile: coins 1,310 → 1,461; the Quartz bag used up (the Studio top-up refills it at the next join); one Quartz growing on pedestal 4; `Settings.AutoShatter` back to **false** (switched off again after the test, because you really own the pass); session count 49.

### Task 10: Studio Play Solo, VIP cosmetics (2026-11-22)

Your DEV profile (owns VIP); one Play Solo run started and stopped by the orchestrator. No steps from you.

| Check | Result |
|---|---|
| On join | **Passed.** Within 0.3 s of the character loading: `VipTag` on the head (text "VIP", `AlwaysOnTop = false`) and `VipTrail` on the root part. |
| `DebugPass_VIP` off, then on | **Passed.** Both removed at once, then added again. |
| Respawn (character reset) | **Passed.** Tag and trail on the new character. |
| Screenshot (Device Simulator, Galaxy A06) | **Passed for the tag:** a gold "VIP" above your character's head, readable, below the top HUD row. **The trail wasn't captured:** a move sent from the command bar is overridden by the client's control script, so the character stood still. |

**Not checked yet:** the trail on screen while walking (you, in task 13); another player seeing your tag (the 2-player test in task 13).

**Dev data changed:** none beyond the session count.

### Task 11: Studio, Store and CrystalMenu (2026-11-22)

**(a) Edit mode, fake `ctx` inside a 685 × 280 frame** (the S25 Ultra's measured safe area; temporary GUI deleted afterwards). Prices in the fake are the config defaults; ownership: VIP owned; snapshot: tier 3, 5 crystals growing, one S token.

| Check | Result |
|---|---|
| Store size | **Passed.** 616 × 257 at (34, 11) inside 685 × 280; list 592 × 189, canvas 708 (scrolls); cards 140 × 118; no button under 48 px. |
| Store texts | **Failed, then fixed and passed.** Six texts didn't fit (Auto Shatter, VIP, Luck Boost and Starter Pack descriptions; "Medium/Large Coin Pouch" names); after the fix none. Screenshots of the top (passes) and the bottom (Starter Pack) checked. |
| Store content | **Passed.** "R$ 249" etc. on passes; VIP "OWNED", disabled; Coin Pouch M "7.2K coins" (30 × Citrine 240); Seed Bundle "3 Citrine seeds"; Starter Pack "1K coins, 3 Citrine seeds and 30 min of Luck Boost"; Luck "Mutation chances ×2 … next 15 min"; Grow All visible with 5 growing. |
| Store, restricted player | **Passed.** Passes: Fast Grow, Extra Pedestals, Auto Shatter, VIP (no Double Coins); Boosts: Grow All only; "Coins & Seeds" header and cards hidden. |
| CrystalMenu, 9:39 left, one S token | **Passed.** 452 × 179 at (116, 50); title "Quartz", "Ready in 9:39"; three 136 × 56 buttons ("Finish now  R$ 9", "📺 Finish free / Watch a short ad", "Use token (S)"), all texts fit; the row ends at 94 of 111 px. Screenshot checked. |
| CrystalMenu, 50 min left | **Passed.** "Finish now  R$ 29"; no ad button (more than 15 min); no token button (an S token doesn't cover M). |
| CrystalMenu, FinishNow ads 5/5 today | **Passed.** Ad button hidden; Finish now and Use token stay. |
| CrystalMenu, crystal ripens | **Passed.** Closed by itself. |

**(b) Play Solo** (your DEV profile; Fast Grow forced off so a Quartz takes 20 s; no steps from you). A simulated mouse click (Studio MCP) on the growing Quartz, through the **real** TapController, opened the CrystalMenu: "Quartz", "Ready in 0:06", **"Finish now  R$ 9" with the live price** from `GetProductInfoAsync`, the 📺 Finish free button (Studio reports an ad available, change Q), no token button (your profile has none). It closed by itself when the crystal ripened. (A screenshot taken a moment later showed the crystal's own "READY!" label partly behind the top HUD row: the known batch 4 open item.)

**Not checked yet:** the Store opened from the HUD (the Store button is task 12); tapping Finish now / Use token / the ad button in the live menu; a phone; all in tasks 12–13.

**Dev data changed:** your DEV profile: one more Quartz planted and ripened on pedestal 1; session count +1.

### Task 12: Studio, HUD / offer / Daily / Result / Odds (2026-11-22)

Your DEV profile in Play Solo (orchestrator-run; no steps from you), plus an Edit-mode harness for Daily and Result in a 685 × 280 frame (deleted afterwards).

**Layout H, measured on three phones** (Play Solo, client positions; the thumbstick is the visible resting image):

| Phone (viewport) | Store / Luck | Auto | Gaps | Overlaps (incl. every grid button) |
|---|---|---|---|---|
| Galaxy A06 (705 × 338) | 473–533 / 541–601 × 216–272 | 174–254 × 220–272 | Luck→jump 9 px; thumbstick (29–103)→Auto 71 px | none |
| iPhone 7 (666 × 374; = iPhone SE screen) | 434–494 / 502–562 × 252–308 | 155–235 × 256–308 | Luck→jump 9 px; Shatter All→Store 11 px; thumbstick→Auto 52 px; Auto→Shatter All 8 px | none |
| Galaxy S25 Ultra (685 × 338) | 453–513 / 521–581 × 216–272 | 164–244 × 220–272 | Luck→jump 9 px; Shatter All→Store 20 px; thumbstick→Auto 61 px | none |

The iPhone 7 numbers equal the plan's computed ones. Screenshots on all three show 🤖 Auto, Shatter All, Store and Luck in one bottom row and the hint above. **Seen:** the 🛍️ and 📺/🍀 icons render small at 14 px on two-line 60 px buttons (readable; judge on the phone).

| # | Check | Result |
|---|---|---|
| 1 | Luck button states | **Passed.** No boost, ad available (Studio) → "📺 Free" with "Watch a short ad" above; after a Luck Boost receipt → "🍀 15:00", counting down. |
| 2 | Store from the HUD | **Not checked by a tap:** simulated mouse input reached the Shop button (a separate down/up) but not the Store button or a panel's X, so taps go to task 13 (you, by touch). |
| 3 | Offer routing and popup (all passes forced off, change R) | **Passed.** The Double Coins popup opened by itself about 30 s after the profile loaded: title "Double Coins", "2× coins from shattering", **"R$ 199" (live price)**, X 56 × 56, panel 424 × 224 inside the screen. Auto hid itself (its pass forced off). |
| 4 | Result card, instant-grown | **Failed, then fixed and passed.** Real path (plant → `RequestInstantGrow` → receipt → shatter): card 140 × 92 with the note, but scaled to about 8 px; after the fix 140 × 100, two lines at 11 px (harness screenshot). "Instant Grow S added!" toast shown. |
| 5 | Odds with a Luck Boost (no surge) | **Passed.** Mutations: None 85 %, Glowing 12 %, Molten 2.4 %, Prismatic 0.3 % (base 6 / 1.2 / 0.15 %), each "Luck ×2"; sizes unchanged (88 / 10 / 1.8 / 0.2 %); note "Boost active: these are your odds right now." |
| 6 | Daily, claimed, ad available (harness) | **Passed.** "Claimed" 47–247, "📺 Bonus coins / Watch a short ad" 263–463 (both × 98–150, 16 px apart), "Come back tomorrow!" 156–178: content height unchanged (184). The ad button appears up to 1 s after opening (Daily's first refresh runs before the panel is visible). Your real profile has today's Coin Pouch ad used, so its button correctly stays hidden. |
| — | Output | No errors on any run. |

**Not checked yet:** taps on Store, Luck, Auto, the popup's buy button and the crystal menu's buttons; the Starter Pack popup on a day-1 profile; a restricted player; a real phone. All in task 13.

**Studio MCP finding:** `user_mouse_input`'s single "click" action didn't fire GUI buttons; a separate mouse-down and mouse-up did, but only on a large button near the left (Shop). Presses aimed at the Store button and at a panel's X by instance path or by coordinates never arrived. Likely the Device Simulator's scaling (screenshots are about 671 px wide for a 705 px viewport) plus the 58 px top-bar inset. Taps on small or right-side buttons need you.

**Dev data changed:** your DEV profile: a Quartz instant-grown and shattered on pedestal 2 (+17 coins), a 15-minute Luck Boost (a receipt through the test hook), session count 55; the Device Simulator is back on the Galaxy A06.

### Plan changes O–Q (from task 1; confirmed by you on 2026-11-22)

- **O. Double Coins is not sold to restricted players.** It turns Robux into coins, and coins buy random rolls, so for `ArePaidRandomItemsRestricted` players it joins the hidden-and-refused list (its Store card and the Day-2 offer). If such a player already owns it (bought where it was allowed), the benefit stays. Fast Grow, Extra Pedestals, Auto Shatter, VIP, Instant Grow and Grow All stay available: they give no currency and don't change any odds.
- **P. Rewarded ads aren't gated on `AreAdsAllowed`** (it's for immersive ads). The gates are the client's `GetAdAvailabilityNowAsync` (which already covers under-13s and blocked regions), the server's caps, cooldown and target checks, and the `ShowAdResult`.
- **Q. Studio shows the ad buttons.** Keep the code as planned (no extra switch, so the buttons still appear by themselves once ads are enabled). Use the Studio behaviour to test the ad path (caps, cooldown, counting at request, the toast). Move verification check 5 to the published DEV place on your phone, where the buttons must not appear.
### Plan change R (from task 5; confirmed by you on 2026-11-22)

- **R. How passes are verified, since your account owns them all.**
  - **Benefits on and off** (check 1 and the monetization spec's "benefit disappears when ownership is false"): with your account, force each pass off with `DebugPass_<Key>`, see the benefit gone, force it on, see it back without rejoining.
  - **The real purchase path** (prompt → server event → confirm): in the Studio local server with test players (task 13's 2-player test). Test players aren't the creator; whether Studio lets them buy (sandbox) and what `UserOwnsGamePassAsync` returns for them is checked then. If Roblox doesn't confirm, the Studio fallback turns the pass on with a warning, which shows the path ran.
  - **The Day-2 offer:** a test player, or your account with every pass forced off.
  - **Real phone:** unchanged (one real 9 R$ **product** purchase; products aren't "owned", so this works with your account).

### Plan change S (from task 6; confirmed by you on 2026-11-22)

- **S. A restricted player's coin-feeding receipt is granted and logged, not kept.** The purchase prompt opens on the client, so the server can't stop a purchase in advance; by the time a receipt arrives the Robux is taken, and an unresolved purchase is never refunded. If a receipt for a Coin Pouch, the Seed Bundle, the Starter Pack or the Luck Boost arrives for a player with `ArePaidRandomItemsRestricted`, it's granted and logged (an `Anomaly` custom event and a warning). The UI still hides those products, and the server still refuses everything it can refuse beforehand (Luck Boost ads, the Starter Pack and Double Coins offers). The products' external store page is off (`storePageEnabled` not set), so today such a receipt can only come from a modified client.

### Task 13 checks (2026-11-22, new session)

Rojo: the server from the last session (started 2026-11-21) still held port 34872 and served this project; three scripts matched their files byte for byte in Studio, so it was used as is.

**Step 1, Play Solo, your taps (Galaxy A06 in the Device Simulator):**

| Check | Result |
|---|---|
| Store from the HUD | **Passed.** Opens; prices in R$; the 5 passes show OWNED. |
| Small Coin Pouch (sandbox) | **Passed.** `granted CoinPouchS (ad=false)` once; coins +1,200 (the card said 1.2K); economy event logged. |
| Luck "📺 Free" | **Passed.** Test ad `ShowCompleted`; `granted LuckBoost (ad=true)` once through ProcessReceipt; the button turned to 🍀 + timer. |
| CrystalMenu → Finish now (sandbox) | **Passed.** `granted InstantGrowS (ad=false)` once; crystal finished. The prompt showed R$ 8 because Roblox applied its own 15 % test coupon; our button shows the list price R$ 9. |
| CrystalMenu → 📺 Finish free | **Passed.** `FinishNow -> ShowCompleted`, `granted InstantGrowS (ad=true)` once. |
| CrystalMenu → Use token | **Passed.** Hidden with 0 tokens (correct). A test receipt through `DebugProcessReceipt` with no pending target kept an S token (`Toast.TokenSaved`); "Use token (S)" then appeared and finished the crystal (`Toast.TokenUsed`). |
| Instant-grown and the board (change L) | **Passed.** A 4.08 ct instant-grown Citrine gave `newBest=false` with a weekly best of 2.0 ct. |
| Auto | **Passed.** Toggles (the server got every tap); a Quartz shattered by itself; left **off**. |
| VIP | **Passed.** "VIP" tag and trail while walking (the 👑 is only on board rows, as designed). |
| Emoji size on the 60 px buttons | **Passed** (readable, your check). |
| Offer popup | Not possible on your profile (day 2+, owns every pass): moved to steps 2 and 3. |

**Step 2, Starter Pack on a day-1 profile** (store `PlayerData_Test5`, reverted afterwards: `git status` clean, Studio reads `PlayerData`): tutorial steps 1–8 driven through the remotes, all logged in order. At the 10th shatter: `[Offer] shown StarterPack`, funnel step 1. The client held the popup because the **Daily panel** (opened at the end of the tutorial) stayed open, and dropped it after 30 s, as designed (change N). Resent from the server with the same kind once the screen was clear; you bought it (sandbox): `granted StarterPack` once (+1,000 coins, 3 Citrine), "OfferPurchased", funnel steps 3 and 2 (in that order, see T5).

**Step 3, local server with 2 players** (test players own no pass):

| Check | Result |
|---|---|
| A's `RequestInstantGrow` vs B's crystal | **Passed.** The remote only takes an index into the caller's own plot; A's calls for 1 (ready) and 3 (empty) returned nil; B's growing crystal on pedestal 1 kept its PlantedAt/ReadyAt. |
| `DebugPass_VIP` on A | **Passed.** `Pass_VIP = true`; B's client sees A's `VipTag` ("VIP") and `VipTrail`, both enabled. |
| Double Coins offer | **Passed (server).** Both test players got `[Offer] shown DoubleCoins` about 30 s after joining. On Player2 the popup was dropped: Daily (a new day for that profile) was still open 30 s after joining (T1). |
| Pass bought by a non-owner (sandbox) | **Passed.** Player2 bought Double Coins in the Store: `prompt closed … wasPurchased=true`, then "Studio test purchase … not confirmed by UserOwnsGamePassAsync; enabled for this session" (the change R fallback), `Pass_DoubleCoins = true`, funnel steps 2–3 and "OfferPurchased". |
| Restricted player | Not checked (no restricted test account). |

**Step 4, published DEV place and your phone** (test session ended first; you checked Version History; the profile's `MetaData.ActiveSession` named a live DEV server):

| Check | Result |
|---|---|
| No 📺 anywhere (change Q) | **Passed.** Luck shows 🍀 + R$ 25; the hint reads "Next free Surge in …"; no ad button in Daily, Store or CrystalMenu. |
| Store, Luck (prompt cancelled), Auto, CrystalMenu by touch | **Passed.** Auto left off. |
| Emoji, VIP tag and trail, plot-sign gold trim | **Passed** (your screenshot). |
| **Real 9 R$ purchase** (Instant Grow S) | **Passed: granted once.** Saved `ProcessedReceipts` went from 10 to 11 (one new ID, no duplicates); a rejoin granted nothing. The Citrine had become ready on its own while the prompt was open, so the server kept an **S token** instead of finishing it (the designed fallback; you then saw "Use token (S)"). |
| Sale in the Creator Dashboard | **Not checked yet** (you will look later; sales can take a while to show). |

**Step 5, review:** `MarketplaceService.ProcessReceipt` is assigned once ([ReceiptService.luau](../../roblox/src/server/Services/ReceiptService.luau), line 258). No price literals in client code; prices come from `PriceInRobux` (`GetProductInfoAsync`). `Rolls.size` has no paid input; `FinishNow` sets `ReadyAt = os.time()`, so overgrowth starts at zero; Fast Grow scales the growth phase only. Final: `lune run tests` **239 passed, 0 failed**; StyLua clean (Vendor skipped); `rojo build` succeeds; ProfileStore untouched.

**Findings from task 13 (none changes money handling; decide in batch 6):**
- **T1. Daily hides the session's one offer.** Daily opens by itself at the end of the tutorial (day 1) and on the first join of a day (day 2+); the offer waits only 30 s for a clear screen. A player who leaves Daily open misses the Starter Pack or Double Coins card for that session. Options: wait for Daily to close without the 30 s limit, or start the 30 s after Daily closes.
- **T2. The luck button says "📺 Free" with nothing about Luck** while an ad is available. Option: "📺 Free Luck" or 🍀 with an ad mark.
- **T3. Auto's only feedback is the button colour** (dark grey ↔ green); you reported "nothing happened". Option: "Auto ON / OFF" text and a toast.
- **T4. Finish now is offered with seconds left.** A crystal can finish during the prompt; the player keeps a token (nothing lost) but sees no visible change. Option: hide Finish now in the last ~10 s, or a clearer "Token saved" toast.
- **T5. Funnel step 2 can be logged after step 3:** "PromptOpened" is written when the prompt closes, and the receipt can arrive first. Each step is still logged once with the same funnel ID.

## Outcome (2026-11-22)

- **Built as specified**, with the confirmed changes G–S and the smaller decisions listed in "Resume here" and Progress.
- **Bugs found and fixed:** in tasks 5–12 (see Progress: review fixes in Store, the result card's note, the locked-pedestal shatter). Task 13 found no bug; findings T1–T5 are UX and analytics points for batch 6.
- **Who did what:**
  - **DeepSeek Flash:** tasks 3, 4, 8, 11 (3 jobs), 12 (4 jobs + 1 retry). Jobs that stopped on their token budget: 4 and 11B (nothing missing, no retry) and 12B (half done, retried with DeepSeek per your rule). Every recovery journal checked and acknowledged.
  - **Haiku:** task 10, accepted first time.
  - **Orchestrator:** tasks 0, 1, 5, 6, 7, 9, 13 and all wiring and review fixes. **You:** task 2 inputs, the taps, the sandbox and real purchases.
  - Nothing went to DeepSeek Pro.
- **Tests:** `lune run tests` **239 passed, 0 failed** (179 before + 60 new); StyLua clean; `rojo build` succeeds.
- **Each place checked:**

  | Where | What | Result |
  |---|---|---|
  | Lune | Receipts, InstantGrow, LuckBoost, AdCaps, Economy additions | Passed |
  | Studio Play Solo | Store, sandbox product purchases, test ads, CrystalMenu (3 options), tokens, Auto, VIP, board exclusion | Passed |
  | Studio, fresh day-1 profile | Tutorial → 10th shatter → Starter Pack offer → purchase, funnel | Passed (popup dropped while Daily was open: T1) |
  | Studio local server, 2 players | Cross-plot Instant Grow refused, VIP seen by the other player, Double Coins offer, non-owner pass purchase (change R fallback) | Passed |
  | Published DEV place, your phone | No 📺, touch on every new button, icons, VIP, one real 9 R$ purchase granted once and not again on rejoin | Passed |

- **Not verified:**
  - **A restricted player** (no test account); the checks are one line each in the code.
  - **The Creator Dashboard sale** of the real purchase (yours to check).
  - **The ad refusal during the tutorial** and **a 15-second save timeout on a receipt** (not reproducible on demand).
  - **The real purchase finishing a crystal on the phone:** it took the token fallback (T4); the finishing path was verified in Studio.
- **Open items (not fixed in this batch):** T1–T5 above; from tasks 11–12: Daily's ad button appears up to 1 s after the panel opens; with both boosts an Odds row reads "⚡ ×2 Luck ×2" while the percentages use the capped ×3; batch 4's "READY!" label behind the HUD's top row.
- **Leftovers:**
  - **Dev data:** your DEV profile has about 7.5K coins, **1 S token** (from the real purchase), today's ad counts partly used, `Settings.AutoShatter = false`. Store **`PlayerData_Test5`** holds a finished tutorial profile with the Starter Pack bought; the next fresh-profile test needs `PlayerData_Test6`. Test profiles `Player_-1` / `Player_-2` used again (`Player_-2`'s Double Coins was a Studio session-only grant).
  - **The DEV experience is published with batch 5.** Pass and product IDs exist only for DEV (`IdsByGameId`); the live experience gets its own at launch (batch 6).
  - **MCP permissions:** `game-pass:write` and `developer-product:write` can go off until icons are added; the `uploads/` folder stays approved.
  - **Still running:** the Rojo server on port 34872 (started 2026-11-21). The Device Simulator is on the Galaxy A06.
- **Lessons:**
  - **A popup that waits for a clear screen must account for panels that open by themselves** (Daily); test the offer with the real join flow, not only with scripted shatters.
  - **Roblox's "Purchase completed" dialog names the product for both grant paths;** to know which path ran, read the server log or the saved profile.
  - **A stale Rojo server from an earlier session can still serve the right project;** compare a script's `#Source` with the file size before trusting it.

