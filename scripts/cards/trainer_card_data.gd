extends CardData
class_name TrainerCardData

enum TrainerKind { ITEM, SUPPORTER, STADIUM, TOOL }

@export var trainer_kind: TrainerKind = TrainerKind.ITEM

@export var effect_handler_id: String = ""
