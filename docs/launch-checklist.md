# Crystal Grove launch checklist

The game goes public only when every row below is ✅. Each ✅ names its evidence. The full details are in the batch records, mostly [batch 6](decisions/2026-11-18-batch-6-polish-and-launch.md).

Built from the MVP's "Acceptance criteria for launch", batch 6's acceptance criteria and launch steps, and Step 5's thumbnail rules. Last updated 2026-11-25 (batch 6, task 7).

**Status:** ✅ passed (evidence given) · ⏳ not checked yet (the task that checks it) · ❌ failed (blocks launch)

## 1. Acceptance criteria

| # | Criterion | Status | Evidence, or where it gets checked |
|---|---|---|---|
| 1 | **Core loop:** a new player finishes the tutorial in 75 s or less **on a phone**, without instructions | ⏳ task 10 | Device Simulator: 64.2 s (about 69 s with reading time), batch 4. The real-phone run was skipped in batch 4, so the phone playtest checks it. |
| 2a | **Saving:** coins, seeds, pedestals, codex, streak and growing crystals survive a **rejoin** | ✅ DEV | Rejoin mid-tutorial (batch 4); ad counts and receipts kept across a rejoin (batch 5). Repeated in the live playtest. |
| 2b | **Saving:** the same survives a **server shutdown** (`BindToClose`) | ⏳ task 10 | The `BindToClose` flush wasn't observed in Studio (batch 3). |
| 2c | **Saving:** joining a second server while the first is still saving loses or duplicates nothing (phone plus PC) | ✅ DEV | Batch 2 session-lock test: PC, then phone on the same account; `Sessions` went up by exactly 1 each time and the crystals stayed. Repeated in the live playtest. |
| 3 | **Offline growth:** a crystal planted before leaving is ready on return after its grow time | ⏳ task 10 | The design stores `ReadyAt` in server time. Not yet checked by leaving for longer than a grow time. |
| 4 | **Fairness:** no pass or product touches `SizeRoll` or overgrowth; instant-grown crystals never reach the leaderboard | ✅ | Code search, task 7: `SizeRoll` is set only at planting, by `Rolls.size` (unpaid); no monetization file refers to `SizeRoll`, overgrowth or `Rolls`. Fast Grow and instant grow change only `ReadyAt`. Carats = `BaseCarats × SizeRoll × (1 + overgrowth)`, so Luck Boost (mutations) and Double Coins can't change carats. Instant-grown crystals skip the weekly best, and `LeaderboardService:Submit` refuses them. |
| 5 | **Security:** the 60 s fuzz run changes no data and causes no server error from our code; every row of the review table passes | ✅ | Task 4: 2 runs, 0 profile fields changed, 0 warnings, 0 errors, 0 handler failures; all 13 remotes pass. |
| 6 | **Leaderboard:** a new weekly best appears on the hub board within 2 minutes, in the correct week's store | ✅ DEV | Batch 3: shown on the board 32 s after the shatter. The week key is unit-tested (`WeekId.spec`). Repeated in the live playtest. |
| 7 | **Performance:** at least 30 FPS on a real mid-range phone with 6 full caves (stress mode) | ⏳ task 10 | Batch 2: 57–60 FPS with 78 crystals on your phone, **before** the batch 6 polish. Measured again on DEV (stress mode is off in live). |
| 8a | **Monetization:** all 5 passes and 10 products exist in the **live** experience, with live IDs in `IdsByGameId` | ⏳ task 9 | DEV has them all (batch 5). |
| 8b | **Monetization:** a real 9 R$ purchase works in live | ⏳ task 10 | On DEV it was granted once and not again on rejoin (batch 5). |
| 8c | **Monetization:** ad buttons are hidden while ads aren't available | ✅ DEV | Batch 5, your phone: no 📺 buttons. Seen again in the live playtest. |
| 9 | **Analytics:** the onboarding funnel (8 steps), economy events and custom events are visible in the dashboard from a test session; session length on the Engagement page (plan change L) | ⏳ task 6 | Sessions on published DEV v88, 2026-11-25; dashboard due around 14:15 UTC on 2026-11-26. |
| 10a | **Content:** no copyrighted names or assets | ✅ | Task 7: no other game or brand names in `roblox/src`; procedural art only; the only external assets are the 7 sounds. |
| 10b | **Content:** all audio is licensed from Roblox or made by you | ✅ | All 7 sound IDs are Creator Store assets whose creator is exactly "Roblox" (batch 4, task 2). |
| 10c | **Content:** the content ratings questionnaire is complete | ⏳ task 9 | — |
| 10d | **Content:** odds in the thumbnails and description are true (derived from `Config.Rolls`) | ⏳ task 8 | Thumbnail B's "1 in 333,000" comes from the MVP amendment. |
| 10e | **Content:** no personal data in the repo | ✅ | Task 7 scan of all 132 tracked and untracked files: no email, name, account ID, username, local user path or key. Repeated before the final commit. |
| 10f | **Content:** no personal data in the store listing | ⏳ task 8 | — |
| 11a | **Dev features off in live (code):** stress mode, the seed top-up and the admin command | ✅ | Stress mode only in Studio or `GameId == DevUniverseId` (`CrystalRenderer`); top-up only in Studio (`CrystalService.studioTopUp`); `/cg` created only in Studio or DEV, owner only (`AdminCommands.existsHere` / `isAllowed`, 12 tests). |
| 11b | **Dev features off in live (tried):** each one tried in the published live build | ⏳ task 10 | — |
| 12 | **Tests:** `lune run tests` passes, StyLua is clean, the build succeeds | ✅ | 2026-11-25: 289 passed, 0 failed; StyLua clean; `rojo build` succeeds. Run again in task 11. |
| 13 | **Batch 5 open item:** the real purchase shows as a sale in the Creator Dashboard | ⏳ task 6 | Checked in the same dashboard visit as row 9. |

## 2. Launch steps (live experience)

Plan change K (launch audience) is **pending**. Steps 4, 8 and 9 follow it once you confirm it before task 9.

| # | Step | Who | Status |
|---|---|---|---|
| 1 | Create the live experience **"Crystal Grove 💎"** (Studio: File → Publish As → Create new experience), separate from DEV. **Studio API access stays off** for live. | You | ⏳ task 9 |
| 2 | **Server size 6** (Open Cloud `serverSize`, or the Dashboard). DEV is 50; live must be 6. | Orchestrator or you | ⏳ task 9 |
| 3 | **Genre and description** from `docs/store-listing.md`: no promotional claims, true odds. | You (text from task 8) | ⏳ task 8–9 |
| 4 | **Content ratings questionnaire:** Creator Dashboard → the game → Publish settings → Content ratings → Get a rating. Name, description and genre must be saved first; the rating takes 15–60 min. | You | ⏳ task 9 |
| 5 | **5 passes and 10 products in live**, created through Open Cloud (change I): same names and prices, free trials off; live IDs in `IdsByGameId`. Then **opt the 15 items out of Managed Pricing** until week 2 (Monetization → Managed Pricing). | Orchestrator, then you | ⏳ task 9 |
| 6 | **Icon and thumbnails** (rules below) uploaded; 2 or more active thumbnails turn personalization on. | You | ⏳ task 8–9 |
| 7 | **Publish:** `rojo build -o CrystalGrove.rbxlx`, open it in Studio, File → Publish to the live experience. The template Baseplate and SpawnLocation must be absent. | You, guided | ⏳ task 9 |
| 8 | **Phone playtest:** 2–3 people, 15 minutes, using section 1. With change K, testers can join through the "invite up to 10 friends" preview. | You + testers | ⏳ task 10 |
| 9 | **Release:** only when section 1 is all ✅. Under change K: age-checked 16+ first; all ages after Roblox's evaluation (100 engaged 16+ plays within 60 days, with ID verification, 2FA, the full questionnaire and the refundable fee). | **You** | ⏳ after task 11 |

## 3. Thumbnail and icon rules (Step 5)

- **Thumbnails A, B and D at launch:** A "COLOSSAL!" (a small avatar under a giant rainbow crystal), B "1 in 333,000" (a cracking Prismatic crystal), D "SHATTER = 💰" (mid-explosion). C and E are kept for later tests.
- 16:9, 1920 × 1080, each under 3 MB; real in-game scenes only; at most 3 words; nothing important in the bottom strip; odds must be true.
- **Icon:** 512 × 512, a Prismatic crystal on dark purple, no text; check it at 150 × 150.
- **Pass and product icons** (change J): you make them in task 8, or launch with the defaults.
