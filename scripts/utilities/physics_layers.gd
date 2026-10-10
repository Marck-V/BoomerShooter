extends RefCounted
class_name PhysicsLayers

# The project's physics layers, in one place so queries don't depend on magic numbers.
# Values are bit masks (layer N = 1 << (N - 1)).
#   layer 1 Player   layer 2 Environment   layer 3 Enemy body   layer 4 Enemy hurtbox
#   layer 5 Bullets  layer 6 Enemy hitbox  layer 7 Grapple points
const PLAYER := 1
const ENVIRONMENT := 2
const ENEMY_BODY := 4
const ENEMY_HURTBOX := 8
const GRAPPLE := 64        # layer 7: grapple points the thrown shield can latch onto

# Level geometry that effects (blood splats, impacts...) may land on. Layer 1 is included because level
# bodies built by func_godot default to it; the player shares that layer, so callers using this mask must
# also pass player_rids() as the query's exclude list.
const SURFACE_MASK := PLAYER | ENVIRONMENT


# Bodies of the player(s), to exclude from surface queries
static func player_rids(tree: SceneTree) -> Array[RID]:
	var rids: Array[RID] = []
	for node in tree.get_nodes_in_group("Player"):
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
	return rids


# First level surface hit by a ray, as a physics ray result Dictionary (empty when nothing was hit)
static func surface_ray(tree: SceneTree, from: Vector3, to: Vector3) -> Dictionary:
	var world := tree.root.world_3d
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, SURFACE_MASK)
	query.collide_with_areas = false
	query.exclude = player_rids(tree)
	return world.direct_space_state.intersect_ray(query)
