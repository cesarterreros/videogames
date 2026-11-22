# Specification: Batch 4, UI and onboarding (HUD, screens, seed picker, tutorial, sounds)

Status: approved 2026-11-18. Built and verified 2026-11-21 (see Outcome); committed as `1d7b489` on `batch-4-ui-onboarding`, pushed.

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

## Progress (2026-11-21)

- **Task 0 done:** branch `batch-4-ui-onboarding` created from `batch-3-progression` (`fd3317f`, pushed; same tree as `batch-1-setup` after PR #3). Starting state: `lune run tests` **154 passed, 0 failed**; StyLua clean. The Rojo server from the last session is still listening on port 34872.
- **Plan changes confirmed by you (2026-11-21)**, after comparing this plan with the batch 3 and cave-brightness work:
  - **A. ☀ button:** `BrightnessButton` keeps its cycle code but puts its button into a slot the HUD reserves next to 🔊 inside `CrystalGroveUI` (no own ScreenGui any more). The HUD itself still sends only `ShatterAll` and `SetSetting`. ☀ and 🔊 stay enabled during the tutorial (`SetLocked` leaves them alone). Client order: State → Lighting → Sound → UI → Brightness → CrystalRenderer → Effects → Tap → Tutorial.
  - **B. Existing profiles skip the tutorial:** every profile so far has `Tutorial = {Step = 0, Done = false}`. A profile at step 0 that has already shattered (`Stats.Shatters > 0`) is set to `Done = true` on load, with no funnel events. Tutorial tests still use the temporary `PlayerData_Test1` store (Decision 3).
  - **C. Plant count without a new field:** plants so far = `Stats.Shatters` + crystals on pedestals. Exact for a tutorial player (thanks to B), and it survives a rejoin. It drives the 8-second grow (first plant), the forced Glowing (3rd plant) and step 6.
  - **D. Tutorial bonus:** a separate `DataService:AddCoins(50, "Onboarding", "TutorialBonus")` right after the shatter coins (its own economy event). `ShatterResult` gets a new field `bonusCoins` (0 normally) for the popup. The shatter order is otherwise unchanged.
  - **E. New pure module `Logic/Tutorial.luau`** with Lune tests (active check, grow override, forced mutation, bonus, step advances); `TutorialService` calls it.
  - **F. Details:** a `BuySeed` arriving before `TutorialAction(4)` logs step 4, then 5. The popup string becomes "Lucky! {mutation} ×{mult}" (a random Molten on plant 2 can also reach step 7). Toasts use a new tested `Strings.message(key, params)` that collapses double spaces; the Studio `[Toast]`/`[Announce]` prints leave `StateController`.
- **Task 1 done (2026-11-21, orchestrator).** You confirmed the ScreenInsets change (Findings).
  - **Strings:** 82 new keys in `en.luau`: the HUD, every panel, the result popup, the tap bubble, the tutorial bubbles (with "Lucky! {mutation} ×{mult}", change F), the stall signs and `Prompt.Open`, plus `Mutation.None` = "None" for the Codex column. Emoji are **not** in the strings: they go in `UI/Theme` (task 3) as icons, so a text-only fallback needs no string change.
  - **Added beyond the plan:** `Hud.FriendBonus` ("Friends +{percent}%") for the `FriendBonus` attribute, shown only when it's above 0. `Shop.Owned`, `Upgrades.PedestalEffect`, `Codex.Hint` and `Odds.Note` are short helper lines on their panels.
  - **[Config/Sounds.luau](../../roblox/src/shared/Config/Sounds.luau):** `Ids` with the 7 names (all 0 = silent), `MusicVolume = 0.3`, `EffectsVolume = 0.6`, `ShatterPitchStep = 0.05`.
  - **Change F:** `Format.tidySpaces(text)` (pure, tested) and `Strings.message(key, params)` = `tidySpaces(get(...))` for Toast and Announce payloads.
  - **New tests (3):** `tidySpaces` (the empty-mutation case); `Config/Sounds` has exactly the 7 IDs as whole numbers ≥ 0 and is in the "no require" list; `Mutation.None` and a `Result.Size.*` label exist for every size tier above Normal.
  - Tests **157 passed, 0 failed** (154 + 3); StyLua clean; `rojo build` succeeds.

- **Task 2 done by the orchestrator at your request (2026-11-21)**, not by you as planned. The Creator Store search (Studio MCP `search_asset`, Audio) mostly returns community uploads, several named after other games ("Subway Surfers", "Half Life", "Deltarune"), so only assets whose **creator is exactly "Roblox"** were used. Each was loaded in Studio Edit mode (`IsLoaded = true`) and its length read; the probe sounds were deleted afterwards.

  | Name | Asset (creator Roblox) | ID | Length |
  |---|---|---|---|
  | Shatter | glassbreak.wav | 12222005 | 1.58 s |
  | Coin | CoinTransfer_01 | 127645268874265 | 1.66 s |
  | Ready | Roblox_UI_Indicator | 15675085146 | 3.37 s |
  | Mutation | Roblox_UI_Tonal_Stinger | 15675043410 | 1.47 s |
  | NewBest | Roblox_UI_Piano_Hello | 15675016548 | 4.04 s |
  | Click | Roblox_UI_Small_Click | 15675032796 | 0.13 s |
  | Music | Roblox_UI_Loop_Calm_Music | 15675069601 | 95.5 s |

  - **Not listened to:** chosen by name and length only. You judge how they sound in task 14 (or earlier on the store pages); swapping one is a one-line change in `Config/Sounds`.
  - **Compromises:** no Roblox-made "fanfare" was found, so NewBest is a short piano phrase. The shatter is Roblox's classic glass break rather than a crystal "ting". DistroKid tracks (`DistrokidOfficial`, Roblox's licensed music partner) were left out to keep to "published by Roblox".

- **Task 3 done (2026-11-21, DeepSeek Flash, accepted with one fix):** [UI/Theme.luau](../../roblox/src/client/UI/Theme.luau), [UI/Components.luau](../../roblox/src/client/UI/Components.luau), [tests/Theme.spec.luau](../../roblox/tests/Theme.spec.luau) (6 tests).
  - **Contract additions** (screens may use them): `Theme.Colors` also has `PanelLight`, `Stroke`, `Disabled`; `Theme.StrokeThickness = 2`; `Theme.Icons` (the emoji, with `Close = "X"`); `Theme.rgb(hex)` (pure, tested under Lune) and `Theme.fontFace()`. `Components.setClickSound(fn)` (UIController hands it `SoundController:Play("Click")`), `Components.setEnabled(button, bool)` / `isEnabled` (the attribute `Disabled`; greyed and ignores taps), and optional `Name`, `LayoutOrder`, `TextColor`, `XAlignment`, `AspectRatio` props. `progressBar` returns `{ Root, Set }`.
  - **Review fix (orchestrator):** the job assigned `Theme.fontFace()` (a `Font` datatype) to `.Font`, which only takes an `Enum.Font` and would have errored at runtime. Changed to `.FontFace`, with a new source check in `Theme.spec`.
  - **Studio check (Edit mode, Device Simulator; temporary GUI deleted afterwards):** `Theme.color("#FFFFFF")` equals white; a button built at 10 × 10 px renders at **48 × 48**, as does the panel's close button; `FontFace` is FredokaOne; disable/enable restores the colour; the bar fill follows `Set(0.4, …)`. A screenshot shows the panel, gold title, red X, progress bar and outlined label as intended.
  - **Review:** recovery journal (5 entries) checked against the files and acknowledged. Tests **163 passed, 0 failed** (157 + 6); StyLua clean. DeepSeek wrote its build check inside `roblox/` and deleted it; nothing left behind.

- **Before tasks 4–9 (2026-11-21, orchestrator):**
  - **Touch controls measured** (short Play Solo, Galaxy S25 Ultra landscape, then stopped): the `CoreUISafeInsets` area is **685 × 280** below the 58 px top bar; the jump button covers x 590–660, y 190–260; the resting thumbstick covers x 29–103, y 187–261 (its touch zone is the lower-left area). The HUD layout given to the jobs keeps clear of both: a 2 × 2 button grid top-left, another top-right under the weekly best / music / ☀ row, Shatter All bottom centre, and the reserved slot just left of the jump button. **This differs from the plan's "left column / right column"** (four stacked buttons per side would reach the thumbstick and the jump button on this phone); **you approved the two-grid layout on 2026-11-21**, after it was built.
  - **New [tests/Screens.spec.luau](../../roblox/tests/Screens.spec.luau) (3 tests):** every literal `Strings.get`/`Strings.message` key in `UI/**` exists (the plan's `Strings.spec`); each screen looks up only its allowed remotes (`ctx.Remotes:WaitForChild("Name")`) and no other way; screens call no `require`. Tests **166 passed**.
  - **Shared screen brief** for every job: the `ctx` fields (adds `Player`, `Now()`, `Logic.Growth`, `Logic.WeekId`, `Config.Game`, `Config.Sounds` and `Sounds:SetMusicFromTap` to the plan's ctx), the snapshot shape, layout zones and the rules above.
- **Task 4 done (2026-11-21, DeepSeek Flash; the job stopped on its token budget after writing the file; accepted with fixes):** [Screens/Hud.luau](../../roblox/src/client/UI/Screens/Hud.luau).
  - Exposes `Buttons` (MyCave, Shop, Upgrades, Codex, Daily, Goals, Surge, Odds, ShatterAll; the music button isn't in it, so the tutorial lock leaves it alone), `BrightnessSlot` and `MonetizationSlot`. Surge opens the Odds panel. The 1-second loop updates the surge countdown, Shatter All, the dots and the weekly best, and plays `Ready` when the ready count rises.
  - **Review fixes (orchestrator):** the weekly-best pill was 110 px too far left (a gap before 🔊); `MonetizationSlot` was missing from the returned table; label sizes were uneven (`TextScaled` blew up short labels), so `Components.button` got an optional `TextSize` cap (contract addition) and the HUD buttons use 18 px at 108 × 48.
  - **Studio check (Edit mode, Device Simulator, fake ctx, temporary GUI):** every HUD button measures ≥ 48 px tall (grid 108 × 48, Shatter All 180 × 52); coins "💰 954" with the tick-up caught mid-way; weekly best "🏆 2.0 ct"; both dots on for a claimable daily and goal; surge "Surge in 23:52"; "Shatter All (2)" for 2 ripe crystals; "Friends +20%" for a bonus of 0.2. Screenshot checked. **Not checked yet:** taps (they need a Play session; task 10) and the layout under the real top bar.
  - Recovery journal (3 entries) checked and acknowledged. Tests **166 passed**; StyLua clean.

- **Rule from you (2026-11-21):** when a DeepSeek job stops early, retry the work with DeepSeek instead of the orchestrator finishing it.
- **Task 5 done (2026-11-21, DeepSeek Flash, accepted first time):** [Screens/SeedPicker.luau](../../roblox/src/client/UI/Screens/SeedPicker.luau), [Screens/Result.luau](../../roblox/src/client/UI/Screens/Result.luau).
  - **SeedPicker:** a horizontal strip of owned seeds (110 × 130 cards: colour swatch, name, "×n", rarity-coloured border); a tap fires `Plant(index, seedId)` and closes. Cards rebuild only when the set of owned seeds changes; otherwise only the counts update. An empty bag shows "No seeds — visit the Shop" and a Shop button.
  - **Result:** up to 3 cards in a row at y 96, newest on the left; 0.15 s pop-in, 2 s on screen, 0.3 s fade. Line 3 shows NEW BEST!, else "{mutation} ×{mult}", else "+{coins} bonus!"; with two of these, a mutation pill sits on the card's top edge. Sounds: Shatter (pitch `1 + 0.05 × (tier − 1)` from `result.seedId`), Coin, then Mutation / NewBest. **It needs `seedId` (and `bonusCoins`) in `ShatterResult`**: two new optional payload fields, added in task 11.
  - **Dynamic keys:** `Screens.spec`'s key check also matches the prefix of `Strings.get("Seed." .. id)`, so the jobs build dynamic keys in a local first. That works; noted for later jobs.
  - **Studio check (Edit mode, fake ctx, temporary GUI):** 3 seed cards at 110 × 130 with counts; a snapshot with an empty bag switches to the hint and the Shop button while the panel stays open. Cards "+12.4K / 14.2 ct / NEW BEST!" with a "Glowing" pill, "5.1 ct HUGE!" in purple, "+50 bonus!" in green; sounds in order with pitch 1.1 for Citrine (tier 3). Screenshot checked. The result cards are drawn over a panel's title for their 2 s (they don't take taps); accepted. **Not checked yet:** the Plant tap (Play session, task 10).
  - One harmless slip left as is: a fallback reads `Colors.Common` (nil) instead of `Colors.Rarity.Common`, and falls through to the Text colour.
  - Recovery journal (10 entries) checked and acknowledged. Tests **166 passed**; StyLua clean.

- **Task 6 done (2026-11-21, DeepSeek Flash, accepted first time):** [Screens/Shop.luau](../../roblox/src/client/UI/Screens/Shop.luau), [Screens/Upgrades.luau](../../roblox/src/client/UI/Screens/Upgrades.luau).
  - **Shop:** a scrolling grid of 10 cards (150 × 150, rarity border): swatch, name, ⏱ grow time with the lamp applied, "Owned: n", price (gold if affordable, greyed if not), Buy and ×5 (`BuySeed(id, 1|5)`). Locked cards: dark swatch and "Shatter a {prev} to unlock", no buttons. Extra field `Cards` (seed id → card) for the tutorial arrow.
  - **Upgrades:** two cards, "Pedestal 4/10" and "Growth Lamp 1/5 / −5% grow time", each with a price button (`BuyUpgrade`). Green when affordable, greyed but tappable when short (the server toasts), "MAX" and disabled at the end.
  - **Studio check (Edit mode, fake ctx; snapshot tier 3, 954 coins, pedestal 4, lamp 1):** Quartz "⏱ 0:19 · Owned: 3 · 💰 10" (20 s − 5 %), Buy 69 × 48; Rose Quartz "Shatter a Citrine to unlock"; Pedestal 500 green, Lamp 10K greyed; with pedestal 10/10 the button shows MAX and is disabled; buttons 174 × 52. Screenshots checked. **Not checked yet:** the buy taps (task 10).
  - **For task 10:** a `ScreenGui` made by script defaults to `ZIndexBehavior = Global`, so the HUD's notification dot drew over an open panel. `CrystalGroveUI` must use `Sibling` (checked: with it, the panel covers the dot).
  - Recovery journal (5 entries) checked and acknowledged. Tests **166 passed**.

- **Task 7 done (2026-11-21, DeepSeek Flash, accepted first time):** [Screens/Codex.luau](../../roblox/src/client/UI/Screens/Codex.luau), [Screens/Odds.luau](../../roblox/src/client/UI/Screens/Odds.luau).
  - **Codex:** hint line, header row (None, Glowing, Molten, Prismatic) and a scrolling 10 × 4 grid. Found cells take the crystal colour with a G/M/P mark and a gold/red/purple border; missing cells are dark silhouettes; a complete row shows "+10%".
  - **Odds:** size and mutation tables from `Config.Rolls`, None as the remainder. During a surge the mutation odds are ×2 in gold with "⚡ ×2"; refreshed every second while open. Note "The same odds for every player."
  - **Studio check (Edit mode, fake ctx):** Codex row Quartz complete (marks + "+10%"), Amethyst only None, the rest silhouettes. Odds normal: 88 / 10 / 1.8 / 0.2 %; None 93 %, Glowing 6 %, Molten 1.2 %, Prismatic 0.15 %. With the clock set to minute :02 (surge): Glowing 12 %, Molten 2.4 %, Prismatic 0.3 % with "⚡ ×2", None 85 %. All match `Config.Rolls` and `SurgeMutationMult = 2`. Screenshots checked.
  - Recovery journal (2 entries) checked and acknowledged. Tests **166 passed**.

- **Task 8 done (2026-11-21, DeepSeek Flash, accepted with layout fixes):** [Screens/Daily.luau](../../roblox/src/client/UI/Screens/Daily.luau), [Screens/Goals.luau](../../roblox/src/client/UI/Screens/Goals.luau).
  - **Daily:** 7 day tiles from `Progression.Streak` (coins or seed reward); the day due is highlighted gold (claimed today → that day; claimed yesterday → the next, wrapping after 7; else day 1), earlier days dimmed; Claim (`ClaimDaily`) turns into a disabled "Claimed" with "Come back tomorrow!". Re-checked every second while open.
  - **Goals:** 3 goal rows (label, progress bar "n/target", reward "+2.4K", Claim → `ClaimGoal(i)`; "Done" when claimed) and the Surprise Seed row (seed one tier up, `ClaimGoal("Bonus")` once all 3 are claimed). Goals from an old day show with every Claim disabled.
  - **Studio check (Edit mode, fake ctx):** Daily with yesterday claimed: Day 1 dimmed, Day 2 highlighted, Claim enabled; with today claimed: "Claimed", disabled. Goals: goal 1 at 20/20 claimable, goal 2 at 0/1 disabled, goal 3 "Done", bonus disabled; reward +2.4K (= 10 × Citrine 240), surprise seed Rose Quartz. Screenshots checked.
  - **Phone-size check (all panels inside a 685 × 280 frame, the measured safe area):** Shop, Upgrades, Codex and Odds fit. Three didn't, from the sizes the orchestrator gave the jobs; fixed by the orchestrator: **Goals** overflowed by 50 px (the bonus row was clipped) → its rows now scroll; **Daily** overflowed by 20 px → panel height 0.8 → 0.9; **SeedPicker** content was 105 px for 130 px cards → panel height 0.62 → 0.8. Re-measured: no overflow anywhere. Also fixed: "Emerald ×1" broke mid-word in its narrow Daily tile → the reward text shrinks to fit (max 15 px).
  - Recovery journal (2 entries) checked and acknowledged. Tests **166 passed**; StyLua clean.

- **Task 9 done (2026-11-21, DeepSeek Flash, accepted first time):** [Screens/Toasts.luau](../../roblox/src/client/UI/Screens/Toasts.luau), [Controllers/SoundController.luau](../../roblox/src/client/Controllers/SoundController.luau).
  - **Toasts:** extra field `Push(text, gold?)` (also `Open({ Text, Gold })`); up to 3 rows at the top centre (y 52), the 4th drops the oldest; 2.5 s, then a 0.25 s fade. Gold border and text for announcements. `ZIndex 50`, so toasts draw above panels.
  - **SoundController:** builds one `Sound` per non-zero ID in a client folder `SoundService.CrystalGroveSounds` (music looped at 0.3, effects at 0.6). `:Play(name, pitch?)` uses `PlayLocalSound` (pitch clamped 0.5–2); `:SetMusic(on)`; `:SetMusicFromTap(on)` ignores state syncs for 1.5 s. The music follows `Settings.Music` and only starts after the first snapshot.
  - **Studio check (Edit mode):** 4 pushes leave the newest 3 ("New in Codex: Quartz" with no double space, "Not enough coins", the gold "Player1 found a Colossal Prismatic Quartz!"); an empty push is ignored; all rows gone after 3.1 s; a screenshot shows them above the open Shop. SoundController: 7 sounds built, music volume 0.3 and looped, `SetMusic(true)` plays, `SetMusicFromTap(false)` stops, `Play("Shatter", 1.1)` sets speed 1.10 without error. Folders cleaned up. **Not checked yet:** how the sounds actually sound (task 14).
  - Recovery journal (3 entries) checked and acknowledged. Tests **166 passed**.

- **Task 10 done (2026-11-21, DeepSeek Flash in two jobs, both accepted with small fixes):** [UIController.luau](../../roblox/src/client/Controllers/UIController.luau), [TapController.luau](../../roblox/src/client/Controllers/TapController.luau); changes A and F in [BrightnessButton.luau](../../roblox/src/client/Controllers/BrightnessButton.luau) and [StateController.luau](../../roblox/src/client/Controllers/StateController.luau); [Main.client.luau](../../roblox/src/client/Main.client.luau).
  - **Split and moved:** the job was split in two (10A UIController + wiring, 10B TapController) to stay within the token budget. The client start order (plan: task 13) was done here, because nothing can be tried in Play without it: State → Lighting → Sound → UI → Brightness → CrystalRenderer → Effects → Tap (Tutorial is added in task 12).
  - **UIController:** builds `CrystalGroveUI` (`CoreUISafeInsets`, `ZIndexBehavior = Sibling`), the `ctx` and the 10 screens (z-order: HUD 1, dim backdrop 9, panels 10, results 40, toasts 50). One panel at a time; tapping the backdrop closes it. Routes `StateSync` → every `Update`, `ShatterResult` → Result, `Toast`/`Announce` → toasts (`Strings.message`, announcements gold). Opens Daily on the first snapshot of a session when the tutorial is done and today isn't claimed. API: `Open`, `Close`, `CloseAll`, `Toast`, `Get`, `OpenPanel`, `SetLocked(locked, allowedButton?)` (disables every HUD button but the allowed one; while locked only the SeedPicker and that button's panel can open), `IsLocked`, signals `PanelOpened`/`PanelClosed`/`Ready`, `WaitUntilReady`.
  - **TapController:** touch (`TouchTapInWorld`, skipped when `processedByUI`) and mouse (`InputBegan` MouseButton1, skipped when `gameProcessed`) → ray (mouse: `ViewportPointToRay` on `GetMouseLocation()`; touch: `ScreenPointToRay`) → the pedestal under the hit, only in your own plot. Ready → `Shatter(index)` (1 s cooldown per pedestal); growing → a 2 s "Ready in m:ss" bubble; empty and unlocked → the seed picker. `SetAllowed(fn)` for the tutorial.
  - **Review fixes (orchestrator):** (1) replacing an open panel didn't fire `PanelClosed` for it; it now goes through `Close`. (2) Found in Play: the tap that closed a panel via the backdrop also reached the world (the backdrop hides on release, and `TouchTapInWorld` fires after it), and opened the seed picker behind the Codex. TapController now ignores world taps while a panel is open and for 0.4 s after one closes. (3) The growing-crystal bubble never showed: 7 studs up it sat behind the HUD at close range, and an `AlwaysOnTop` billboard never appeared in a Studio capture. It now uses `AlwaysOnTop = false` and `StudsOffset (0, 2, 3)`, i.e. 3 studs toward the camera, in front of the crystal.

- **Task 11 done (2026-11-21, orchestrator):**
  - **[Logic/Tutorial.luau](../../roblox/src/shared/Logic/Tutorial.luau) (change E)**, pure: `StepNames`, `isActive`, `shouldSkip` (B), `plantsSoFar` (C), `growOverride`, `forcedMutation`, `bonusCoins`, and `advance(tutorial, event, info) -> (newStep, stepsReached, done)` for the events Load, Plant, Shatter, BuySeed and Action. 12 tests in [tests/Tutorial.spec.luau](../../roblox/tests/Tutorial.spec.luau) cover every task 11 criterion that can be unit-tested: the full run logs 1–8 once each; `TutorialAction` only 4 or 8 and only as the next step (8 refused cases); a purchase before step 4 logs 4 then 5; the 8 s grow, forced Glowing and +50 only in an active tutorial and only on the first crystal / 3rd plant / step-2 shatter; skip rule; no input mutation; no `require`.
  - **[TutorialService.luau](../../roblox/src/server/Services/TutorialService.luau):** keeps `Tutorial.Step/Done` through `DataService:GetData` only, logs `LogOnboardingFunnelStepEvent` once per reached step, handles `TutorialAction`. An idempotent `ensureStarted` (skip an old profile, or reach step 1) runs at every entry point, so it doesn't matter whether `PlotService` or `TutorialService` hears `ProfileLoaded` first. It changes data only and never syncs, except on its own remote and when the first load changes something.
  - **Server integrations:** `CrystalService` asks for the grow override and forced mutation **before** storing the crystal, reports `Plant` after it; on a shatter the bonus is a **second `AddCoins(50, "Onboarding", "TutorialBonus")` right after the shatter coins**, and `Shatter` is reported after the announcement (step 6b), all inside the batch 3 order, one `StateSync` per request. `ShatterResult` gains `bonusCoins` and `seedId`. The Studio top-up runs only when the tutorial isn't active. `ShopService` reports `BuySeed` before its sync. `SettingsService` saves `SetSetting("Music", bool)` (sync only on change) and ignores `"AutoShatter"` until batch 5. `Main.server`: TutorialService after SettingsService (12 services).
  - **Mistake caught:** a `stylua src` run reformatted the vendored `ProfileStore.luau`; restored from git at once (`git checkout`), no other change. The Vendor folder must stay excluded (README).
  - Tests **178 passed, 0 failed** (166 + 12); StyLua clean; `rojo build` succeeds.

- **Task 12 done (2026-11-21, DeepSeek Flash; the job stopped on its token budget after writing the whole file and the `Main.client` entry, before its own checks; nothing was missing, so no retry was needed; accepted with fixes):** [TutorialController.luau](../../roblox/src/client/Controllers/TutorialController.luau).
  - Re-derives everything from `snapshot.Tutorial` (so a rejoin just works): the HUD lock (`SetLocked`), the world-tap filter (`TapController:SetAllowed`), a gold beam from the character to the target pedestal, a world bubble on it, a screen hint next to a HUD button or Shop card with a pulsing gold outline, the "+50 bonus!" and "Lucky! …" popups, the tip card ("Got it!" → `TutorialAction(8)`), `TutorialAction(4)` when the Shop opens at step 3, and the Daily panel once when the tutorial finishes during the session. Per-step table as specified; ☀ and 🔊 stay usable throughout.
  - **Review fixes (orchestrator):** (1) at step 7 the tip card appeared together with the Lucky popup (overlapping); it now waits for the popup. (2) After "Got it!" the 0.25 s loop showed the tip card again before the server's step-8 reply; no longer once step 8 is sent. (3) The beam end used the pedestal's local Y, which is horizontal on these upright cylinders (the spec's mistake); it now sets `WorldPosition` above the pedestal. (4) Found in your run: `hudButton` and `shopCard` compared `typeof(x) == "instance"`; Luau returns `"Instance"`, so both always returned nil and **"Open the Shop!", "Buy seeds!" and both gold outlines never showed**. Fixed, plus a new `Screens.spec` test that rejects `typeof(...) == "instance"` anywhere in `src` (tests **179**).
  - **A slip, no harm:** a stray `git stash -- <TutorialController>` was run while adding that test; the file is untracked, so git stashed nothing (stash list empty, file checked intact).

- **Task 13 done (2026-11-21, Haiku, accepted first time):** [MapService.luau](../../roblox/src/server/Services/MapService.luau), [UIController.luau](../../roblox/src/client/Controllers/UIController.luau), [CrystalRenderer.luau](../../roblox/src/client/Controllers/CrystalRenderer.luau). (The client start order from this task was done in task 10.)
  - **Hub stalls:** `SeedShopStall` and `UpgradeStall` in `workspace.Map.Hub`, at radius 30 and −20° / −40° from plot 1's path (the board's other side; the board stands at +30°, radius 34), each facing the spawn pad: a wooden counter, two posts, a coloured roof (green / blue) and a sign ("Seed Shop" / "Upgrades", `LightInfluence = 0`). The counter has a `ProximityPrompt` "Open" (10 studs). The stall model's attribute `OpensPanel` names the panel; UIController opens it from `ProximityPromptService.PromptTriggered` (the tutorial lock still applies).
  - **Plant prompt:** now opens the seed picker for that pedestal (`UIController:Open("SeedPicker", index)`) instead of planting the cheapest seed; it shows on every empty unlocked pedestal of your own cave, even with an empty bag (the picker then offers the Shop). The unused `lowestSeed` and Plant remote were removed.
  - Tests **179 passed**; StyLua clean; `rojo build` succeeds; Vendor untouched.

## Findings

### Task 1: outside facts (checked 2026-11-21)

Pages read through the Studio MCP doc fetcher (the ScreenInsets page shows `last_updated: 2026-11-20`).

| API | Official page | What it says | Effect on this plan |
|---|---|---|---|
| `ScreenGui.ScreenInsets`, `Enum.ScreenInsets` | [ScreenGui](https://create.roblox.com/docs/reference/engine/classes/ScreenGui.md), [ScreenInsets](https://create.roblox.com/docs/reference/engine/enums/ScreenInsets.md) | `DeviceSafeInsets` avoids device cutouts but adds **no inset for the Roblox top bar buttons**. `CoreUISafeInsets` (the default) avoids both and "is recommended for any ScreenGui that contains interactive and/or important UI elements such as buttons". | **Changes the plan (confirmed by you, 2026-11-21):** `CrystalGroveUI` uses **`CoreUISafeInsets`** with `IgnoreGuiInset = false`, not `DeviceSafeInsets`. The ☀ button already used it and was checked in the Device Simulator. |
| `ScreenGui.IgnoreGuiInset` | [ScreenGui](https://create.roblox.com/docs/reference/engine/classes/ScreenGui.md) | `false` (default) keeps `ScreenInsets` at `CoreUISafeInsets`; setting it `true` switches it to `DeviceSafeInsets`. | Leave it `false`. |
| `UISizeConstraint` | [UISizeConstraint](https://create.roblox.com/docs/reference/engine/classes/UISizeConstraint.md) | `MinSize` / `MaxSize` in pixels; the parent can't get smaller or larger. | As planned: `MinSize = 48 × 48` on every tappable element. |
| `UIScale`, `UIStroke`, `UICorner`, `UIListLayout`, `UIGridLayout` | [UIScale](https://create.roblox.com/docs/reference/engine/classes/UIScale.md), [UIStroke](https://create.roblox.com/docs/reference/engine/classes/UIStroke.md), [UICorner](https://create.roblox.com/docs/reference/engine/classes/UICorner.md), [UIListLayout](https://create.roblox.com/docs/reference/engine/classes/UIListLayout.md), [UIGridLayout](https://create.roblox.com/docs/reference/engine/classes/UIGridLayout.md) | `UIScale.Scale` (float); `UIStroke.ApplyStrokeMode` (`Contextual` = text outline, `Border` = frame outline); `UICorner.CornerRadius` (UDim; also per-corner radii); `UIListLayout.Padding` and flex options; `UIGridLayout.CellSize`, `CellPadding`. | As planned. The press effect tweens a `UIScale` to 0.95. |
| `Font.fromEnum` | [Font](https://create.roblox.com/docs/reference/engine/datatypes/Font.md) | `Font.fromEnum(Enum.Font.X)` builds a `Font` for `FontFace`; errors only on `Font.Unknown`. | As planned: `Font.fromEnum(Enum.Font.FredokaOne)`. |
| `TweenService:Create` | [TweenService](https://create.roblox.com/docs/reference/engine/classes/TweenService.md) | `Create(instance, tweenInfo, propertyTable): Tween`. | As planned. |
| `Beam` | [Beam](https://create.roblox.com/docs/reference/engine/classes/Beam.md) | Shows only when it and both `Attachment0`/`Attachment1` are descendants of `Workspace`; `Width0/1`, `TextureSpeed`, `FaceCamera`. | Tutorial arrow: one attachment in the character's root part, one on the target pedestal. |
| `Sound`, `SoundService:PlayLocalSound` | [Sound](https://create.roblox.com/docs/reference/engine/classes/Sound.md), [SoundService](https://create.roblox.com/docs/reference/engine/classes/SoundService.md), [deprecated list](https://create.roblox.com/docs/reference/engine/deprecated.md) | `Sound.SoundId`, `PlaybackSpeed` (`Pitch` is deprecated in favour of it). `PlayLocalSound(sound)` plays a local copy, carrying over `Volume` and `PlaybackSpeed`. `Sound` itself isn't deprecated. | As planned. One-shot effects use `PlayLocalSound`; the music is one looped `Sound`. |
| Audio licensing | [Audio assets](https://create.roblox.com/docs/audio/assets.md) | The Creator Store has free audio "made by Roblox and the Roblox community", including licensed sound effects and music from audio partners. | Task 2: pick Roblox-published audio only. |
| Tap in the world | [UserInputService](https://create.roblox.com/docs/reference/engine/classes/UserInputService.md), [Camera](https://create.roblox.com/docs/reference/engine/classes/Camera.md) | `TouchTapInWorld(position, processedByUI)` fires only for taps not on a `GuiObject`; the page doesn't say which coordinate system `position` uses. `ViewportPointToRay` uses device-safe coordinates (origin at the top left of the top bar); `ScreenPointToRay` accounts for the GUI inset. | Touch: `TouchTapInWorld`; mouse: `InputBegan` with `MouseButton1` and `gameProcessed == false`; then a ray and `workspace:Raycast`. **Which ray function matches the tap position is checked in Studio in task 10** (a mismatch would be off by the top-bar height). |

### Task 1: emoji in TextLabels (Studio, Device Simulator, 2026-11-21)

A temporary `ScreenGui` in `StarterGui` (Edit mode, Galaxy S25 Ultra landscape, FredokaOne 24–28 px) showed these labels; it was deleted afterwards.

- **Render in colour:** 💰 🏆 🏠 🛒 ⬆️ 📖 🎁 🎯 ⚡ 🎲 🔊 🔇 ☀ 🍀 ⏱, and `×` `—` `…` `−`.
- **Don't render:** `✕` (U+2715) and `⨯` (blank). `✖` comes out black (hard to see on the dark panel); `❌` is red.
- **Result:** Decision 1 (emoji icons) stands. **The close button uses a bold "X"** in FredokaOne instead of ✕.
- **Not checked yet:** this is Studio on Windows. iOS and Android draw emoji with their own fonts, so the real-phone check in task 14 must look at the icons too.

### Task 10: Studio Play Solo (2026-11-21)

Place "Crystal Grove DEV", Rojo connected (all 10 controllers had the same size in Studio as on disk), Device Simulator Galaxy S25 Ultra landscape. Your DEV profile (sessions 34–35). A client-side logger recorded panels, remotes and bubbles; you did the taps.

| # | Check | Result |
|---|---|---|
| — | Start | **Passed.** `CrystalGroveUI` with the 10 screens and the backdrop in the planned z-order; ☀ inside `Hud.BrightnessSlot`, no old `BrightnessGui`; coins "💰 954", weekly best "🏆 2.0 ct", surge countdown, music playing. Output: no errors, only the known `rbxassetid://203785492` warning. Screenshot: both button grids clear of the thumbstick and the jump button. |
| 1 | Tap an empty pedestal → seed picker → Quartz | **Passed.** Picker opened and closed; Quartz 5 → 4; crystal planted. |
| 2 | Tap a growing crystal → countdown bubble | **Failed, then fixed.** No bubble was logged in your run. A tap sent through TapController's own code at the pedestal's screen position (`WorldToScreenPoint` → `ScreenPointToRay`) hit pedestal 1 and created the bubble ("Ready in 0:18"), but it wasn't visible: at 7 studs it sat behind the HUD, and `AlwaysOnTop` bubbles never showed in a capture. Fixed (Progress, task 10); a test bubble at the new position shows clearly in front of the crystal. **Your re-check on the new code is still to do** (task 14). |
| 3 | Tap a ready crystal → shatter, result card, sounds | **Passed.** `ShatterResult` for pedestal 1, +17 coins; you saw the card and heard the sounds. |
| 4 | Panels open one at a time; tapping outside closes | **Passed.** Shop, Upgrades, Codex, Odds opened and closed in turn. **Bug found:** the backdrop tap that closed the Codex also opened the seed picker; fixed, then re-checked: 3 backdrop taps closed the Codex and the picker stayed shut. |
| 5 | Shop → Buy Quartz | **Passed on the second run.** The first run logged no purchase. On the re-run the logger saw 2 taps on Buy: coins 1,238 → 1,228 → 1,218, Quartz 4 → 5 → 6. The counter showed "1.2K" throughout (`Format.compact` truncates), which is why a 10-coin change wasn't visible. Before the retry, the Buy button was checked as the topmost tappable object at its centre (69 × 48, enabled). |
| 6 | Daily → Claim | **Passed.** `Toast.DailyClaimed`, coins +250 (Day 2), dot gone. |
| 7 | 🔊 toggle | **Passed on the client** (music stopped and restarted, label shown). The server answered `[Remote] rejected SetSetting … no handler`: expected, the Music handler is task 11. |
| 8 | ☀ cycles the lighting | **Passed.** 9 taps, `Settings.Brightness` cycled Dark → Normal → Bright through `StateSync`. |
| 9 | My Cave | **Passed** (your check; client only, nothing to log). |

**Not checked yet:** `SetLocked` (the command bar loads its own module copies, so the live UIController can't be called from it; checked with the tutorial in task 12); tapping another player's crystal (2-player test, task 14); which ray function matches a real phone's touch position (the code path is consistent with `WorldToScreenPoint`; the real phone in task 14 decides).

**Dev data changed:** your DEV profile got 2 Quartz bought, Day 2 of the streak claimed, and a few Quartz planted and shattered (coins about 1.2K).

### Task 11: Studio Play Solo (2026-11-21)

Remotes fired from the client command bar through the MCP; results read from the client's `StateSync`/`ShatterResult` and the server Output. No steps from you.

**(a) Your DEV profile:**

| Check | Result |
|---|---|
| Server start | **Passed.** `[Server] Started 12 services`, no errors. |
| Existing profile skips the tutorial | **Passed.** Output `existing profile, tutorial skipped`; snapshot `Tutorial = 0 / Done = true`; no funnel event. The Studio top-up still ran (Quartz 4 → 5) because the tutorial is done. |
| `SetSetting("Music", false/true)` saved | **Passed.** `Settings.Music` false, then true, each with a sync. |
| `SetSetting("AutoShatter", true)` refused | **Passed.** `AutoShatter` stayed false, no sync. |
| `TutorialAction(4)` on a finished tutorial | **Passed.** Refused, step unchanged. |

**(b) Fresh profile** (Decision 3: `Config.Game.ProfileStoreName` temporarily `PlayerData_Test1`, **reverted right after the run**, checked on disk and in Studio):

| Step | Result |
|---|---|
| Load | **Passed.** Step 1 `Spawned`, coins 0, bag `{Quartz = 1}`, no top-up. |
| `TutorialAction(4)` and `(8)` before their time | **Passed.** Both refused at step 1. |
| First plant | **Passed.** Step 2; `ReadyAt − PlantedAt` = **8 s**. |
| First shatter | **Passed.** Coins 0 → **65** = 15 + 50; payload `bonusCoins = 50`, `seedId = "Quartz"`; two economy events; step 3. |
| `TutorialAction(4)`, then again | **Passed.** Step 4; the repeat refused. |
| Buy 2 Quartz (qty 1, twice) | **Passed.** Step 5 on the first purchase; coins 65 → 45. |
| Plants 2 and 3 | **Passed.** Plant 2 `None` (20 s, no override), plant 3 **`Glowing`** (forced) → step 6. |
| Shatters | **Passed.** Plant 2 (None): still step 6, no bonus. Plant 3 (Glowing, 41 coins = ×2): step 7. |
| `TutorialAction(8)` | **Passed.** Step 8, `Done = true`. |
| Funnel | **Passed.** Output shows `reached step 1 … 8` once each, in order, each with `LogOnboardingFunnelStepEvent`. |

**Not checked yet:** a rejoin mid-tutorial (task 12 / 14) and the timing of a real run with the client tutorial (task 14).

**Dev data changed:** your DEV profile is now `Tutorial.Done = true` (by the skip rule) and Music was toggled off and on (ends on). A new store **`PlayerData_Test1`** now holds a finished tutorial profile for your account; the next fresh-profile test needs another name (for example `PlayerData_Test2`).

### Task 12: Studio Play Solo, fresh profiles (2026-11-21)

Decision 3: `Config.Game.ProfileStoreName` was temporarily `PlayerData_Test2`, then `PlayerData_Test3` (a profile that hadn't passed step 3 was needed after the fix), and **reverted to `PlayerData` afterwards** (identical to the committed file; checked in Studio). Device Simulator Galaxy S25 Ultra landscape; you played by touch; a client logger and the server Output recorded the run.

| # | Check | Result |
|---|---|---|
| 1 | Step 1 on join | **Passed.** All 8 HUD buttons greyed (🔊 and ☀ usable); bubble "Tap the pedestal to plant!" on pedestal 1; gold beam from the character (screenshot). |
| 2 | Plant → "Watch it grow…" → "Tap your crystal!" → shatter | **Passed** (your run, store Test2): 8 s grow, 17 + 50 coins, "+50 bonus!" popup, Shop button enabled at step 3. |
| 3 | Step 3: gold outline on Shop + "Open the Shop!" | **Failed in your run** (the `"instance"` bug), **then passed**: on store Test3, steps 1–3 driven through the remotes, the hint "Open the Shop!" sat below the Shop button, the outline was on it, and only Shop was enabled (screenshot). |
| 4 | Step 4: "Buy seeds!" above the Quartz card | **Failed in your first run** (same bug; step 4 took 108 s there without the hint), **then passed** in your second run ("Buy seeds showed"). |
| 5 | Rejoin mid-tutorial | **Passed.** Your first attempt didn't rejoin (Output showed one load; the run just continued), and the second attempt started a **server-only** test (the test-mode dropdown was on "Server…", no player). The orchestrator then started Play Solo: `sessions = 2`, coins 45, 2 Quartz, still step 5: only My Cave enabled, "Plant them!" on pedestal 1, beam on; no step logged twice, no Studio top-up. |
| 6 | Plants 2–3, Glowing, Lucky, tip, finish | **Passed** (your check + Output): step 6 on the 3rd plant, the Glowing crystal (×2) → step 7, "Lucky! GLOWING ×2" then the tip card, "Got it!" → step 8 `TutorialDone`; Daily opened. Afterwards all 8 HUD buttons enabled, no hint/tip/popup left, beam off. Your first run also showed the popup, the tip 2.7 s later, and the Daily panel. |
| 7 | Funnel | **Passed.** Each run logged steps once each, in order (Test2: 1–8 in one session; Test3: 1–5, then 6–8 after the rejoin). |

**Not checked yet:** the timed run of 75 s or less (your first run took about 267 s with long pauses for instructions and the missing hint; task 14 times a clean run); the real phone.

**Dev data changed:** stores `PlayerData_Test2` and `PlayerData_Test3` hold finished tutorial profiles for your account. The next fresh-profile test needs a new name (for example `PlayerData_Test4`).

### Task 13: Studio Play Solo (2026-11-21)

Your DEV profile, Device Simulator Galaxy S25 Ultra landscape.

| # | Check | Result |
|---|---|---|
| — | Stalls built and placed | **Passed.** Server: Seed Shop at (−10.3, 28.2), Upgrades at (−19.3, 23.0), both radius 30, front facing the spawn pad (dot 1.00); 12.0 / 19.3 studs from the spawn, **27.8 / 37.3 studs from the leaderboard board** (no overlap); signs "Seed Shop" / "Upgrades"; prompts "Open". A capture from above the spawn shows the board, the green Seed Shop stall with its sign and the blue Upgrades stall. |
| 1 | Seed Shop prompt opens the Shop | **Passed** (your check). |
| 2 | Upgrades prompt opens Upgrades | **Passed** (your check). |
| 3 | A pedestal's Plant prompt opens the seed picker | **Passed** (your check). Output confirms nothing was planted directly (Quartz stayed 5); no errors. |

### Task 14: timed new-player tutorial, Device Simulator (2026-11-21)

Fresh profile (Decision 3: store temporarily `PlayerData_Test4`, **reverted afterwards**, file identical to the committed one, checked in Studio). Galaxy S25 Ultra landscape. You played by touch without instructions; a client logger timed the run. The profile loaded before the logger connected, so the clock starts at your **first tap** (you started when you read the message, not at join).

| Time | Event |
|---|---|
| 0.0 s | First tap: seed picker on pedestal 1 |
| 3.7 s | Planted → step 2 |
| 13.7 s | Shatter (+50 bonus) → step 3. This first crystal rolled **Glowing by chance** (a surge was running). |
| 18.5 s | Shop opened → step 4 |
| 25.5 s | First purchase → step 5 |
| 27.7 s | Shop closed |
| 28.8–38.5 s | Picker opened 3 times for 2 plants (one false start) → step 6 at 38.6 s |
| 59.6 s | Forced-Glowing crystal shattered → step 7 (most of this stretch is its 20 s grow) |
| 62.2 s | Tip card |
| **64.2 s** | **"Got it!" → step 8, Daily opened** |

- **Result: passed.** 64.2 s from the first tap; with the MVP's ~5 s to read the first bubble, about 69 s, under the 75 s target. Funnel steps 1–8 each logged once.
- **Finding (your screenshot at step 6):** the tutorial's world bubble ("Watch it grow…") for a pedestal on the left of the screen sits partly behind the HUD's left button grid (still readable here), and a crystal's own "READY!" label can be hidden behind it too. Not fixed; see Outcome → open items.
- **Finding:** the Daily and Goals red dots stay visible on their locked buttons during the tutorial.

**Dev data changed:** store `PlayerData_Test4` holds a finished tutorial profile for your account.

### Task 14: Device Simulator, small and mid-size phones (2026-11-21)

Play Solo with your DEV profile (tutorial done). The Simulator has **no iPhone SE**; the **iPhone 7 (667 × 375)** has the same screen as the iPhone SE 2nd/3rd generation and was used instead. Mid-size Android: **Samsung Galaxy A06 (800 × 360)**. Measured on the client: every HUD element against every other one and against the jump button and the thumbstick; every panel made visible in turn, checking for content below the panel's bottom (outside scrolling lists) and buttons under 48 px.

| Device (viewport) | HUD | Panels | Result |
|---|---|---|---|
| iPhone 7 (666 × 374) | No overlaps (jump 571–641 × 226–296, thumbstick 29–103 × 223–297 clear); coin pill 20 px from Shop, 26 px from the weekly best | All 7 fit, no button under 48 px, close buttons 48 × 48 | **Passed.** You scrolled the Shop to Voidheart and the Codex to its last row by touch. Screenshot checked. |
| Galaxy A06 (705 × 338) | No overlaps; gaps 39 / 45 px | **Daily overflowed by 20 px** when today was already claimed: the "Come back tomorrow!" line (hidden when the day is claimable, which is why the task 8 check missed it) | **Failed, then fixed and passed:** day tiles 110 → 90 px tall (their labels use 74 px), Claim 56 → 52 px (still ≥ 48). Re-measured in the claimed state: overflow 0; screenshot shows "Claimed" and the line inside the panel. |

The Galaxy S25 Ultra (685 × 280 safe area) was checked in tasks 4–13.

### Task 14: Studio local server, 2 players (2026-11-21)

Server and 2 clients started by you (Player1 = `Player_-1`, Player2 = `Player_-2`, both with earlier shatters). Calls fired from each client's command bar through the MCP; the debug announcement from the server.

| # | Check | Result |
|---|---|---|
| — | Join | **Passed.** Both: `existing profile, tutorial skipped`, UI built, HUD unlocked; `[Social] friends Player2 & Player1 = false`; no errors. |
| 1 | An announcement reaches both players, gold | **Passed.** `DebugAnnounce` → both clients' toast stacks got "Player1 found a Colossal Prismatic Quartz!" with the gold border (the attribute reset itself). |
| 2 | A player's own toast stays private | **Passed.** Player1 `BuySeed("Voidheart", 1)` → "Shatter a Starfire Opal to unlock" on Player1 only; Player2's stack still held only the announcement. |
| 3 | A tap on another player's crystal does nothing | **Passed.** Player2 planted 2 Quartz in `Plot_2`. Once ripe, Player1 was moved into Player2's cave; the touch ray TapController casts from the crystal's screen point hit `Pedestal_1` of `Plot_2` (owner −2). A tap sent through Player1's TapController produced no `ShatterResult` and the crystal stayed. Then Player1's direct `Shatter(1)` and `ShatterAll` only touched Player1's own (empty) pedestals: Player2's crystals stayed. Player2's own `ShatterAll` then shattered both (2 results). |

**Dev data changed:** `Player_-2` planted and shattered 2 Quartz; both test profiles were marked tutorial-done by the skip rule; brightness toggled (ends Normal).

**Your decision (2026-11-21): no tutorial run on the real phone.** Your DEV profile has finished the tutorial, and a phone run would need a temporary store name in the published build plus a second publish. The tutorial stays verified in Studio only (Device Simulator, timed run and rejoin); recorded under Outcome → not verified.

**Before publishing (2026-11-21):** tests 179/179, StyLua clean, `rojo build` succeeds, Vendor untouched, `Remotes` still 17 entries. Personal-data scan of the whole batch diff (email, name, Roblox user ID and username, `C:\Users` paths, keys): clean; the only hits were variable names such as `bubbleToken`.

### Task 14: published DEV experience, your phone (2026-11-21)

You ended the test sessions, published, checked File → Version History and joined from the DEV place link. All results below are **your checks** (the orchestrator can't see the phone or the live server's log).

| Check | Result |
|---|---|
| New version running (two-grid HUD) | **Passed.** |
| Emoji icons render (💰 🏠 🛒 ⬆️ 📖 🎁 🎯 ⚡ 🎲 🔊 ☀) | **Passed.** |
| Tap a growing crystal → "Ready in 0:xx" bubble in front of it | **Passed** (also the re-check of the task 10 bubble fix). |
| Tap a ready crystal → shatter and result card | **Passed.** |
| 🔊 music toggle | **Passed.** |
| Sounds (click, shatter, coin, ready, music) | **Passed:** "sounds are fine". |

## Outcome (2026-11-21)

- **Built as specified**, with these differences (details in Progress and Findings):
  - **Confirmed changes A–F** (from the batch 3 and cave-brightness work): ☀ in a HUD slot; old profiles skip the tutorial; plant count = shatters + crystals on pedestals; the +50 as a separate `Onboarding` economy event with `bonusCoins` in `ShatterResult`; pure `Logic/Tutorial.luau`; `Strings.message` for toasts and a parametrised "Lucky! {mutation} ×{mult}".
  - **`CoreUISafeInsets`** instead of `DeviceSafeInsets` (the docs say the latter doesn't avoid the top bar).
  - **Two 2 × 2 HUD grids** instead of left/right columns (four stacked buttons would reach the thumbstick and the jump button); approved by you after it was built.
  - **Close buttons use a bold "X"**: "✕" doesn't render.
  - **Sounds picked by the orchestrator** at your request: 7 assets whose creator is "Roblox"; you approved how they sound on the phone.
  - **Contract additions:** `ctx.Player`, `ctx.Now()`, `Logic.Growth/WeekId`, `Config.Game/Sounds`, `Sounds:SetMusicFromTap`; `Theme.Icons`, `Theme.rgb`; `Components.setEnabled/setClickSound` and a `TextSize` cap; `Hud.Buttons/BrightnessSlot/MonetizationSlot`, `Shop.Cards`, `Toasts.Push`; UIController `SetLocked(locked, allowedButton?)`, `PanelOpened/PanelClosed`, `WaitUntilReady`; TapController `SetAllowed`; `ShatterResult.seedId`. Extra strings: "Friends +n%" in the HUD and a few panel hint lines.
  - **Task moves:** the client start order was done in task 10 (not 13), so Play tests were possible; task 10 ran as two jobs.
- **Bugs found and fixed** (all before the final checks):
  - **In review:** `.Font` given a `Font` datatype (Components); weekly-best pill misplaced and uneven button text (Hud); `PanelClosed` not fired on panel replacement; tip card overlapping the Lucky popup and reappearing after "Got it!"; beam end beside the pedestal (a spec mistake).
  - **In Studio checks:** a backdrop tap also tapping the world; an invisible tap bubble (behind the HUD / `AlwaysOnTop`); `typeof(x) == "instance"` (always false) hiding the Shop hint and outlines; panels too tall for a 280 px phone (Goals, Daily, SeedPicker; Daily again in the claimed state on the A06); "Emerald ×1" breaking mid-word; a HUD dot drawing over panels (`ZIndexBehavior`).
- **Who did what:**
  - **DeepSeek Flash:** tasks 3, 4–9 (6 jobs), 10 (2 jobs) and 12. Accepted first time: 5, 6, 7, 9, 10B. With orchestrator fixes: 3, 4, 8, 10A, 12. Two jobs (4, 12) stopped on their token budget after writing their files; nothing was missing, so no retry was needed (your rule: retry with DeepSeek when work is missing). Every recovery journal was checked and acknowledged.
  - **Haiku:** task 13, accepted first time.
  - **Orchestrator:** tasks 0, 1, 2 (at your request), 11 and 14, plus the review fixes above.
  - Nothing went to DeepSeek Pro.
- **Tests:** `lune run tests` gives **179 passed, 0 failed** (154 existing + 25 new: Format 1, Config 2, Theme 6, Screens 4, Tutorial 12). `stylua --check` is clean (Vendor skipped), and `rojo build` succeeds.
- **Each place checked:**

  | Where | What | Result |
  |---|---|---|
  | Studio Edit mode (fake ctx) | Every screen rendered with sample data; panels at the phone's real 685 × 280 size | Passed after the layout fixes |
  | Studio Play Solo | Wiring, taps, panels, Buy, Daily, music, brightness, My Cave; server tutorial on a fresh profile; tutorial by touch with a rejoin; stalls and the Plant prompt | All passed (bugs fixed on the way) |
  | Timed new-player run (Device Simulator) | Fresh profile, no instructions | **64.2 s** from the first tap (~69 s with reading time), under 75 s |
  | Device Simulator: iPhone 7 (= iPhone SE screen), Galaxy A06, Galaxy S25 Ultra | No overlaps with each other or the touch controls; panels fit; Shop and Codex scroll | Passed (Daily fixed on the A06) |
  | Studio local server, 2 players | Announcement to both, private toasts, no effect on another player's crystals | Passed |
  | Published DEV experience, your phone | New version, emoji, tap bubble, tap-to-shatter, music, sounds | Passed (your checks) |

- **Not verified:**
  - **The tutorial on a real phone** (your decision): verified in the Device Simulator only.
  - **`SetLocked` called directly** (the command bar loads its own module copies): checked only through the tutorial, where it locked and unlocked the HUD as designed.
  - **Which ray function matches a real phone's touch position** wasn't measured; the phone checks (tap bubble, tap-to-shatter) show it works in practice.
  - **The live server's log** after publishing (the phone checks are yours).
- **Open items (not fixed in this batch):**
  - The tutorial's world bubble and a crystal's own countdown / "READY!" label can sit behind the HUD's top grids for pedestals near the screen's top corners (seen on the S25 Ultra at step 6; still readable). Candidate for the batch 6 polish pass (lower offset or camera-aware placement).
  - The Daily and Goals dots stay visible on their locked buttons during the tutorial.
  - Above 1K coins, a small coin change isn't visible on the counter ("1.2K"); by design of `Format.compact`.
- **Leftovers:**
  - **Dev data:** your DEV profile is tutorial-done (skip rule), with Day 2 claimed, about 1.2K coins and a few plants; `Player_-1` and `Player_-2` were used (both tutorial-done). Test stores **`PlayerData_Test1` to `PlayerData_Test4`** hold finished tutorial profiles for your account; the next fresh-profile test needs `PlayerData_Test5`. `Config.Game.ProfileStoreName` is back to `PlayerData` (identical to the committed file).
  - **The DEV experience is published with batch 4.**
  - **Git:** committed as `1d7b489` on `batch-4-ui-onboarding` and pushed (2026-11-21), with this status update as `ceeb4bb`. Pull request #4 into `batch-1-setup` was merged on 2026-11-22.
  - **Still running:** the Rojo server on port 34872. The Device Simulator is on the Galaxy A06.
  - **`rojo build` output** is in the session scratchpad, outside the repo.
- **Lessons:**
  - **`typeof` returns `"Instance"`** (capital I); a lowercase compare silently fails. Now a test.
  - **An `AlwaysOnTop` billboard didn't show in Studio captures**, and high billboards end up behind the HUD at close range; `StudsOffset` Z (toward the camera) puts a bubble in front of the crystal instead.
  - **Check panels at the real safe-area size and in every state** (claimed / empty / max), not only the default one.
  - **A ScreenGui made by script defaults to `ZIndexBehavior = Global`;** set `Sibling` explicitly.
  - **Never run StyLua on all of `src`** (it reformats the vendored ProfileStore); name the folders, or use `stylua src tests --glob '!**/Vendor/**'`.
  - **The test-mode dropdown can be left on "Server…"**, which starts a server with no player; check it before pressing Play, or let the orchestrator start Play.

