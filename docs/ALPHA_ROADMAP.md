# Alpha Release Roadmap — Project_TCGEX

> **Authoritative roadmap.** Future sessions should consult this document
> before starting work that touches Alpha scope. Update it when a
> workstream lands or scope changes — do not let it go stale.
>
> Last revised: 2026-05-17 (branch `version_0.0.4.4`, mid-W4).
> Source plan: `.claude/plans/look-over-the-previous-keen-floyd.md`.

---

## 🚨 Next-Session Priority — W0: Replace `TestDeckFactory` with a real card loader

**Address this BEFORE touching anything else.** A playtest of W4 Phase B2
surfaced that Growlithe's "Fire Veil" Poké-Body never burns the attacker
in live play, even though the GUT test passes. Investigation traced this
to a divergence between two card parsers:

- [`scripts/cards/card_library.gd`](../scripts/cards/card_library.gd)
  is the complete parser. GUT tests use it and pass.
- [`scripts/game/test_deck_factory.gd`](../scripts/game/test_deck_factory.gd)
  is what `DeckLoader` actually uses at match start, and it **does not
  parse the `abilities` array, the `effect_chain` array on attacks, the
  `extra_types` array, the `plays_as_pokemon` flag on trainers, or the
  `rules_text` field on Pokémon.** So every Poké-Body, every Poké-Power,
  every multi-effect attack chain, and every Fossil item is silently
  inert during real gameplay.

The name `TestDeckFactory` betrays the smell: a test helper became the
live path. It should not be involved in production card loading at all.

**Plan for next session (do FIRST):**

1. Audit every `TestDeckFactory.*` call site (current callers:
   [`scripts/game/deck_loader.gd`](../scripts/game/deck_loader.gd),
   [`scripts/game/game_state_serializer.gd`](../scripts/game/game_state_serializer.gd),
   [`scenes/match/save_load_manager.gd`](../scenes/match/save_load_manager.gd),
   [`scenes/match/setup_manager.gd`](../scenes/match/setup_manager.gd))
   and figure out what each needs (`build_deck(60)` random fallback,
   `_build_card_pool_by_id()` ID lookup, `load_art_for_deck()` art warm-up).
2. Promote `CardLibrary` (or a new `CardCatalog` autoload built on top of
   it) to be the single source of truth for parsed card data at runtime.
   `CardDatabase` already exists at
   [`autoload/card_database.gd`](../autoload/card_database.gd) — check
   whether that is the right home and consolidate there if so.
3. Repoint `DeckLoader._load_from_file`, the save/load card-pool lookup,
   and any other live caller to the new loader.
4. Deprecate `TestDeckFactory`. Keep `build_deck(N)` (random 60-card
   fallback) only if nothing else needs it; otherwise delete entirely.
   Move `load_art_for_deck` somewhere appropriate (it's not actually
   test-only).
5. Re-run the full GUT suite — the Growlithe Fire Veil regression test
   at [`tests/test_ability_wave1.gd`](../tests/test_ability_wave1.gd)
   should keep passing, and the live-game scenario should now actually
   apply BURNED to the attacker.

This unblocks everything that depends on real ability/effect-chain
behavior in live play: most of W4's "smarter CPU" gains, the Phase B3
scoring work, the comprehensive card audit, and the smoke test in §5.

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
| `goofy-enchanting-sedgewick.md` | Tier 2/3 attack handlers + tests | **Done** — Tier 0/1/2/3 suites + `test_effect_registry_coverage.gd` landed pre-Alpha; verified green 2026-05-17 on `version_0.0.4.4` | Closes **W1** |
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

### ~~W1 — Card coverage to "fully coded + tested"~~ ✅

**Landed on branch `version_0.0.4.4`, verified 2026-05-17.**

Re-audit found the original "~24 missing effect_keys" estimate was wrong:
the only non-energy cards without an `effect_key` are vanilla-damage attacks
(empty `text`) — they legitimately need no key. Hariyama and Fearow use
`hits_each_defending: true`, read directly by the resolver at
[`scripts/game/attack_resolver.gd:287`](../scripts/game/attack_resolver.gd),
also no `effect_key` required. Hariyama's flag path is covered by
`test_json_super_slap_push_hits_each_defending` at
[`tests/test_tier3_attacks.gd:2474`](../tests/test_tier3_attacks.gd).

Verified by:
- [`tests/test_tier0_attacks.gd`](../tests/test_tier0_attacks.gd) (vanilla attacks)
- [`tests/test_tier1_attacks.gd`](../tests/test_tier1_attacks.gd)
- [`tests/test_tier2_attacks.gd`](../tests/test_tier2_attacks.gd)
- [`tests/test_tier3_attacks.gd`](../tests/test_tier3_attacks.gd) (~100+ tests, 4 179 lines)
- [`tests/test_effect_registry_coverage.gd`](../tests/test_effect_registry_coverage.gd)
  — asserts every `effect_key` in card data resolves in its registry
  (Ability / Trainer / Attack + chain / Tool).

Full GUT suite is green on this branch.

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

### W4 — NPC enemy AI — **in progress**

Split into four sub-phases. **A / B1 / B2 landed; B3 + abilities bucket
remain.** All commits on branch `version_0.0.4.4`.

**Phase A ✅ — Foundation (commits `09f4334`, `e62afbf`, `23236d5`)**

- [`scripts/ai/opponent_ai.gd`](../scripts/ai/opponent_ai.gd)
  `decide_action(manager, pid) -> GameAction`. Priority-ordered heuristic
  (place active → fill bench → attach energy → attack), with tiered
  attack scoring (damage > 0 first, then status-inflicting on a clean
  target, then vanilla, then status-already-on-target last).
- [`scripts/ai/ai_driver.gd`](../scripts/ai/ai_driver.gd) turn loop +
  auto-place setup + "first valid option" fallback handlers for prize
  selection, promotion, energy-discard choice, retreat-discard choice,
  trainer queries, and attack queries. Match never blocks waiting on
  CPU input.
- [`scripts/ai/ai_profile.gd`](../scripts/ai/ai_profile.gd) stub for
  per-deck weight overrides (Phase B3).
- CPU toggle via Player Mode in
  [`scenes/match/setup_manager.gd`](../scenes/match/setup_manager.gd);
  AIDriver instantiated before `begin_game()`. Dialog gating in
  [`scenes/match/match.gd`](../scenes/match/match.gd) skips CPU-targeted
  prompts so AIDriver answers them.
- Perspective fix: Player Mode never flips camera; human always sees P0.
- First opponent deck: [`data/decks/opponents/dr_fire.json`](../data/decks/opponents/dr_fire.json).

**Phase B1 ✅ — Evolution + 2 more decks (commit `fe8a080`)**

- `_try_evolve` step in OpponentAI; engine's `ActionEvolve.validate`
  handles same-turn / first-turn restrictions.
- [`data/decks/opponents/rs_water.json`](../data/decks/opponents/rs_water.json)
  (Mudkip/Marshtomp, Magikarp/Gyarados, Corphish/Crawdaunt, Horsea/Seadra)
  and
  [`data/decks/opponents/ss_electric.json`](../data/decks/opponents/ss_electric.json)
  (Mareep/Flaaffy, Magnemite/Magneton + Plusle/Minun/Pichu/Elekid).
- SetupManager rolls a random opponent deck at match start; per-NPC
  selection lands with **W5**.

**Phase B2 ✅ — Trainer play (commit `0a223f6`)**

- `_try_play_trainer` step in OpponentAI between active placement and
  bench fill. Handles all five Trainer kinds: ITEM / SUPPORTER / STADIUM
  / TOOL (active first, then bench) / Fossil (`plays_as_pokemon` onto
  empty bench).
- Policy: "play any legal trainer". Engine validators block illegal
  cases; "legal but wasteful" plays (Potion on full HP, etc.) will fire
  until Phase B3 scoring lands.

**Phase B3 ⏳ — Real scoring + per-deck profiles** (next planned bucket
once W0 is done)

- Replace priority-ordered heuristic with a scored enumerator: damage-to-KO,
  energy efficiency, threat avoidance, "is this trainer play worth a card?".
- Load optional `data/ai_profiles/<deck_id>.json` weight overrides via
  the existing AIProfile stub.
- Add Potion-on-damaged, Switch-when-trapped, Energy-Search-when-thirsty
  guards.

**Active Poké-Powers ⏳ — also still pending**

Most Poké-Bodies are already passive (auto-fire). Active Poké-Powers
(e.g. "once per turn, draw 2") need a `_try_use_ability` step that
submits `ActionUseAbility`. Narrow scope (5–10 cards) but moderate
gameplay impact. Note that **active behaviour here also blocks on W0**:
abilities aren't parsed by `TestDeckFactory`, so until W0 lands, no
ability fires in live play.

**In-flight infrastructure changes landed alongside W4**

These were necessary unblockers, committed independently:

- ~~W1~~ closed (commit `0c15902`).
- Card audit pass (commit `4126380`): attack-side searches
  (`search_deck_basic_to_bench`, `search_deck_to_hand`,
  `search_deck_energy_to_hand`, `search_discard_energy_to_hand`) now
  prompt the player via a new `AttackQuery.Kind.CHOOSE_FROM_LIST`
  instead of auto-picking; trainer coin flips await the overlay so the
  player sees them resolve before any follow-up prompt.
- PROMPT handlers may be coroutines (commit `0b3d0c8`): both
  `TrainerEffectRegistry.get_query` and `AbilityEffectRegistry.get_query`
  now `await` the handler call so PROMPT bodies can await coin
  animations etc. Pokémon Reversal uses this.
- Playtest fixes (commit `a48134d`):
  - Dunsparce's "you may switch" tail option (`then_may_switch` param).
  - Cancelled Trainer cards return to hand (Switch, Potion, Mr. Briney's,
    Pokémon Reversal, Energy Switch). New `TrainerContext.cancelled`
    flag + restore-on-cancel in `TrainerResolver.dispatch`.
  - CPU energy attachment is now three passes (needs-energy actives →
    bench → fallback) and treats type-unreachable attacks (e.g. Barboach
    Mud Slap needs FIGHTING in a water-only deck) as covered so the AI
    doesn't pile water onto a Pokémon that can never fund its second
    attack. Barboach/Whiscash swapped out of the water deck for
    Corphish/Crawdaunt (water-only costs).
  - Hand visibility follows `_controlling_player`, not the active turn,
    so the human sees their own hand throughout setup placement and CPU
    turns.

**Known issues still open at end of session**

- **W0 (above) is blocking Fire Veil and every other Poké-Body in live
  play.** Highest priority next session.
- Pokémon Reversal's PROMPT-phase coin path was fixed for animation;
  cancellation restore works for ITEM/SUPPORTER/STADIUM, not TOOL
  (Tools currently have no cancellable path).
- A comprehensive sweep for "game auto-decides where the player should
  choose" was started (4 attack-side search handlers fixed) but is
  intentionally not finished — defer until W0 lands so the live game
  reflects the same behaviour as the tests.

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

1. **~~W1~~** ✅ landed `0c15902`.
2. **W0** — **FIRST next session.** Card-loader replacement (see top of
   document). Unblocks Phase B3 + abilities + the live smoke test.
3. **W4 Phase B3** + **abilities bucket** — resume W4 once W0 is in.
4. **W3** — quick visual win that makes the overworld feel real (needs
   user's Blender pipeline).
5. **W2** — needed before W5 placement (also Blender-gated).
6. **W5** — depends on W2 + W3 + W4.
7. **W8** — depends on W5 + W4.
8. **W7** — independent; do anytime.
9. **W6** — last; touches match flow heavily; land on a stable base.

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
