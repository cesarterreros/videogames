# Specification: Batch 4, UI and onboarding (HUD, screens, seed picker, tutorial, sounds)

Status: approved 2026-11-18. Not started; implemented in its own session.

## Context

After batch 3 ([record](2026-11-18-batch-3-progression-and-saving.md)), all game systems work but can only be used through command-bar remotes. This batch builds **everything the player sees on screen**:
- the HUD and every panel listed in the [MVP spec](2026-11-18-crystal-grove-mvp.md) "UI screens and user flows",
- the **seed picker** (replacing batch 2's "plant the lowest seed" rule),
- tap-to-shatter, the Shatter All button, hub stalls and teleports,
- toasts and announcements,
- sounds and music,
- the **60-second tutorial** from the MVP "Onboarding" table, with its analytics funnel.

It follows the architecture build-order item 10. After this batch, the game is playable by a new player without instructions. Monetization comes in batch 5.

### Context for a new session (read before task 1)

1. [README.md](README.md): **Starting a new session** and **Delegation lessons**.
2. This record.
3. The [MVP spec](2026-11-18-crystal-grove-mvp.md): "UI screens and user flows", "Mobile-first controls", "Onboarding: the first 60 seconds", "Sound and visual style", "Analytics events", and the Decisions and Amendment sections.
4. The [monetization spec](2026-11-18-crystal-grove-monetization.md): only "Guardrails" item 4 (kid-safe selling) and the **HUD reserved slot** (bottom-right). This batch leaves that slot empty.
5. The batch 2 and batch 3 records: their shared contracts (pedestal attributes, `ShatterResult`, remotes, services) and their Findings and Outcome sections.
6. **Code to read:**
   - client: `roblox/src/client/**`
   - shared: `roblox/src/shared/Strings/en.luau`, `Net/Remotes.luau`, `Config/*.luau`, `Logic/Format.luau`, `Logic/Surge.luau`, `Logic/Economy.luau`, `Logic/Codex.luau`, `Logic/Goals.luau`
   - server: `Services/CrystalService.luau`, `ProgressionService.luau`, `DataService.luau`, `MapService.luau`
7. **Starting state:** the batch 3 branch is committed and all tests pass. Create `batch-4-ui-onboarding`.

### Outside facts

To be checked in official docs in task 1, with the URL and date recorded:
- `ScreenGui.ScreenInsets` with `Enum.ScreenInsets.DeviceSafeInsets`, and `ScreenGui.IgnoreGuiInset`.
- `UISizeConstraint`, `UIScale`, `UIStroke`, `UICorner`, `UIListLayout`, `UIGridLayout`.
- `Font.fromEnum` / `Font.new` for a rounded font such as FredokaOne.
- `TweenService:Create`.
- `Beam` for the tutorial arrow.
- `SoundService` and `Sound` (`SoundId`, `PlaybackSpeed`).
- `UserInputService.TouchTapInWorld` / `Mouse.Hit`, or `Camera:ViewportPointToRay` with `workspace:Raycast`, for tap-to-shatter.
- Whether emoji render in `TextLabel` on all platforms (see Decision 1).

## Behaviour

All text comes from `Strings.get` (localization-ready). All numbers come from `Format`. Every tappable element is **at least 48 × 48 px**, enforced by `UISizeConstraint`. Nothing is placed in the bottom-left (the thumbstick) or the top-left (the Roblox menu). The layout is landscape-first.

### HUD (always visible after the tutorial; partly during it)

| Position | Element | Behaviour |
|---|---|---|
| Top centre | **Coin counter** 💰 "12.4K" | Ticks up over 0.4 s when coins increase |
| Top right | **Weekly best** 🏆 "18.4 ct" | From `WeeklyBest`; "—" when this week is empty |
| Left column | **🏠 My Cave**, **🛒 Shop**, **⬆️ Upgrades**, **📖 Codex** | My Cave moves your character to your cave's `SpawnPoint` (the client moves its own character, no remote). Shop and Upgrades open their panels. |
| Right column | **🎁 Daily** (with a red dot when claimable), **🎯 Goals** (with a dot when a goal or the bonus can be claimed), **⚡ Surge** countdown "Surge in 12:34" or "SURGE! 3:10" (gold) | Opens panels |
| Right column, bottom | **🎲 Odds** | Opens the Odds panel |
| Bottom centre | **"Shatter All (N)"** | Visible when 2 or more of your crystals are ready; fires `ShatterAll` |
| Bottom right | **Reserved slot** | An empty frame `MonetizationSlot`, used in batch 5 |
| Top right, under weekly best | **🔊 / 🔇 Music** | Fires `SetSetting("Music", bool)` |

### Panels (one open at a time; tapping outside or ✕ closes; opening one closes the others)
- **Seed picker** (opened by tapping an **empty unlocked pedestal** in your cave):
  - a horizontal strip of the seeds you own, with counts;
  - tapping one fires `Plant(index, seedId)` and closes the picker;
  - if your bag is empty, it shows "No seeds — visit the Shop" with a Shop button.
- **Shatter result popup:**
  - a 2-second, non-blocking card near the top: "+12.4K", "14.2 ct", a mutation badge, "NEW BEST!", and the size tier ("HUGE!" in the size colour);
  - it stacks up to 3 cards.
- **Shop:**
  - a grid of 10 seed cards: crystal colour swatch, name, price, grow time, and buttons "Buy" and "×5";
  - locked cards show a dark silhouette and "Shatter a {prev} to unlock";
  - cards you can't afford show a greyed price.
- **Upgrades:** two cards. "Pedestal 4/10 — 100 💰" and "Growth Lamp 1/5 — −5% grow time — 1K 💰". At the maximum, "MAX".
- **Codex:**
  - a 10 × 4 grid, with rows of crystals and the columns None, Glowing, Molten, Prismatic;
  - undiscovered cells are silhouettes, and completed rows show "+10%".
- **Daily:**
  - 7 day tiles with today highlighted, and a "Claim" button;
  - it **opens automatically on the first join of a UTC day once the tutorial is done**.
- **Goals:** 3 rows with a label, a progress bar "12/20", and a Claim button; plus the Surprise Seed bonus row.
- **Odds:** a size-tier table and a mutation table with percentages. During a Surge, the mutation column shows the boosted odds with "⚡ ×2".
- **Toasts:** up to 3 stacked at the top centre for 2.5 s each. They show `Toast` and `Announce` messages; announcements have a gold border.

### World interactions
- **Tap or click on your own crystal:**
  - **ready** → shatter;
  - **growing** → a small bubble with the countdown;
  - **empty unlocked pedestal** → the seed picker.
- **ProximityPrompts:** they stay as a second way in. The "Plant" prompt now opens the seed picker instead of planting the lowest seed.
- **Hub stalls:** two stalls next to the hub spawn, **"Seed Shop"** and **"Upgrades"**. Each has a sign and a prompt that opens its panel.

### Tutorial (new players only; `Tutorial.Done == false`)

| Step | Who advances it | What the player sees | Server rule |
|---|---|---|---|
| 1 Spawned | Server, on load | Arrow (a Beam from the character) and bubble "Tap the pedestal to plant!" at pedestal 1. All HUD buttons are disabled. | — |
| 2 Planted | Server, on the first plant | Bubble "Watch it grow…" | **This crystal grows in `Tutorial.GrowSeconds` (8 s)** |
| 3 FirstShatter | Server, on the first shatter | "+50 bonus!" | **+`Tutorial.BonusCoins` (50) extra coins** |
| 4 OpenedShop | Client (`TutorialAction(4)`), when the Shop opens | The arrow points to the Shop button, which is the only one enabled. Bubble "Buy seeds!" | — |
| 5 BoughtSeed | Server, on the first `BuySeed` | Bubble "Plant them!" | — |
| 6 PlantedTwo | Server, after 2 more plants | — | **The 3rd plant overall is forced to Mutation = "Glowing"** |
| 7 FirstMutation | Server, on shattering that Glowing crystal | Popup "Lucky! GLOWING ×2" | — |
| 8 TutorialDone | Client (`TutorialAction(8)`), after the tip bubble "Rare crystals keep growing while you're offline!" is closed | All HUD buttons are enabled; the daily popup opens | `Tutorial.Done = true` |

- **Each step:** logs `LogOnboardingFunnelStepEvent(player, step, name)` once.
- **Client-reported steps:** the server accepts `TutorialAction(n)` only when n is 4 or 8 **and** equals the current step + 1.
- **Interrupted tutorial:** a player who leaves mid-tutorial continues from their saved step.
- **Studio seed top-up (from batch 2):** it now runs only when `Tutorial.Done == true`, so it doesn't disturb the tutorial.

### Sounds
- **Sound list:** `Config/Sounds.luau` maps names to asset IDs: `Shatter`, `Coin`, `Ready`, `Mutation`, `NewBest`, `Click`, `Music`. **An ID of 0 is silent**, so the game works before IDs are filled in.
- **Shatter pitch:** `PlaybackSpeed` = 1.0 + 0.05 × (tier − 1).
- **Music:** one quiet loop at volume 0.3, following `Settings.Music`.
- **Choosing the sounds (you, task 2):** pick the 7 sounds from the Creator Store **Audio** section, filtered to audio published by Roblox (licensed for use in experiences), and paste their IDs into `Config/Sounds.luau`. **No uploaded copyrighted music.**

### Edge cases
- **Small phones (iPhone SE landscape):** panels use scale sizing with an aspect constraint. Grids scroll (`ScrollingFrame`) rather than shrink below 48 px buttons.
- **StateSync while a panel is open:** the panel refreshes in place without closing.
- **Tapping during the tutorial outside the target:** ignored. HUD buttons are disabled except the target.
- **Music toggle:** it is saved (`Settings.Music`), so it persists across sessions.

## Not included

- **Store tab, purchase buttons, ad buttons, the Starter Pack popup, Instant Grow, the Luck slot, and filling the reserved slot:** batch 5.
- **VIP cosmetics, Auto Shatter:** batch 5. Because of that, the `SetSetting("AutoShatter")` server handler rejects it until batch 5.
- **Final polish** (coins flying into the counter, camera shake tuning, lighting): batch 6.
- **Languages other than English.** The string keys are ready.
- **A settings menu beyond the music toggle.**

## Design

**Stored data:** no schema change. It uses `Tutorial.Step`, `Tutorial.Done` and `Settings.Music`.

### Shared contract (every screen follows it, so the screens can be built in parallel jobs)

```lua
-- src/client/UI/Theme.luau  (pure data)
Theme.Colors = { Bg = "#14122B", Panel = "#221F45", Text = "#FFFFFF", Muted = "#A9A6C9", Gold = "#FFD54A",
                 Good = "#4CD964", Bad = "#FF5A5F",
                 Rarity = { Common = "#E6E9EE", Uncommon = "#4CD964", Rare = "#3D8BFF", Epic = "#B05CFF", Legendary = "#FFB020" } }
Theme.Font = "FredokaOne"      -- resolved via Font.fromEnum(Enum.Font.FredokaOne)
Theme.MinTouch = 48            -- px
Theme.Corner = 12              -- px
Theme.color(hex: string): Color3

-- src/client/UI/Components.luau
Components.button(props: { Text: string?, Icon: string?, Size: UDim2, Position: UDim2?, AnchorPoint: Vector2?,
                           Color: string?, OnClick: () -> (), Parent: Instance }): TextButton
  -- includes UICorner, UIStroke (2px dark), UISizeConstraint(MinSize = 48x48), press scale 0.95 tween, Click sound
Components.panel(props: { Title: string, Size: UDim2, Parent: Instance, OnClose: () -> () }): (Frame, Frame)  -- (root, content)
Components.label(props: { Text: string, TextSize: number?, Color: string?, Parent: Instance, Size: UDim2 }): TextLabel
Components.progressBar(props: { Parent: Instance, Size: UDim2 }): { Set: (fraction: number, text: string) -> () }

-- Every screen module in src/client/UI/Screens/<Name>.luau:
Screen.new(ctx: Ctx): { Root: GuiObject, Open: (args: any?) -> (), Close: () -> (), Update: (snapshot) -> (), IsOpen: () -> boolean }
-- ctx (built by UIController):
Ctx = { Gui: ScreenGui, Strings, Theme, Components, Remotes: Folder, State (StateController),
        Sounds (SoundController), UI (UIController: :Open(name, args), :Close(name), :Toast(text, gold?)),
        Config = { Seeds, Rolls, Economy, Progression }, Logic = { Format, Economy, Surge, Codex, Goals } }

-- Screen names: "Hud", "SeedPicker", "Result", "Shop", "Upgrades", "Codex", "Daily", "Goals", "Odds", "Toasts"
-- UIController: one ScreenGui "CrystalGroveUI" (ResetOnSpawn=false, ScreenInsets=DeviceSafeInsets, IgnoreGuiInset per task 1),
--   creates all screens, routes StateSync → screen:Update, ShatterResult → Result, Toast/Announce → Toasts,
--   enforces one open panel, exposes :SetLocked(allowedName?) for the tutorial.
-- TutorialController: listens to snapshot.Tutorial, draws Beam + bubble, calls UI:SetLocked, fires TutorialAction(4|8).
-- TapController: tap/click → raycast → own pedestal → Shatter / countdown bubble / UI:Open("SeedPicker", index).
-- SoundController: :Play(name, pitch?), :SetMusic(on).

-- Server
TutorialService:IsActive(player): boolean
TutorialService:GrowSecondsOverride(player): number?       -- 8 during step 1→2, else nil
TutorialService:ForcedMutation(player): string?            -- "Glowing" for the 3rd plant overall during the tutorial
TutorialService:BonusCoins(player): number                  -- 50 on the first shatter, else 0
TutorialService:OnEvent(player, event: "Plant"|"Shatter"|"BuySeed")   -- advances server-driven steps
-- handles remote TutorialAction(step); logs LogOnboardingFunnelStepEvent
SettingsService handles SetSetting("Music", bool); "AutoShatter" is rejected until batch 5
```

### Files

| File (under `roblox/`) | Change | Task |
|---|---|---|
| `src/shared/Strings/en.luau` | Every UI string (button labels, panel titles, tutorial bubbles, the Odds headings, "No seeds — visit the Shop", "MAX", "Claim", "Surge in {time}", "SURGE! {time}", "NEW BEST!", "Lucky! GLOWING ×2", the stall signs) | 1 |
| `src/shared/Config/Sounds.luau` | New, IDs 0 | 1 |
| `src/client/UI/Theme.luau`, `Components.luau` | New | 3 |
| `src/client/UI/Screens/Hud.luau` | New | 4 |
| `src/client/UI/Screens/SeedPicker.luau`, `Result.luau` | New | 5 |
| `src/client/UI/Screens/Shop.luau`, `Upgrades.luau` | New | 6 |
| `src/client/UI/Screens/Codex.luau`, `Odds.luau` | New | 7 |
| `src/client/UI/Screens/Daily.luau`, `Goals.luau` | New | 8 |
| `src/client/UI/Screens/Toasts.luau`, `src/client/Controllers/SoundController.luau` | New | 9 |
| `src/client/Controllers/UIController.luau`, `TapController.luau` | New | 10 |
| `src/server/Services/TutorialService.luau`, `SettingsService.luau`; changes in `CrystalService` (override, forced mutation, bonus coins, tutorial events, top-up rule) and `ShopService` (BuySeed event); `Main.server` order | New / changed | 11 |
| `src/client/Controllers/TutorialController.luau` | New | 12 |
| `src/server/Services/MapService.luau` (hub stalls `SeedShopStall` and `UpgradeStall`); `src/client/Controllers/CrystalRenderer.luau` (the Plant prompt opens the picker); `src/client/Main.client.luau` order: State → Sound → UI → CrystalRenderer → Effects → Tap → Tutorial | Changed | 13 |

## Task breakdown and model assignment

| # | Task | Model | Why this model | Depends on |
|---|---|---|---|---|
| 0 | Branch and save the record status | Orchestrator | — | — |
| 1 | **Proof:** check the "Outside facts" APIs, including emoji rendering in the device emulator; add all strings and `Config/Sounds` | Orchestrator | Judgment; the strings are the shared text contract | 0 |
| 2 | Pick 7 licensed sounds and paste their IDs | You | Needs your Creator Store account | 1 |
| 3 | `UI/Theme`, `UI/Components` | DeepSeek Flash | Foundation; exact contract | 1 |
| 4–9 | Screens, two files per job, in the order in the Files table | DeepSeek Flash | Standard UI code against the contract | 3 |
| 10 | `UIController`, `TapController` | DeepSeek Flash (Pro if cut off twice) | Routing and raycast | 4–9 |
| 11 | `TutorialService`, `SettingsService`, server integrations | Orchestrator | Grants coins and changes rolls | 1 |
| 12 | `TutorialController` | DeepSeek Flash | Client visuals, exact step table | 10, 11 |
| 13 | Stalls, renderer prompt change, client order | Haiku | Small, fully specified | 10 |
| 14 | Review, tests, StyLua, build, emulator and phone checks with you; findings and outcome | Orchestrator | — | all |

Escalation: as in earlier batches (back once with defects, then DeepSeek Pro, or the orchestrator fixes small ones). **If emoji don't render reliably** (task 1), switch `Components.button` to text-only labels with rarity colours and record it as a finding. Image icons need asset uploads, which would be a separate amendment.

### Acceptance criteria

- **Task 1:** each API is checked, with URL and date; strings exist for every visible text; `Config/Sounds` has the 7 keys.
- **Task 3:** every component meets the minimum touch size; `Theme.color("#FFFFFF")` returns white.
- **Tasks 4–9:** each screen follows the `Screen.new(ctx)` contract, uses only `ctx` (no hard-coded text or prices), updates in place from the snapshot, and contains no `FireServer` except the remotes its row lists:
  - Hud: `ShatterAll`, `SetSetting`
  - SeedPicker: `Plant`
  - Shop: `BuySeed`
  - Upgrades: `BuyUpgrade`
  - Daily: `ClaimDaily`
  - Goals: `ClaimGoal`
- **Task 10:** only one panel is open at a time; tap-to-shatter works only on your own plot; `SetLocked` disables every non-target button.
- **Task 11:**
  - Steps advance exactly as in the table, each logged once.
  - `TutorialAction` only accepts 4 or 8, and only as the next step.
  - The 8-second grow, the +50 coins and the forced Glowing apply only during the tutorial, and only once each.
  - The top-up only runs when the tutorial is done.
  - `SetSetting("Music")` is saved.
- **Task 12:** the Beam and bubble follow the table; the tutorial survives a rejoin.
- **Task 13:** the stalls open their panels; the Plant prompt opens the picker.
- **Task 14:**
  - All tests pass; StyLua is clean; the build succeeds.
  - A **new-player tutorial run in the phone emulator takes 75 s or less** without instructions.
  - There is no UI overlap on iPhone SE and on a mid-size Android in landscape.

## Verification

- **Automated tests:** existing tests, plus a new `Strings.spec.luau` checking that every key used in `UI/**` exists in `en.luau` (it scans the sources for `Strings.get("…")` and for `ctx.Strings.get("…")`).
- **Backup first:** not needed. There is no schema change.
- **Fresh profile in Studio:** to test the tutorial, use a second account, or temporarily change `Config.Game.ProfileStoreName` to `PlayerData_Test1` and **revert it afterwards**; record that in Leftovers.
  1. Join → arrow to pedestal 1; HUD buttons disabled.
  2. Plant → about 8 s → shatter → coins 15+ plus 50.
  3. Arrow to Shop → buy 2 Quartz → plant both → the 3rd plant is Glowing.
  4. Shatter it → "Lucky! GLOWING ×2".
  5. Tip → close → HUD unlocked → the daily popup opens.
  6. Total time: 75 s or less.
- **Device emulator (iPhone SE and a mid-size Android, landscape):** every button is reachable; no overlap with the thumbstick or the Roblox menu; the panels scroll.
- **Real phone (published dev experience):** a tutorial run by touch only; tap-to-shatter works; music toggles.
- **Studio 2-player server:** player B's toasts and announcements show; A's tap on B's crystal does nothing.

## Decisions (confirmed by the user 2026-11-18, recommended options chosen)

1. **Emoji as icons** (💰 🛒 📖 🎁 …) for v1. Rejected: custom image icons, which need art and uploads. If task 1 finds emoji unreliable, use text-only labels.
2. **The UI is built in code with plain Instances, no UI library.** Rejected: Fusion or React-lua via Wally, which add packages and a learning curve, though they would help a bigger UI later.
3. **Testing the tutorial with a temporary profile store name**, reverted afterwards. Rejected: a dev command to reset your tutorial, which comes in batch 6 with the admin command.
