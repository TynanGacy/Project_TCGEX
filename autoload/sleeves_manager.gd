class_name SleevesManager
extends Node
## Manages card sleeve (back-face) textures per player.
## Both players default to the shared card_back.png.
## Call set_sleeve() to customise a player's sleeve at runtime.

const DEFAULT_SLEEVE_PATH := "res://assets/images/card_back.png"

## Index 0 = player 0, index 1 = player 1.
var _sleeves: Array[Texture2D] = [null, null]


func _ready() -> void:
	var default_tex := load(DEFAULT_SLEEVE_PATH) as Texture2D
	_sleeves[0] = default_tex
	_sleeves[1] = default_tex


## Returns the sleeve texture for player_id, or null if none is set.
func get_sleeve(player_id: int) -> Texture2D:
	if player_id >= 0 and player_id < _sleeves.size():
		return _sleeves[player_id]
	return null


## Sets a custom sleeve texture for player_id.
func set_sleeve(player_id: int, texture: Texture2D) -> void:
	if player_id >= 0 and player_id < _sleeves.size():
		_sleeves[player_id] = texture
