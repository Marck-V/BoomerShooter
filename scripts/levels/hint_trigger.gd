extends Area3D

# A TrenchBroom brush entity ("hint_trigger"): the first time the player walks in, a note appears at the bottom of the
# screen (title + lines, split with "|") and fades by itself. {parry} and {throw_shield} (any input action name in braces)
# are replaced with the key bound to it.

@export var title := ""
@export var text := ""
@export var seconds := 7.0

var shown := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if shown or not body.is_in_group("Player"):
		return
	shown = true
	var lines: Array = []
	for line in text.split("|"):
		lines.append(_with_keys(line.strip_edges()))
	NoteBox.show_note(get_tree(), title, lines, seconds)


func _with_keys(line: String) -> String:
	for action in InputMap.get_actions():
		line = line.replace("{%s}" % action, NoteBox.key(action))
	return line
