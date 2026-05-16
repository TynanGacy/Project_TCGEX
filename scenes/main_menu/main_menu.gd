extends Control
## Main menu — entry point after launch.
## Buttons navigate to the match scene or WIP placeholder states.


func _ready() -> void:
	$VBox/MatchButton.pressed.connect(_on_match_pressed)
	$VBox/OverworldButton.pressed.connect(func(): GameStateManager.go_to_placeholder("Overworld"))
	$VBox/CardListButton.pressed.connect(func(): GameStateManager.change_state("res://scenes/card_browser/card_browser.tscn"))
	$VBox/DeckBuilderButton.pressed.connect(func(): GameStateManager.change_state("res://scenes/deck_builder/deck_builder.tscn"))
	$VBox/PackOpeningButton.pressed.connect(func(): GameStateManager.go_to_placeholder("Pack Opening"))
	$VBox/MiniGame1Button.pressed.connect(func(): GameStateManager.go_to_placeholder("Mini Game 1"))


func _on_match_pressed() -> void:
	GameStateManager.change_state("res://scenes/match/match.tscn")
