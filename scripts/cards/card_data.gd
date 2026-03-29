extends Resource
class_name CardData

enum CardType { POKEMON, TRAINER, ENERGY }

@export var card_id: String = ""
@export var display_name: String = ""
@export var card_type: CardType = CardType.POKEMON

@export_multiline var rules_text: String = ""

@export var art: Texture2D
