class_name TestFixtures
## Library of named board states for GUT tests.
##
## Each static method configures a TestBoardBuilder into a specific, reproducible
## scenario. Name the fixture after what mechanic it is designed to exercise.
##
## Usage:
##   var b := TestBoardBuilder.new(mgr, lib)
##   TestFixtures.basic_combat(b)
##   mgr.request_action(ActionAttack.new(...))
##
## Energy card IDs:
##   Grass:     RS_104_grass_energy
##   Fighting:  RS_105_fighting_energy
##   Water:     RS_106_water_energy
##   Psychic:   RS_107_psychic_energy
##   Fire:      RS_108_fire_energy
##   Lightning: RS_109_lightning_energy
##   Darkness:  RS_93_darkness_energy
##   Metal:     RS_94_metal_energy

## ── Tier-0 base scenarios ──────────────────────────────────────────────────

## Electrike (1 Lightning energy, Headbutt 10dmg) vs Poochyena (1 Grass energy).
## Use: basic single-colorless attack validation.
static func basic_combat(b: TestBoardBuilder) -> void:
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike", {"energy": ["RS_109_lightning_energy"]})
	b.place_active(1, "RS_63_poochyena", {"energy": ["RS_104_grass_energy"]})
	b.set_prizes(0)
	b.set_prizes(1)


## Pikachu (Lightning) attacks Lotad (Water, weak to Lightning).
## Pika Bolt base=40 → after weakness ×2 = 80.
## Use: weakness multiplier.
static func weakness_lightning_vs_water(b: TestBoardBuilder) -> void:
	b.set_turn(0)
	## Pika Bolt costs 1 Lightning + 2 Colorless
	b.place_active(0, "SS_72_pikachu", {
		"energy": ["RS_109_lightning_energy", "RS_104_grass_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "SS_66_lotad", {"hp": 120})
	b.set_prizes(0)
	b.set_prizes(1)


## Grovyle (Grass) attacks Lairon (Metal, resistance GRASS -30).
## Slash base=20 → after resistance = max(0, 20-30) = 0.
## Use: resistance clamp to zero.
static func resistance_grass_vs_metal(b: TestBoardBuilder) -> void:
	b.set_turn(0)
	## Slash costs 2 Colorless
	b.place_active(0, "RS_32_grovyle", {
		"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "RS_36_lairon", {"hp": 70})
	b.set_prizes(0)
	b.set_prizes(1)


## Armaldo (Fighting) attacks Trapinch (Fighting-weak Grass) at exactly KO HP.
## Blade Arms base=60 → KO. Opponent has a Poochyena on bench so game continues.
## Use: KO detection, prize award, opponent promotion.
static func ko_scenario(b: TestBoardBuilder) -> void:
	b.set_turn(0)
	## Blade Arms costs 2 Fighting + 1 Colorless
	b.place_active(0, "SS_1_armaldo", {
		"energy": ["RS_105_fighting_energy", "RS_105_fighting_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "DR_78_trapinch", {"hp": 60})
	b.place_bench(1, "RS_63_poochyena")  ## keep opponent alive after KO
	b.set_prizes(0)
	b.set_prizes(1)


## Crawdaunt (Water) tries to attack without meeting typed energy requirement.
## Guillotine costs 1 Water + 2 Colorless; attacker only has 1 Grass energy.
## Use: energy validation rejection.
static func insufficient_energy(b: TestBoardBuilder) -> void:
	b.set_turn(0)
	b.place_active(0, "DR_3_crawdaunt", {"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)


## Electrike is Paralyzed — attack should be rejected.
## Use: special-condition blocking.
static func paralyzed_cannot_attack(b: TestBoardBuilder) -> void:
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike", {
		"energy": ["RS_109_lightning_energy"],
		"conditions": [PokemonInstance.SpecialCondition.PARALYZED],
	})
	b.place_active(1, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)


## Electrike is Asleep — attack should be rejected.
## Use: special-condition blocking.
static func asleep_cannot_attack(b: TestBoardBuilder) -> void:
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike", {
		"energy": ["RS_109_lightning_energy"],
		"conditions": [PokemonInstance.SpecialCondition.ASLEEP],
	})
	b.place_active(1, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)


## Lairon (Metal) uses Metal Claw (40dmg, 1 Metal + 2 Colorless) on a neutral target.
## Use: typed energy cost with colorless supplement.
static func typed_plus_colorless_cost(b: TestBoardBuilder) -> void:
	b.set_turn(0)
	b.place_active(0, "RS_36_lairon", {
		"energy": ["RS_94_metal_energy", "RS_104_grass_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "DR_41_shelgon", {"hp": 120})  ## COLORLESS, no W/R
	b.set_prizes(0)
	b.set_prizes(1)
