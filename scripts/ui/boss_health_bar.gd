extends Control

@onready var health_bar = $"HealthBar"

var flash_tween: Tween

func set_max_health(amount):
    health_bar.max_value = amount

func set_health(amount):
    health_bar.value = amount
    flash_damage() # ← Trigger flash automatically when updated

func show_bar():
    visible = true

func hide_bar():
    visible = false


func flash_damage():
    # If a tween is already running, stop it
    if flash_tween:
        flash_tween.kill()

    # Create a new tween
    flash_tween = get_tree().create_tween()
    
    # Animate the modulate color
    # Flash to red quickly
    flash_tween.tween_property(
        health_bar, 
        "self_modulate", 
        Color(1, 0.2, 0.2), 
        0.08
    )

    # Tween back to normal color
    flash_tween.tween_property(
        health_bar,
        "self_modulate",
        Color.WHITE,
        0.12
    ).set_delay(0.05)
