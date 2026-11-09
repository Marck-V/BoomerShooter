extends Node

# Lets Escape or Enter close a pause window (the shield pickup's): calls the "close" Callable kept in this node's meta.
# It keeps working while the game is paused and swallows the key so the pause menu doesn't open.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER):
		get_viewport().set_input_as_handled()
		var close: Callable = get_meta("close")
		close.call()
