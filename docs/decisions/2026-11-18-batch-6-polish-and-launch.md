# Specification: Batch 6, polish, analytics audit, anti-exploit hardening, admin command, launch

Status: approved 2026-11-18; plan changes A–J (from batch 5's findings and earlier records) confirmed by you on 2026-11-24. **In progress** on `batch-6-polish-launch`: tasks 0–1 done; plan change K pending (before task 9); see **Progress** and **Findings**.

## Context

After batch 5 ([record](2026-11-18-batch-5-monetization.md)), the game is complete: the loop, progression, UI, tutorial and monetization all work in the **dev** experience. This last batch makes it **feel good, safe and measurable**, then **publishes it** to a new **live** experience:
- **Polish:** juice, lighting, cave decoration, and the performance settings from the batch 2 proof.
- **Analytics audit:** every event from the MVP and monetization specs, verified in the Creator Dashboard.
- **Anti-exploit review:** a fuzz test of every remote.
- **Admin command:** a dev-only command so you can test quickly.
- **Launch checklist:** built from the MVP's "Acceptance criteria for launch" and Step 5's thumbnails.

It follows the architecture build-order item 12. The 14-day launch and iteration plan (Step 8) is a separate document written after this batch, and it isn't code.

### Context for a new session (read before task 1)

1. [README.md](README.md): **Starting a new session** and **Delegation lessons**.
2. This record.
3. The [MVP spec](2026-11-18-crystal-grove-mvp.md): "Acceptance criteria for launch", "Analytics events and success metrics", "Sound and visual style", "Map and layout" (the performance budget), and the Amendment on truthful odds.
4. The [monetization spec](2026-11-18-crystal-grove-monetization.md): "Guardrails", the analytics events, and the "Price and offer testing after launch" week-1 rule.
5. The [architecture spec](2026-11-18-crystal-grove-architecture.md): "Remote security rules", "Anti-exploit considerations", "Analytics events".
6. **All earlier batch records:** especially the batch 2 **performance-proof findings** (the FPS numbers and which fallbacks were needed), and every Outcome's **Not verified** and **Leftovers** lists. Close them here or carry them over explicitly.
7. **Step 5 (thumbnails and ads)** lives in the conversation, not a record. The thumbnail concepts are: **A** "COLOSSAL!" (a small avatar under a giant rainbow crystal), **B** "1 in 333,000" (a cracking Prismatic crystal), **C** "MY CRYSTAL CAVE", **D** "SHATTER = 💰" (mid-explosion), **E** "BIGGEST CRYSTAL WINS". Launch with **A, B, D**. Rules:
   - 16:9, 1920 × 1080;
   - nothing important in the bottom strip;
   - at most 3 words;
   - real in-game scenes only;
   - odds must be true.

   The icon is a 512 × 512 Prismatic crystal on dark purple, with no text.
8. **Code:** the whole `roblox/src` tree. This batch reviews all of it.
9. **Starting state:** the batch 5 branch is committed; tests pass. Create `batch-6-polish-launch`.

### Outside facts

To check in official docs in task 1, recording the URL and date:
- `TextChatService` + `TextChatCommand` (`PrimaryAlias`, `Triggered`): on which side does `Triggered` fire, and can the server create commands?
- `Lighting` effects: `Atmosphere`, `ColorCorrectionEffect`, `BloomEffect`.
- The Creator Dashboard steps for: **Maturity & Compliance Questionnaire**; **server size** (Places → Server Size); **experience thumbnails** (Configurations → Places → Thumbnails → Home Page tab, 2–5 active for personalization); **Managed Pricing** (default enrollment); **Rewarded Video** (Monetization → Ads, which shows eligibility).
- Analytics: how long until custom, economy and funnel events appear in the dashboard.

## Behaviour

### Polish (what players notice)
- **Coins fly from the shattered crystal to the HUD counter:** 6–12 coin icons over 0.5 s, and the counter ticks up as they arrive.
- **Shatter feel:**
  - shards come in the crystal's colour, with a mutation tint;
  - Huge crystals shake the camera for 0.2 s, Colossal for 0.4 s;
  - a short white flash for Prismatic.
- **Ready crystals:** a soft pulsing glow ring on the pedestal.
- **Lighting:**
  - **Atmosphere:** density 0.35, a blue-purple tint.
  - **ColorCorrection:** saturation +0.1, contrast +0.05.
  - **Bloom:** intensity 0.8, size 24, threshold 1.1.
  - ClockTime and the ambient colours are tuned so that crystals are the main light, while the UI stays readable.
- **Cave decoration, built by code:**
  - 8–12 rock stalagmites per cave, using **seeded positions** so every server looks the same;
  - 3 small decorative crystal clusters on each cave's walls (Neon only, no lights);
  - a glowing path from the hub to each cave mouth.
- **Graphics quality:** `Config/Graphics.luau` holds the fallbacks the batch 2 proof showed were needed:
  - `LightsMinTier`;
  - `ParticleRate` multiplier;
  - `GlassShell` on/off.

  These also lower themselves automatically when the player's graphics quality setting is low.

### Admin command (development only)
- **Who can use it:** only in **Studio**, or in the **dev experience** for the experience's owner (`game.CreatorType == Enum.CreatorType.User` and `player.UserId == game.CreatorId`). **It never works in the live experience**, which is checked against `IdsByGameId` (the live `GameId`).
- **Chat commands** (`/cg …`), each replying with a system message:

  | Command | Effect |
  |---|---|
  | `/cg coins <n>` | Set your coins to n |
  | `/cg seeds <seedId> <n>` | Add n seeds |
  | `/cg ready` | Make all your growing crystals ready |
  | `/cg tutorial reset` | `Tutorial = {Step = 0, Done = false}` |
  | `/cg daily reset` | Clear the streak and goal dates so you can claim again |
  | `/cg tier <n>` | Set your highest unlocked tier |
  | `/cg wipe` | Reset your profile to the template |

- **Logging:** every admin action logs a `LogCustomEvent("Admin", …)` and prints to the Output.

### Anti-exploit hardening
- **A fuzz script** (`roblox/dev/FuzzClient.client.luau`, **outside the Rojo project tree**, so it is never synced or published) is pasted into a Studio client for testing. For 60 s it fires every ToServer remote with random junk: wrong types, NaN, huge numbers, other players' pedestals, nil, tables and long strings.
  - **Expected:** no server errors from our code, no data change (the coins and seed counts are compared before and after), and the server keeps running.
- **A review checklist** (task 4) is applied to every handler and recorded as a findings table, one row per remote:
  - the remote validates its arguments;
  - it acts only on the caller's own data or plot;
  - it never uses client-sent amounts;
  - it grants only after checks;
  - it can't pay twice.
- **Rate-limit tuning:** the per-remote `Rate`/`Burst` values are adjusted if the fuzz or play tests show honest players being rejected.

### Analytics audit
- **Event table:** every event from the MVP and monetization specs, with the file and line that logs it; a dashboard screenshot proves each one arrived.
- **Limits:** at most 10 funnels (we use 2: onboarding and FirstPurchase), at most 5 currency types (we use 1: "Coins"), at most 20 transaction types, at most 100 SKUs.
- **`SessionEnd`** (minutes played) is logged on `PlayerRemoving`.

### Launch (live experience)
1. **Create the live experience "Crystal Grove 💎"** (Studio: File → Publish As → Create new experience), separate from DEV. **Studio API access stays OFF** for live.
2. **Server size 6.**
3. **Genre and description.** The description is written in task 8, with no promotional claims and true odds.
4. **Maturity & Compliance Questionnaire** completed. It is also required later for rewarded ads.
5. **Create the 5 passes and 10 products in the live experience** (same names and prices as the monetization spec, free trials off), and put the live IDs in `IdsByGameId`.
6. **Icon** (512 × 512) and thumbnails **A, B, D** (1920 × 1080) made from real in-game Studio screenshots; thumbnail personalization turned on with those 3.
7. **Publish:** run `rojo build -o CrystalGrove.rbxlx`, open the file in Studio, then File → Publish to the live experience. The template Baseplate and SpawnLocation must be absent.
8. **Playtest on phones:** 2–3 people for 15 minutes, using the launch acceptance list below.
9. **Make it public** only after every launch acceptance criterion passes. **You do this step yourself.**

## Not included

- **The Step 8 launch and iteration plan:** a separate document after this batch.
- **Paid ads** (Roblox sponsored campaigns, TikTok, Shorts): started only after D1 retention is at least 10%, per Step 5.
- **Rewarded ads going live:** automatic once Roblox marks the experience eligible (about 2,000 monthly visitors). No code is needed.
- **New content** (more seeds, events, leaderboard prizes): v1.1, decided by data.
- **Translations.**

## Design

**Stored data:** no schema change. The `/cg wipe` command resets *your* profile to the template in the **dev** experience only.

### Files

| File (under `roblox/` unless rooted) | Change | Task |
|---|---|---|
| `src/shared/Config/Graphics.luau` | New | 2 |
| `src/client/Controllers/EffectsController.luau`, `CrystalRenderer.luau`, `UI/Screens/Hud.luau` | Coin fly, shake tuning, glow ring, graphics config | 2 |
| `src/server/Services/MapService.luau` | Lighting values, cave decoration, hub paths | 3 |
| `dev/FuzzClient.client.luau` | New, **not in `default.project.json`** | 4 |
| `src/server/Services/*` | Hardening fixes found by the review | 4 |
| `src/server/Services/AdminService.luau` | New | 5 |
| `src/server/Services/Analytics.luau` and callers | `SessionEnd`, and gaps found by the audit | 6 |
| `docs/launch-checklist.md` | New: the checklist with ✅ / ❌ and evidence for each item | 7 |
| `docs/store-listing.md` | New: title, description and genre text (no personal data) | 8 |

## Task breakdown and model assignment

| # | Task | Model | Why this model | Depends on |
|---|---|---|---|---|
| 0 | Branch and save the record status | Orchestrator | — | — |
| 1 | **Proof:** check the "Outside facts" items; read the batch 2 performance findings and set the `Graphics` defaults from them | Orchestrator | Judgment | 0 |
| 2 | Polish: Graphics config, coin fly, shake, glow ring | DeepSeek Flash (2 jobs: Effects + Hud; Renderer + Graphics) | Visual code | 1 |
| 2b | **Batch 5 follow-ups** (changes A–D) and small open items: offer wait (A), "📺 Free Luck" (B), Auto ON/OFF + toast (C), Finish now hidden at ≤ 10 s (D), Daily/Goals dots during the tutorial, the Odds row's capped total, Daily's ad button refresh on open | Orchestrator (A) + Haiku (the rest) | A is guardrail code; the rest is small and fully specified | 1 |
| 3 | Lighting (in `Config/Lighting`, change F) and cave decoration in MapService | DeepSeek Flash | Geometry code | 1 |
| 4 | Fuzz script; a per-remote review table; hardening fixes | Orchestrator (the fuzz script can go to DeepSeek Flash) | Security review stays with the orchestrator | 1 |
| 5 | `AdminService` | Orchestrator | Changes data; permission checks | 1 |
| 6 | Analytics audit and fixes | Orchestrator | Cross-file judgment | 2–5 |
| 7 | `docs/launch-checklist.md` | Orchestrator | — | 6 |
| 8 | Store listing text; the thumbnails and icon from in-game screenshots | Orchestrator (text) + you (images) | You own the art and the account | 3 |
| 9 | Live experience setup (launch steps 1–6) | You, guided step by step | Your account | 7, 8 |
| 10 | Phone playtest (launch step 8); fix blockers | You + orchestrator | — | 9 |
| 11 | Final review, tests, outcome; you decide to make it public | Orchestrator + you | — | 10 |

Escalation: as in earlier batches. **If the playtest finds a blocker**, fix it in this batch as an amendment, and publish only when the checklist is all ✅.

### Acceptance criteria (the launch checklist; every item needs evidence)

- **Core loop:** a new player finishes the tutorial in 75 s or less on a phone without instructions.
- **Saving:**
  - coins, seeds, pedestals, codex, streak and growing crystals survive a rejoin and a server shutdown;
  - joining a second server while the first is saving loses or duplicates nothing (phone plus PC test).
- **Offline growth:** a crystal planted before leaving is ready on return after its grow time.
- **Fairness:** a code search confirms that no pass or product touches `SizeRoll` or overgrowth, and that instant-grown crystals never reach the leaderboard.
- **Security:** the 60-second fuzz run causes no data change and no server error from our code; every row of the review table passes.
- **Leaderboard:** a new weekly best appears on the hub board within 2 minutes, in the correct week's store.
- **Performance:** at least 30 FPS on a real mid-range phone with 6 full caves (stress mode).
- **Monetization:** all 5 passes and 10 products exist in the **live** experience and pass a real 9 R$ purchase test; ad buttons are hidden while ads are unavailable.
- **Analytics:** the onboarding funnel (8 steps), economy events and the custom events are visible in the dashboard from a test session.
- **Content:**
  - no copyrighted names or assets; all audio is licensed from Roblox or made by you;
  - the maturity questionnaire is complete;
  - the thumbnail and description odds are true;
  - **no personal data in the repo or the store listing.**
- **Dev features off in live:** stress mode, the seed top-up and the admin command don't work in the live experience. Each is checked by trying it in the published live build before going public.
- **Tests:** `lune run tests` passes, StyLua is clean, and the build succeeds.

## Verification

- **Automated tests:** all earlier specs, plus `Graphics.spec` (the config shape) and `Admin.spec` (pure command parsing, if parsing is split into `Logic/AdminCommands.luau`).
- **Backup first:** before `/cg wipe` is ever used, note that it affects only the dev profile. The live experience starts with no data.
- **Studio:** polish checks by eye; the fuzz run; admin commands in Studio.
- **Device emulator:** the UI after the polish (coin fly over the HUD on iPhone SE).
- **Real phones (live experience, still private):** the full checklist with 2–3 people.

## Decisions (confirmed by the user 2026-11-18, recommended options chosen)

1. **The admin command is disabled in the live experience entirely.** Rejected: owner-only admin in live, which is useful for support but is a risk if the check is ever wrong.
2. **The fuzz script lives outside the Rojo project** (`roblox/dev/`), so it can never ship. Rejected: an in-game Studio-only toggle, which is easier to run but is code that ships.
3. **You flip the game to Public yourself,** after the checklist is all ✅. Rejected: going public as part of the batch.

## Progress (2026-11-24)

- **Task 0 done:** branch `batch-6-polish-launch` created from `batch-5-monetization` (`22d05b5`; same tree as `batch-1-setup` after PR #5, merge `5ac6d47`). The batch 5 record's status line (PR #5 merged) is committed here. Starting state: `lune run tests` **239 passed, 0 failed**. The Rojo server from 2026-11-21 still listens on port 34872; a script's `#Source` is compared with its file size before a Studio check is trusted.

### Plan changes A–J (confirmed by you on 2026-11-24)

From batch 5's task 13 findings (T1–T5) and the earlier records' open items. This plan was approved before those findings.

| | Source | Change | Task |
|---|---|---|---|
| A | T1 | **The session's offer waits for a clear screen with no time limit:** shown once nothing (no panel, no result card, tutorial done) has been on screen for **3 s**; dropped only if the player leaves. Still one per session, never during the tutorial or a result. No new remote: `OfferShown` stays logged when the server sends the card, so the Starter Pack take rate slightly overcounts only for players who leave before the screen clears. Rejected: starting the 30 s after Daily closes (any other panel can still drop the offer). | 2b |
| B | T2 | The Luck slot's ad button reads **"📺 Free Luck"** (`Ad.FreeLuck`); checked to fit the 60 px button in the Device Simulator. | 2b |
| C | T3 | The Auto button reads **"Auto ON" / "Auto OFF"**, with a toast on each change. | 2b |
| D | T4 | **"Finish now" and "📺 Finish free" are hidden at 10 s or less left** (client only; the server's token fallback is unchanged). | 2b |
| E | T5 | `OfferService.notePurchased` logs funnel step 2 first if it hasn't been logged, so the steps arrive in order. | 6 |
| F | Cave-brightness record | **Lighting values live in `Config/Lighting.luau`:** Atmosphere, ColorCorrection and Bloom as one shared effects table, ambient and `ClockTime` tuned in the 3 presets; `MapService` applies them and keeps the surface colours and decoration. All 3 brightness levels are re-checked. | 3 |
| G | Batch 2 proof | **`Graphics` defaults are full quality** (the phone proof gave 57–60 FPS with 78 crystals, no fallback needed); automatic lowering at a low graphics setting stays. Stress FPS on the phone is measured again after the polish. | 1, 2, 10 |
| H | Decision 1 | **The admin command uses an allowlist:** Studio, or `game.GameId == GameConfig.DevUniverseId` and the caller is the owner. Stricter than "not the live `GameId`", and it works before a live ID exists. | 5 |
| I | Batch 5 task 2 | **The live passes and products are created by the orchestrator through Open Cloud** (as for DEV), not by hand. Needs the live universe ID and the `game-pass:write` / `developer-product:write` permissions on again. | 9 |
| J | Batch 5 "Not included" | **The pass and product icons were never made** (`uploads/icons/` is empty). Decided in task 8: you make them, or launch with the defaults. | 8 |

### Open items from earlier batches

**Closed in this batch (planned):**

| Item | From | Where |
|---|---|---|
| "READY!" label and tutorial bubble behind the HUD's top row | Batch 4 | Task 2 (renderer job) |
| Daily and Goals dots visible on locked buttons during the tutorial | Batch 4 | 2b |
| Tutorial on a real phone | Batch 4 | 10 |
| Odds row "⚡ ×2 Luck ×2" while the odds use the ×3 cap → show the capped total | Batch 5 | 2b |
| Daily's ad button up to 1 s late → refresh when the panel opens | Batch 5 | 2b |
| Ad refusal during the tutorial | Batch 5 | 5 (`/cg tutorial reset`, Studio test ads) |
| Creator Dashboard sale of the real purchase | Batch 5 | 6 |
| A real purchase that finishes a crystal (not the token fallback) | Batch 5 | 10 (live 9 R$ test, crystal with ≥ 1 min left) |
| `BindToClose` flush; saving through a server shutdown | Batch 3 | 10 |
| `Toast.MaxLevel` | Batch 3 | 5 (via `/cg coins`) |
| Friend bonus above 0 | Batch 3 | 10, if two playtesters are friends |
| "+N" label seen on screen | Batch 2 | 2 (by eye, with the coin fly) |
| `StudsOffsetWorldSpace` axes in the official docs | Batch 2 | 1 |

**Carried over:** a restricted player (no test account); a 15-second receipt save timeout; the Crystal Surge in play; a real Molten or Prismatic announcement; the Codex completion bonus in play. **Closed as by design:** "1.2K" hiding small coin changes (`Format.compact`; the coin fly's tick-up shows the change).

- **Task 1 done (2026-11-24, orchestrator):** the outside facts are checked (Findings → Task 1) and the `Graphics` defaults are set (Findings → Graphics defaults). Two findings change later steps: the Atmosphere replaces today's fog (task 3), and the release rules give **plan change K** (pending, to confirm before task 9). No code changed.
- **Tasks 2 and 2b: code done (2026-11-24); checks by eye still open.**
  - **Change A (orchestrator):** [UIController.luau](../../roblox/src/client/Controllers/UIController.luau): the offer waits until the screen has been clear (tutorial done, no panel, no result card) for 3 s in a row, with no time limit. One wait runs at a time; a newer card replaces it.
  - **Task 2, job 1 (DeepSeek Flash; stopped on its token budget with every file written, so no retry):**
    - New pure [Logic/CoinFly.luau](../../roblox/src/shared/Logic/CoinFly.luau) (`iconCount`: 6–12 icons by coin amount; `split`: whole shares that sum exactly) with `CoinFly.spec` (9 tests).
    - [Hud.luau](../../roblox/src/client/UI/Screens/Hud.luau): `CoinTarget`, `HoldCoins`, `ReleaseCoins`. The counter holds back flying coins and ticks up as each icon lands, with a small pop. A hold releases itself after 1.6 s, so the counter can't get stuck.
    - [EffectsController.luau](../../roblox/src/client/Controllers/EffectsController.luau): coin fly (icons from the crystal's screen point to the coin pill over 0.5 s); shake Huge 0.2 s and Colossal 0.4 s; shards tinted by mutation (Glowing lighter, Molten orange, Prismatic a rainbow); a white flash for Prismatic.
  - **Task 2, job 2 (DeepSeek Flash; stopped on its budget with 3 hooks missing; a DeepSeek retry added them):**
    - New [Config/Graphics.luau](../../roblox/src/shared/Config/Graphics.luau) (change G's two profiles; `profileName`, `profile`) with `Graphics.spec` (6 tests).
    - `CrystalBuilder.build(..., withShell?)`.
    - `CrystalVisuals.applyMutation(..., profile)`: lights and particle rates follow the profile.
    - `CrystalVisuals.makeReadyRing` / `pulseRing`.
    - [CrystalRenderer.luau](../../roblox/src/client/Controllers/CrystalRenderer.luau): reads `SavedQualityLevel` and restyles on change; a pulsing glow ring on ripe crystals; own-plot labels that would land in the HUD's top 130 px drop to just above the pedestal, 3 studs toward the camera, and climb back only below 160 px.
  - **Task 2b (Haiku, accepted first time):**
    - Hud: "📺 Free Luck" (B); Auto reads "Auto ON / OFF" and toasts on each change (C); no red dots before the tutorial is done.
    - CrystalMenu: Finish now and 📺 Finish free hidden at 10 s or less (D).
    - Odds: both boosts read "⚡+Luck ×3 (max)".
    - Daily: the panel is visible before its first refresh, so the ad probe runs at once.
    - 4 new strings.
  - **Review:** every DeepSeek recovery journal was checked and acknowledged. The full-screen fly layer doesn't block world taps (TapController uses `gameProcessed`; the layer isn't `Active`). Tests **254 passed, 0 failed** (239 + 9 CoinFly + 6 Graphics); StyLua clean; `rojo build` succeeds.
  - **Studio, first check (Play Solo, your DEV profile; the old Rojo server synced every changed script, byte for byte):**
    - No errors from our code.
    - `[Graphics] profile=Low`: Studio's own graphics level is 1–3 here, so Studio shows the Low profile.
    - Ripe pedestals 1 and 2 had a `ReadyRing`.
    - Shattering pedestal 1 flew 8 icons, all gone by 1.75 s; the counter went 8.3K → 8.4K.
    - A second shatter: the first icon started at (253, 92) against the crystal's screen point (256, 94) and flew to the coin pill's centre (352, 28), in the same coordinate space.
    - The Daily panel opened by itself (a new day), the T1 situation.
  - **Studio, checks by eye (Play Solo, Device Simulator iPhone 7, 2026-11-24; your taps, Fast Grow forced off with `DebugPass_FastGrow` so a Quartz grows for 20 s):**

    | Check | Result |
    |---|---|
    | Finish now shown with more than 10 s left, hidden in the last 10 s (D) | **Passed** (your check). A 📺 Finish free test ad also completed earlier in the growth: `granted InstantGrowS (ad=true)` once. |
    | Glow ring on a ripe crystal | **Passed** (your check). |
    | Coin fly: icons to the counter, tick-up and pop, the "+N" label, shard colour | **Passed** (your check), on 3 real shatters (+44, +54, +36). This also closes batch 2's "+N label seen on screen". |
    | "📺 Free Luck" fits its button (B) | **Passed** (your check). A Luck test ad was granted once through ProcessReceipt. |
    | Auto: "Auto ON / OFF" and a toast on each tap (C) | **Passed** (your check); left **off** (the HUD reads "Auto OFF"). |
    | Own-plot label drops below the HUD near the top of the screen (batch 4 open item) | **Passed** (your check). |
    | 0.4 s shake, white flash, rainbow shards (a fake Colossal Prismatic `ShatterResult` sent from the server command bar, display only, no coins) | **Passed** (your check). |
    | Graphics profile follows Studio's graphics level | **Passed:** `[Graphics] profile=Low` at start, then `profile=Full` when the level changed during the session. |

  - **Change A, Studio local server with 2 test players (2026-11-24, test profiles `Player_-1` / `Player_-2`, which own no pass):** both got `[Offer] shown DoubleCoins` while the Daily panel (a new day for them) was open. At 50 s or more after the send, Player1's popup was still waiting, not dropped. You closed Daily in Player1's window and the Double Coins card was showing at the next check (21:58:09 UTC, more than 70 s after the send). Player2, with Daily still open, kept waiting with no popup. **Passed: T1 is fixed.**

  - **Device Simulator, Galaxy A16 (viewport 685 × 338; Play Solo, your DEV profile, Fast Grow forced off, 2026-11-24):** Finish now shown, then hidden in the last 10 s; glow ring; coin fly on a real shatter (+39); the Luck and "Auto ON / OFF" texts fit; the top-of-screen label drops below the HUD; the fake Colossal Prismatic (sent twice: the first time pedestal 1 was out of view) shook, flashed and burst in rainbow shards. **All passed** (your checks). Auto left off ("Auto OFF"). The client log shows both fake results and no errors from our code.

    **Still open from tasks 2 and 2b:** the tutorial's world bubble near the HUD (its own placement code wasn't changed); the Odds row with both boosts (needs a Surge window, :00–:04 UTC, while a Luck Boost runs).

## Findings

### Task 1: outside facts (checked 2026-11-24)

Pages read through the Studio MCP doc fetcher; each showed `last_updated: 2026-11-24`.

| Fact | Official page | What it says | Effect on this plan |
|---|---|---|---|
| `TextChatCommand.Triggered` | [TextChatCommand](https://create.roblox.com/docs/reference/engine/classes/TextChatCommand.md) | `Triggered(originTextSource, unfilteredText)` fires **on the sending client and the server**, not on other clients. Matching is case-insensitive; with the default `StartsWith` mode the alias must be followed by a space or the end ("/cg coins 5" matches "/cg"). With `DeliverMessage = false` the message isn't sent to others and `unfilteredText` is the whole message. `AutocompleteVisible` hides the command from suggestions. | As planned: `AdminService` creates one `TextChatCommand` (`PrimaryAlias = "/cg"`, `AutocompleteVisible = false`) under `TextChatService` on the server **only when the gate passes**, handles `Triggered` on the server, and reads the caller from `originTextSource.UserId`. Checked in Studio in task 5. |
| `Atmosphere` | [Atmosphere](https://create.roblox.com/docs/reference/engine/classes/Atmosphere.md) | "**Fog properties are hidden when Lighting contains an Atmosphere object.**" `Density` sets how much in-game objects are obscured. | **Today's `FogEnd = 600` / `FogColor` stop working** once the Atmosphere is added. The Atmosphere replaces the fog: change F's effects table holds its values, and `MapService` stops setting fog. |
| `BloomEffect` | [BloomEffect](https://create.roblox.com/docs/reference/engine/classes/BloomEffect.md) | `Intensity`, `Size` (pixels), `Threshold`: "If set to 1, only pure white colors will bloom. If set to 0, all colors will bloom." Renders differently by quality level. | Today's bloom is 0.8 / 24 / **0.85**; the plan says threshold **1.1**. Task 3 starts from 1.1 and keeps it only if Neon crystals still glow by eye; otherwise 0.85 stays (recorded either way). |
| `ColorCorrectionEffect` | [ColorCorrectionEffect](https://create.roblox.com/docs/reference/engine/classes/ColorCorrectionEffect.md) | `Saturation` above 0 is more vivid, −1 is grey; `Contrast` above 0 is more contrast. | As planned (+0.1, +0.05). |
| `BillboardGui.StudsOffsetWorldSpace` (batch 2 open item) | [BillboardGui](https://create.roblox.com/docs/reference/engine/classes/BillboardGui.md) | "offset from its Adornee in studs, relative to the **global axes**." | **The docs disagree with batch 2's measurement** (the label moved along the rolled pedestal's own Y axis). The code follows the measurement, which works on screen; no change. Open item closed as "checked; the docs differ from observed behaviour". |
| Graphics quality | [UserGameSettings](https://create.roblox.com/docs/reference/engine/classes/UserGameSettings.md), [SavedQualitySetting](https://create.roblox.com/docs/reference/engine/enums/SavedQualitySetting.md) | `SavedQualityLevel` is `Automatic` (0, "determined automatically based on device performance") or `QualityLevel1`–`10`. | See **Graphics defaults** below. |
| Thumbnails | [Thumbnails](https://create.roblox.com/docs/production/publishing/thumbnails.md) | 16:9, ideally 1920 × 1080. Creator Dashboard → game → **Configurations → Places** → a place → **Thumbnails** → **Home Page** tab → Edit active thumbnails → 2–5 **Active**, each under 3 MB → Save → **Start**. Personalization starts only with 2 or more active. Nothing essential at the bottom. | As planned. |
| Icon | [Icons](https://create.roblox.com/docs/production/publishing/experience-icons.md) | Square, 512 × 512; check it at 150 × 150. | As planned. |
| Server size | [Places (Open Cloud)](https://create.roblox.com/docs/cloud/reference/features/places.md) | `PATCH /cloud/v2/universes/{u}/places/{p}` with `updateMask=serverSize`: "the maximum number of allowed users in a single server". | Task 9 can set 6 through Open Cloud (or you in the Dashboard). The DEV place is already 6 (batch 3: `OrderedList = 17 = 5 + 2 × 6`). |
| Managed Pricing | [Managed pricing](https://create.roblox.com/docs/production/monetization/managed-pricing.md), [Regional pricing](https://create.roblox.com/docs/production/monetization/regional-pricing.md) | "**New games and newly created items are enrolled in Managed pricing by default.** Item-level opt-out is available at any time." It combines price tests and regional pricing (30–100 % of the default price). In-game prices must come from `GetProductInfoAsync`. | The monetization spec says **week 1 at default prices**, so in task 9 the 15 live items are **opted out** (Monetization → Managed Pricing) until week 2. The UI already reads `GetProductInfoAsync`, so regional prices will show correctly later. |
| Rewarded video | [Rewarded video ads](https://create.roblox.com/docs/production/promotion/rewarded-video-ads.md) | Game: public and unrestricted, with a **reviewed and approved** questionnaire and ≥ 2,000 unique visitors per month. Publisher: 13+, **2FA and ID verification**. Rewards: developer products, not random. Eligibility is under **Monetization → Ads → Eligibility**. | No code change. Your account steps (2FA, ID) are the same as for the all-ages release below. |
| Analytics delay | [Custom events](https://create.roblox.com/docs/production/analytics/custom-events.md), [Funnel events](https://create.roblox.com/docs/production/analytics/funnel-events.md) | "Events can only be sent from the server and **in published games**. Events can't be sent from the client or **Studio**." Custom events are aggregated daily: "it may take up to 24 hours". | **Task 6's dashboard evidence needs a session on the published DEV place**, then up to a day's wait. Studio only shows the `[Analytics]` prints. |
| Questionnaire and release | [Content ratings](https://create.roblox.com/docs/production/promotion/content-ratings.md), [Publish games](https://create.roblox.com/docs/production/publishing/publish-games-and-places.md), [Kids and Select](https://create.roblox.com/docs/production/publishing/kids-and-select.md) | **Renamed "Content Ratings Questionnaire"**: Creator Dashboard → game → **Publish settings → Content ratings** → Get a rating. The name, description and genre must be saved first; it takes 15–60 min, and the ratings can take a few days if you aren't age-verified as 18+. **Releasing is now done from Studio's File → Publish window.** Answering "No" to the first question gives "Content May Vary" and **ages 16+ only**. **All ages (Kids 5–8, Select 9–15)** also needs ID verification (government ID if 18+), 2FA, the **full** questionnaire with a Minimal, Mild or Moderate rating, a **1,000 R$ refundable fee or a 2-month Roblox Plus/Premium subscription**, and an **evaluation**: the game first runs for age-checked 16+ users until it reaches **100 unique plays by "highly engaged" players within 60 days**. Before release you can "invite up to 10 similar-aged friends" as testers. | **This changes launch steps 4, 8 and 9:** plan change K, to confirm before task 9. |

### Graphics defaults (change G, from the batch 2 proof)

The phone proof (57–60 FPS with 78 crystals, no fallback needed) keeps the defaults at today's look. `Config/Graphics.luau` (task 2) holds two profiles:

| Field | `Full` (default; also used for `Automatic`) | `Low` (`SavedQualityLevel` 1–3) | Today's code |
|---|---|---|---|
| `LightsMinTier` (un-mutated crystals get a PointLight from this tier up) | 7 (Epic and Legendary) | 9 (Legendary only) | `GLOW_TIER = 7` in `CrystalVisuals` |
| `MutationLights` | true | true (mutations are rare and are the main "wow") | always on |
| `ParticleRate` multiplier | 1 | 0.5 | sparkles 4/s, embers 6/s |
| `GlassShell` | true | true (turning it off changes the look; kept as a switch for later) | always on |

`Automatic` keeps `Full`, because the engine already lowers its rendering on weak devices. The profile is re-read when `SavedQualityLevel` changes. The phone stress reading is repeated after the polish (task 10).

### Plan change K (pending; to confirm with you before task 9)

**Launch audience.** Under today's release rules, the live game can start only with **age-checked 16+ players**. Reaching under-16s, most of this game's audience, needs your account steps (ID verification, 2FA), the full questionnaire, the 1,000 R$ refundable fee (or 2 months of Plus/Premium), and then 100 engaged 16+ plays within 60 days. The plan's "make it public" therefore becomes: release to 16+ first, then all ages once the evaluation passes. The **playtest** (launch step 8) can use the "invite up to 10 friends" preview instead of a public release. The account steps take time, so you may want to start them early.
