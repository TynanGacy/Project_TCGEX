extends Control
## Main menu — entry point after launch.
## Buttons navigate to the match scene, overworld, or user-progression flows
## (collection / shop / deck builder).


func _ready() -> void:
	$VBox/MatchButton.pressed.connect(_on_match_pressed)
	$VBox/OverworldButton.pressed.connect(func(): GameStateManager.change_state("res://scenes/overworld/overworld_root.tscn"))
	$VBox/CollectionButton.pressed.connect(GameStateManager.open_collection)
	$VBox/DeckBuilderButton.pressed.connect(func(): GameStateManager.change_state("res://scenes/deck_builder/deck_builder.tscn"))
	$VBox/ShopButton.pressed.connect(GameStateManager.open_shop)
	$VBox/MiniGame1Button.pressed.connect(func(): GameStateManager.go_to_placeholder("Mini Game 1"))

	_refresh_coins(PlayerProfile.coins)
	PlayerProfile.coins_changed.connect(_refresh_coins)


func _on_match_pressed() -> void:
	GameStateManager.change_state("res://scenes/match/match.tscn")


func _refresh_coins(value: int) -> void:
	$CoinLabel.text = "Coins: %d" % value
