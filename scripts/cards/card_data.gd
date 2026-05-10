extends Resource
class_name CardData

enum CardType { POKEMON, TRAINER, ENERGY }

@export var card_id: String = ""
@export var display_name: String = ""
@export var card_type: CardType = CardType.POKEMON
## Cards can carry multiple rarities at once — e.g. promos that also have a
## standard rarity (Promo + Rare). Filters and the rarity sort treat the card
## as belonging to every entry; display joins them with " / ".
@export var rarities: Array[String] = []

@export_multiline var rules_text: String = ""

@export var art: Texture2D
