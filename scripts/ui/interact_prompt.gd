class_name InteractPrompt

# The HUD's "Interact" prompt (key icon and a line of text) for things you walk up to and press the interact key at.
# InteractPrompt.show_prompt(tree, "Take the shield") while the player is in reach, InteractPrompt.hide_prompt(tree)
# when they leave or have used it. Hiding puts the text back to "Interact" for the upgrade station, which shares it.

const DEFAULT_TEXT := "Interact"


static func show_prompt(tree: SceneTree, text: String) -> void:
	var box := _box(tree)
	if box == null:
		return
	(box.get_node("InteractLabel") as Label).text = text
	box.visible = true


static func hide_prompt(tree: SceneTree) -> void:
	var box := _box(tree)
	if box == null:
		return
	box.visible = false
	(box.get_node("InteractLabel") as Label).text = DEFAULT_TEXT


static func _box(tree: SceneTree) -> Control:
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("HUD/InGameHUD/InteractContainer") as Control
