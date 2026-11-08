extends RefCounted
class_name Blast

# An explosion in the world: the fireball, a shockwave that shoves the player, damage to every enemy and the
# player caught in it (nearer means harder, walls stop it, and the player is hurt as much as anyone), and a nudge
# for anything in the "Blastable" group (barrels, windows) so blasts set each other off.
#   Blast.explode(tree, center, radius, player_damage, enemy_damage, source)
# Anything that wants to react to a blast joins the "Blastable" group and implements on_blast(center, radius).

const SHOCKWAVE_SPEED := 26.0
const MAX_CAMERA_SHAKE := 0.8
const SOUNDS := "assets/audio/sfx/impacts/Balloon Explosion B.wav"


static func explode(tree: SceneTree, center: Vector3, radius: float, player_damage: float, enemy_damage: float, source: CollisionObject3D = null) -> void:
	BomberExplosion.spawn(tree, center, radius)
	BossShockwave.spawn(tree, _floor_below(tree, center), radius, SHOCKWAVE_SPEED, 0.0)   # does no damage, but throws the player back
	Audio.play_at(center, SOUNDS)

	var skip := _blast_bodies(tree)
	if source != null:
		skip.append(source.get_rid())

	for enemy in tree.get_nodes_in_group("Enemy"):
		if enemy.get("destroyed") or not enemy.has_method("damage_silently"):
			continue
		var distance := center.distance_to(enemy.global_position + Vector3.UP)
		if distance <= radius and _has_clear_line(tree, center, enemy.global_position + Vector3.UP, skip):
			enemy.damage_silently(enemy_damage * falloff(distance, radius))

	var player = GlobalVariables.player
	if is_instance_valid(player):
		var chest: Vector3 = player.global_position + Vector3.UP
		var distance := center.distance_to(chest)
		if distance <= radius * 2.0 and player.has_method("add_camera_shake"):
			player.add_camera_shake(MAX_CAMERA_SHAKE * (1.0 - distance / (radius * 2.0)))
		if distance <= radius and player.has_method("damage") and _has_clear_line(tree, center, chest, skip):
			player.damage(player_damage * falloff(distance, radius), false, center)

	for node in tree.get_nodes_in_group("Blastable"):
		if node != source and node.has_method("on_blast"):
			node.on_blast(center, radius)


# Full strength at the centre, half at the edge
static func falloff(distance: float, radius: float) -> float:
	return lerpf(1.0, 0.5, clampf(distance / radius, 0.0, 1.0))


static func _floor_below(tree: SceneTree, point: Vector3) -> Vector3:
	var hit := PhysicsLayers.surface_ray(tree, point, point + Vector3.DOWN * 4.0)
	return hit["position"] if not hit.is_empty() else point


# The bodies of barrels and windows, which a blast breaks rather than is stopped by
static func _blast_bodies(tree: SceneTree) -> Array[RID]:
	var rids: Array[RID] = []
	for node in tree.get_nodes_in_group("Blastable"):
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
	return rids


static func _has_clear_line(tree: SceneTree, from: Vector3, to: Vector3, skip: Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.ENVIRONMENT)
	query.exclude = skip
	return tree.root.world_3d.direct_space_state.intersect_ray(query).is_empty()
