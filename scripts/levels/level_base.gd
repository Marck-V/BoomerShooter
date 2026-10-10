extends Node3D
class_name LevelBase

# Shared setup for levels built from a TrenchBroom map (FuncGodotMap).
#
# Level geometry has to sit on the Environment physics layer: bullets, blood splats, impact sparks and enemy
# line-of-sight all look for it. func_godot's definitions default to layer 1 and a Build saved into a scene
# keeps whatever layer it had at the time, so every level calls this on load and fixes stale geometry.


# Moves static level bodies under `root` onto the Environment layer. Returns how many it had to fix.
func ensure_world_collision(root: Node) -> int:
	var fixed := 0
	for node in root.find_children("*", "CollisionObject3D", true, false):
		if not (node is StaticBody3D or node is AnimatableBody3D):
			continue
		var body := node as CollisionObject3D
		if body.collision_layer & PhysicsLayers.ENVIRONMENT == 0:
			body.collision_layer |= PhysicsLayers.ENVIRONMENT
			fixed += 1
	if fixed > 0:
		push_warning("%s: moved %d level bodies onto the Environment physics layer (rebuild the map to fix this at the source)." % [name, fixed])
	return fixed
