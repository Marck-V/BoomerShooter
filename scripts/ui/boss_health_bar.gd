extends Control

@onready var health_bar = $"HealthBar"
@onready var name_label: Label = get_node_or_null("BossName")

func set_max_health(amount):
	health_bar.max_value = amount

func set_health(amount):
	health_bar.value = amount

# The name shown under the bar. Bosses that don't set one leave it empty.
func set_boss_name(boss_name: String) -> void:
	if name_label:
		name_label.text = boss_name

func show_bar():
	visible = true

func hide_bar():
	visible = false

