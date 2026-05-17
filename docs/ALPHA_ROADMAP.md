# Alpha Release Roadmap — Project_TCGEX

> **Authoritative roadmap.** Future sessions should consult this document
> before starting work that touches Alpha scope. Update it when a
> workstream lands or scope changes — do not let it go stale.
>
> Last revised: 2026-05-17 (branch `version_0.0.4.4`).
> Source plan: `.claude/plans/look-over-the-previous-keen-floyd.md`.

---

## 1. Alpha Definition

An Alpha Release of Project_TCGEX must deliver:

1. **Three card sets fully coded** — DR, RS, SS with complete `effect_key` / `attack_data` for every non-energy card, **and** GUT test coverage for Tier 1, Tier 2, and Tier 3 attacks.
2. **Opening town blocked out** in the overworld with playable transitions.
3. **NPC enemy logic** — generic heuristic AI **plus per-deck overrides**, with ≥3 pre-built opponent decks.
4. **Online mode** — LAN / direct-IP via `ENetMultiplayerPeer` (no matchmaking, no relay).
5. **Deckbuilder** — already functional; polish to alpha quality.
6. **Card shop** — already functional; integrate into overworld + finish progression loop.
7. **Animated player character** — rigged trainer extracted from a GameCube ISO using the Colosseum/XD pipeline in [CLAUDE.md](../CLAUDE.md), with idle + walk animations.
8. **Animated idle NPCs** — ≥3 NPCs in the opening town with idle animations (also GC-extracted).

Anything **not** in this list is explicitly out-of-scope for Alpha (see §6).

---

## 2. Prior-Plan Audit

Snapshot of how plans in `.claude/plans/` have actually landed.

| Plan file | Goal | Status | Alpha disposition |
|---|---|---|---|
| `goofy-enchanting-sedgewick.md` | Tier 2/3 attack handlers + tests | **Partial** — handlers exist at [`scenes/match/effect_handlers.gd:354`](../scenes/match/effect_handlers.gd); tests missing | Folded into **W1** |
| `i-d-like-to-do-fluffy-octopus.md` | main.gd split + lazy art + multi-state arch | **Phase 1 ✅, Phase 2 ⛔ abandoned, Phase 3 ✅** | Deprecate Phase 2 — lazy art deferred post-Alpha |
| `just-for-fun-i-m-smooth-naur.md` | Eeveelutions niche test deck | **Abandoned** | Dropped — superseded by **W4** opponent decks |
| `please-continue-with-the-curried-pond.md` | Tier 1 attack rewrite | **Done** | No action |
| `please-do-a-review-cryptic-dewdrop.md` | Roadmap review (reference doc) | **Reference only** | Inputs absorbed here |
| `snoopy-hugging-castle.md` | Retreat/discard dialog polish + remove Modify Bench | **Partial** — dialogs wired, polish missing | Folded into **W7** |
| `we-recently-created-a-radiant-hopcroft.md` | 14-step async attack resolver | **Skeleton only** | **Parked behind a feature flag.** Too risky to mid-flight; sync handlers remain primary through Alpha |
| `i-m-happy-to-tackle-quirky-moler.md` | Overworld phase plan (CLAUDE.md references it) | **File missing** | Either recreate as appendix or remove the CLAUDE.md link |

### Current code baseline (verified 2026-05-17)

- **Cards:** 309 across DR (100) / RS (109) / SS (100). ~24 non-energy cards missing `effect_key`. CardDatabase API at [`autoload/card_database.gd`](../autoload/card_database.gd).
- **Overworld:** [`scenes/overworld/maps/starter_town.tscn`](../scenes/overworld/maps/starter_town.tscn) is a 200×200 safety floor + one shrine + lilypad + 2 spawns. No buildings or NPCs. [`test_field.tscn`](../scenes/overworld/maps/test_field.tscn) is a 30×30 tan plane.
- **Player:** [`scenes/overworld/player/player.tscn`](../scenes/overworld/player/player.tscn) is a brown capsule. No rig, no AnimationPlayer.
- **Animations:** none in any project scene. Only rigged asset to date: nothing — `lilypad_01.glb` is static.
- **Match flow:** main menu → `match.tscn` → SetupManager. Opponent is hotseat-only; CPU not implemented.
- **Networking:** [`scripts/net/match_authority.gd`](../scripts/net/match_authority.gd) is a 109-line local-only stub.
- **Shop + progression:** **Already shipped** in commit `e2179ca` (0.0.4.3). PlayerProfile, PackCatalog, PackOpener, pack_opening scene, sellback, dev coin grant.
- **Deckbuilder:** Functional at [`scenes/deck_builder/deck_builder.gd`](../scenes/deck_builder/deck_builder.gd).
- **Main menu:** Exposes Match, Overworld, Deck Builder, Collection, Shop, Mini Game 1 (WIP). Needs **LAN Match** added by **W6**.

---

## 3. Workstreams

Each workstream is self-contained enough to be picked up in a fresh session.

### W1 — Card coverage to "fully coded + tested"

- Audit `data/cards/{DR,RS,SS}/*.json`; fill missing `effect_key` / `attack_data`. Skip energy cards (legitimately keyless).
- Author `tests/test_tier2_attacks.gd` covering Tier 2 handlers in [`scenes/match/effect_handlers.gd`](../scenes/match/effect_handlers.gd).
- Author `tests/test_tier3_attacks.gd` covering Tier 3 (status, coin flip, conditional damage).
- Use [`tests/test_tier1_attacks.gd`](../tests/test_tier1_attacks.gd) as the template.
- Run via godot-ai MCP `test_run`; ship green.

### W2 — Opening town blockout

- Add building footprints (PokéCenter, Shop, Player home), boundary walls on layer `ow_world`, path StaticBodies.
- Extract 2–3 building meshes via the CLAUDE.md asset pipeline → `assets/models/overworld/buildings/`.
- Place NPC markers (Area3D on layer `ow_interact`) where **W5** will spawn NPCs.
- Add a second exit to test_field for a "route" feel.
- Verify transitions through [`autoload/overworld/world_manager.gd`](../autoload/overworld/world_manager.gd).

### W3 — Animated player character (GC-extracted)

Follow the **exact** pipeline in CLAUDE.md (Dolphin → `.fsys` extract → Blender StarsMmd addon → glTF Binary, Selected Objects, +Y Up).

- Extract Wes or Michael (XD) — full rigs with idle/walk.
- Save to `assets/models/overworld/characters/player_trainer.glb`. Commit `.glb` + any `_tex_<hash>.png` sidecars.
- Replace the capsule in `player.tscn` with the imported PackedScene. Expect ~0.3 scale tune.
- New `scenes/overworld/player/player_animation.gd`:
  - `idle` clip when `velocity.length() < 0.1`.
  - `walk` clip otherwise.
  - Reads velocity from the existing controller — do not duplicate input handling.
- Keep the existing CollisionShape3D capsule for physics; animation drives the mesh only.

### W4 — NPC enemy AI

- New `scripts/ai/opponent_ai.gd` with `decide_action(match_state) -> Action`.
- **Heuristic baseline:** enumerate legal actions, score by damage potential, energy efficiency, board threat.
- **Per-deck overrides:** optional `data/ai_profiles/<deck_id>.json` with weight hints. Falls back to defaults when absent.
- Wire into [`scenes/match/match.gd`](../scenes/match/match.gd): when SetupManager mode is **Player** and player 1 has `is_cpu=true`, AI drives the opposing turn. Add CPU toggle to [`scenes/match/setup_manager.gd`](../scenes/match/setup_manager.gd).
- Author 3 opponent decks under `data/decks/opponents/`: DR fire, RS water, SS electric. One AI profile per deck.

### W5 — Animated idle NPCs

- Extract 3 NPC models (shop clerk, PokéCenter nurse, generic townsperson) via the W3 pipeline → `assets/models/overworld/characters/`.
- New `scenes/overworld/npc/npc_idle.{tscn,gd}`:
  - Node3D root + imported PackedScene + StaticBody3D (`ow_world`) + Area3D (`ow_interact`) + Label3D nameplate.
  - `_ready()` plays the rig's `idle` clip.
  - Exported `interact_dialog: String` for click-to-talk; clerk NPC opens the shop, trainer NPC challenges to battle using a W4 opponent deck.
- Place 3 instances in starter_town.

### W6 — Online mode (LAN / direct-IP via ENet)

- New `scripts/net/lan_match.gd` wrapping `ENetMultiplayerPeer`: `host(port)`, `join(ip, port)`.
- New `scenes/lan_lobby/lan_lobby.{tscn,gd}` with IP + port fields, Host / Join buttons, status label.
- Add **"LAN Match"** to [`scenes/main_menu/main_menu.tscn`](../scenes/main_menu/main_menu.tscn).
- Refactor [`scripts/net/match_authority.gd`](../scripts/net/match_authority.gd) so actions are RPC-able. Host is authoritative on RNG seed; clients run effects deterministically from a single initial snapshot — only the action stream is networked thereafter.
- Verify with two editors on `127.0.0.1`.

### W7 — Match polish (carryover from `snoopy-hugging-castle`)

- Remove **Modify Bench** debug button.
- Retreat dialog: energy-type hints; auto-skip when only one valid selection.
- Discard dialog: auto-skip when N attached = N required.
- All in [`scenes/match/dialog_manager.gd`](../scenes/match/dialog_manager.gd) (~lines 176–666).

### W8 — Shop + progression integration

- Wire the shop NPC (from W5) → opens [`scenes/shop/shop.tscn`](../scenes/shop/shop.tscn) without a main-menu detour.
- Tiered pack pricing: add `price` field to PackDefinition, default 100 when absent.
- Reward coins on W4 NPC battle wins via `PlayerProfile.add_coins`.

---

## 4. Recommended Execution Order

1. **W1** — independent, low risk; can interleave with anything.
2. **W3** — quick visual win that makes the overworld feel real.
3. **W2** — needed before W5 placement.
4. **W4** — depends on W1 cards being playable.
5. **W5** — depends on W2 + W3 + W4.
6. **W8** — depends on W5 + W4.
7. **W7** — independent; do anytime.
8. **W6** — last; touches match flow heavily; land on a stable base.

---

## 5. Verification (Alpha smoke test)

Run end-to-end in one play session:

1. Boot → main menu shows Match, Overworld, Deck Builder, Collection, Shop, **LAN Match** + coin counter.
2. Overworld → spawn in starter_town as the rigged player; idle clip plays; walking → walk clip.
3. ≥3 animated NPCs visible in town, each playing idle.
4. Interact with **clerk NPC** → shop opens → buy pack → coins deduct → open → collection grows.
5. Interact with **trainer NPC** → match vs W4 opponent deck → opponent plays plausibly → win → coins awarded.
6. Deck Builder → build 60-card deck from owned cards → use it in next match.
7. LAN Match → host on editor A, join `127.0.0.1` on editor B → synchronized turns.
8. `test_run` MCP verb → all GUT tests green (Tier 1/2/3).

Track exceptions in `docs/ALPHA_KNOWN_ISSUES.md` (create when needed).

---

## 6. Out of Scope for Alpha

- Phase 2 of `fluffy-octopus` (lazy card art).
- Async attack resolver from `radiant-hopcroft` — parked behind a feature flag.
- Matchmaking, dedicated server, anything beyond direct-IP ENet.
- More than 3 opponent decks or 3 idle NPCs.
- Cutscenes, dialog trees, scripted town events beyond click-to-talk / click-to-battle.
- Audio (music, SFX) — separate post-Alpha workstream.

---

## 7. Updating This Document

When closing a workstream, edit §3 to strike it through and add a one-line
"Landed in commit `<sha>`" note. When scope changes, edit §1 and §6 in
lockstep so they stay consistent. Keep §2 (audit) as a historical
snapshot — do not rewrite the past, just append new rows if new plans land.
