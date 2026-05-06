extends Control
## Generic placeholder for WIP game states.
## Displays the state name provided by GameStateManager and a Back button.


func _ready() -> void:
	$VBox/StateLabel.text = GameStateManager.get_pending_state_name()
	$VBox/BackButton.pressed.connect(GameStateManager.return_to_menu)
