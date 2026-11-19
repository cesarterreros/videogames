# Decision records

This folder keeps the specification of every feature in this project, one dated file per decision: `YYYY-MM-DD-short-title.md`. Each record is written and approved before coding and gets an Outcome section after verification. The general format comes from the `write-spec` skill; this file holds this project's own conventions.

The project is a Roblox experience, **Crystal Grove**, built with Rojo + VS Code. Source lives in [roblox/](../../roblox/).

## Build and tests

- **Build / sync:** `rojo serve` from `roblox/` while Roblox Studio is open with the Rojo plugin connected. `rojo build -o CrystalGrove.rbxlx` produces a place file.
- **Tests:** `lune run tests` from `roblox/`. Only **pure Luau modules** (game math, config validation, data migration) are unit-tested this way: growth timing, rarity and size rolls, prices, leaderboard week IDs, profile migration. Anything that touches Roblox services is checked manually in Studio.
- **Rule:** game math goes into pure modules under `src/shared/Logic/` so it can be tested with Lune.

## Where changes are checked

In this order:

1. **Studio Play Solo**: the basic flow works, no errors in Output.
2. **Studio local server with 2 players** (Test tab → Clients and Servers): replication, plot ownership, and that one player cannot affect another's plot.
3. **Studio Device Emulator**, phone profile (for example iPhone SE and a mid-size Android) in landscape: every button reachable with a thumb, text readable, no UI overlap.
4. **Published private test place on a real phone**: frame rate stays playable (target ≥ 30 FPS), touch controls work.

## Stored data

- **Separate dev experience:** all development and testing use a separate Roblox experience (its own universe) so test data never touches live player data. Studio API access to DataStores is enabled only in the dev experience.
- **Schema version:** every player profile has a `Version` integer. Migrations are pure functions `migrate(profile) -> profile` in `src/shared/Logic/`, unit-tested with Lune, and run on the dev experience before the live one.
- **Backup before a change to stored data:** before a migration ships, export a sample of dev profiles (via a dev-only admin command or Open Cloud) and record the count of profiles checked before and after.

## Delegation

Skill defaults: Haiku for small, fully specified edits; DeepSeek Flash for standard implementation and tests; DeepSeek Pro only for the hardest cross-file task. DataStore/session-locking code and anything security-critical (remote validation, receipt processing) stays with the orchestrator.

### Delegation lessons (from batch 1)

- **DeepSeek's shell is `cmd.exe`, not bash.** Give it this command for tests: `set PATH=C:\Users\<you>\.rokit\bin;%PATH% && cd /d C:\Projects\videogames\roblox && lune run tests`. Find `<you>` locally; don't write it in the records.
- **Tell DeepSeek to write each file in one Write call.** Batch 1's test-runner job ran out of turns (50) doing stub-then-small-Edits.
- **One DeepSeek job at a time per workspace.** After each job: `get_deepseek_recovery`, review the files, run the tests, then `acknowledge_deepseek_mutations` with the exact IDs.
- **Haiku subagents** do well with fully specified files (exact content or exact tables). Give them the contract text itself, not a pointer to a record.
- **Test style:** `expect(x):toBe(y)` (colon calls), `expect(x).never:toBe(y)`. "No require" checks must search for a call (`require%s*[%(\"']`), not the bare word, because comments may mention it.

## Starting a new session

Each batch is implemented in its own Claude session. Start every session like this:

1. **Read, in order:** this README; the batch's own record (its **Context for a new session** section lists everything else to read); then the **Findings**, **Progress** and **Outcome** sections of earlier batch records, which may correct their plans.
2. **Environment (Windows, Git Bash):**
   - Tools: `export PATH="$HOME/.rokit/bin:$PATH"` (Rojo 7.7.1, Lune 0.11.1, StyLua 2.6.0, pinned in `roblox/rokit.toml`).
   - Tests: `cd roblox && lune run tests`.
   - Format: `stylua src tests` (skip `src/server/Vendor`).
   - Build check: `rojo build -o <scratchpad>/test.rbxlx`.
   - Sync: run `rojo serve` in the background; you then click **Connect** in Studio's Rojo panel (the plugin is already installed).
   - Studio: the experience is **"Crystal Grove DEV"** (separate dev universe, Studio API access on). In this Studio version, Output is under **Window → Output**.
3. **Git:** branch from the previous batch's branch as `batch-N-short-name`. Commit only when the user asks. Before committing, scan for personal data (email, name, Roblox user ID or username, `C:\Users\…` paths, keys and tokens).
4. **Workflow rules from the user:** no code until the batch plan is approved. A plan's `Status:` line says whether it is approved; if a finding changes an approved plan, re-confirm with the user before coding. End each step with one focused question. Results go in the record (Findings, Progress, Outcome); report only verified checks as passed.

## Extra rules

- **No copyrighted material:** no names, characters, art, music, or UI that copies another game. Only self-made or Roblox-licensed assets.
- **Server authority:** the client never decides coins, rolls, timers, or purchases. Every RemoteEvent handler validates its arguments' types and ranges and rate-limits per player.
- **Mobile first:** every UI change is checked on the phone emulator profile before it counts as done.
- **Official docs only** for Roblox API names and limits; record the URL and the date checked.
