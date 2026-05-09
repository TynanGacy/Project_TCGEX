# Just-for-Fun Deck — RS / SS / DR Modified (v2)

## Context
User wants a 60-card RS/SS/DR-only deck that's a fun, **Average to
Above-Average** difficulty opponent for a new player — not a tournament
list. The previous draft (Wobbgard / Gardevoir ex) tested at "Very
Hard." Pivoting to a niche archetype with a real win condition but
clear weaknesses a learning player can identify and exploit.

## The Pick: "Eeveelutions Toolbox"
A classic niche/janky archetype of the era. Sandstorm reprinted the
five Neo Eeveelutions (Espeon, Flareon, Jolteon, Umbreon, Vaporeon)
all evolving from one Eevee, all Stage 1, all only giving up 1 Prize.
You stuff Rainbow + Multi Energy into one deck and pick whichever
Eeveelution counters what your opponent led with.

Why this difficulty band lands right:
- **Only Stage 1, no ex Pokémon** — caps damage output at 50–70 per turn,
  so a beginner has time to react.
- **Coin-flip-heavy attacks** (Confuse Ray, Quick Attack, Double Kick,
  Super Singe) — game has natural variance the player can ride.
- **No infinite combos, no energy denial, no bench damage spread** —
  none of the "feels-bad" loss patterns.
- **Clear counter-play:** any Fighting-type attacker (which the new
  player's starter decks already feature) hits 4 of the 5 Eeveelutions
  for weakness. Lessons reward themselves.
- Still has a real **win condition** — Espeon's `Energy Crush` scales
  with opposing energy and reliably 2-shots, Flareon's `Flamethrower`
  swings for 70 — so the AI doesn't feel like a pushover either.

## Decklist (60)

### Pokémon (17)
- 4 Eevee (SS_63) — `Signs of Evolution` is the engine
- 2 Espeon (SS_16) — Psychic, scales vs. high-energy decks
- 2 Flareon (SS_5) — Fire, hardest-hitting Eeveelution (70)
- 2 Jolteon (SS_6) — Lightning, anti-Water tech
- 2 Umbreon (SS_24) — Darkness, Confuse Ray + Psychic resistance
- 2 Vaporeon (SS_25) — Water, anti-Fire tech, ignores Resistance
- 3 Dunsparce (SS_60) — starter, fills bench T1

### Trainers (19)
- 3 Rare Candy (SS_88) — go straight from Eevee to Eeveelution
- 3 Professor Birch (RS_89) — shuffle-draw, friendlier than TV Reporter
- 3 Pokémon Nav (RS_88) — find the right Eeveelution for the matchup
- 2 Energy Search (RS_90) — basic energy fixer
- 2 Switch (RS_92)
- 2 Potion (RS_91) — heal small chip damage on 70/80 HP attackers
- 2 Oran Berry (RS_85) — auto-heal 10
- 2 Lady Outing (RS_83) — light draw / Pokémon search

### Energy (24)
- 4 Rainbow Energy (RS_95) — pays any colored cost
- 4 Multi Energy (SS_93) — 2nd colorless slot when alone, 1 of any
- 4 Fire Energy (RS_108)
- 4 Water Energy (RS_106)
- 4 Lightning Energy (RS_109)
- 4 Psychic Energy (RS_107)

(No Darkness Energy: Umbreon's `Moon Impact` is 1 Darkness + 2
colorless and Rainbow/Multi cover the colored cost. Saves a slot for
basic energy of more-attacked-with types.)

## Game Plan / Rationale
1. **Turn 1:** Lead Dunsparce, `Strike and Run` to fetch Eevee + a
   second Dunsparce / utility basic. Attach an energy.
2. **Turn 2:** Eevee uses `Signs of Evolution` to grab the right
   Eeveelution against what the opponent has played, OR Rare Candy
   straight up. Attach.
3. **Turn 3 onward:** Promote the matchup-favorable Eeveelution and
   start swinging. If the opponent rotates threats, you rotate too —
   bench up a fresh Eevee, evolve, attack.
4. **Pacing for the player:** because every attacker is Stage 1 / 1
   Prize, the AI taking 6 prizes requires 6 KOs — plenty of opportunity
   for the player to stabilize.

## Why niche, not meta
Real-world top decks of RS-on (Gardevoir ex, Blaziken/Rayquaza ex,
Aggron ex stall, Wailord ex stall) are all OHKO threats or stall locks
that punish positional mistakes a new player will keep making. The
Eeveelutions deck instead trades evenly and rewards type-matchup
recognition — exactly the lesson a beginner deck should be teaching.

Other niche archetypes I considered and rejected:
- **Cradily (SS) "Sticky Hold" stall** — too punishing; trainer-locks
  feel bad to play against without prior knowledge.
- **Slaking (RS) solo beatdown** — its Poké-Body shuts off your own
  Powers, weirdly hostile for a new player to read.
- **Beautifly + Dustox spread** — too gimmicky, doesn't actually win.
- **Salamence-line dragons** — fragile Stage 2s, anti-climactic when
  they can't set up.

## Verification
- Total: 17 + 19 + 24 = **60** ✅
- 4-of cap respected on every non-basic-Energy card ✅
- All `card_id`s exist under `data/cards/RS|SS|DR/` ✅
- To play it: copy this list to
  `data/decks/eeveelutions_rsondr.json` mirroring
  `data/decks/ralts_test_deck.json`'s structure, then load from main.
