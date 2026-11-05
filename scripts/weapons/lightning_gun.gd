extends BaseWeapon

# Chain lightning gun: one shot hits what you aim at, then the lightning jumps from enemy to enemy.

const ElectricAura = preload("res://scripts/weapons/electric_aura.gd")
const LightningBolt = preload("res://scripts/weapons/lightning_bolt.gd")

# --- Chain Lightning Parameters ---
var chain_radius = 8.0        # how far (meters) the lightning can jump to the next enemy
var max_targets = 8           # most enemies one shot can hit, including the one that was shot
var chain_damage = 50
const CHAIN_HOP_DELAY := 0.1  # seconds between jumps

const AMMO_PER_SHOT := 1
const HIT_FLASH_COLOR := Color(0.3, 0.6, 1.0)   # blue, like the lightning

# --- The model (models/lightning_gun, built by tools/assetgen/lightning_gun.py) ---
# A plasma globe that lights the gun from inside, arcs crawling in it, rattling along the glass tubes on the side and
# now and then across the claw tips. On a shot the globe flares, the claws snap open, arcs leap from each tip to the
# muzzle and a bolt flies from the claws to whatever the shot hit.
const ARC_ENERGY := 3.5                          # glow of the model's arcs (lightning_bolt.gdshader)
const ARC_WIDTH := 0.007                         # half-width of an arc's glow, in the model's units (about 0.75 long)
const ARC_REFRESH := 0.06                        # seconds between new arc shapes: the flicker
const ORB_ARCS := 4
const CLAW_ARC_CHANCE := 0.25                    # chance per refresh of an arc jumping between two claw tips
const TUBE_COUNT := 3
const TUBE_ARC_WIGGLE := 0.012                   # how far an arc strays from a tube's middle (the glass is 0.021)
const TUBE_ARC_WIDTH := 0.0045                   # thinner than the other arcs, so the glass and caps still show

# The shot's bolt, from the claws to the hit point (drawn by lightning_bolt.gd): thin at the gun so it doesn't fill
# the view, full width a few metres out
const BOLT_WIDTH_NEAR := 0.008
const BOLT_WIDTH := 0.14
const CHAIN_WIDTH := 0.12                        # the jumps between enemies
const ORB_LIGHT_ENERGY := 0.45
const ORB_LIGHT_RANGE := 0.1                     # metres: enough to light the gun, not the room
const CLAW_FLARE := deg_to_rad(16.0)             # how far the claws snap open on a shot
const FIRE_GLOW_TIME := 0.25                     # how long the shot's flare takes to die down

@onready var model: Node3D = $Model
@onready var orb: Node3D = $Model/Orb
@onready var orb_core: MeshInstance3D = $Model/OrbCore
@onready var claws: Array[Node3D] = [$Model/Claw0, $Model/Claw1, $Model/Claw2]
@onready var claw_tips: Array[Node3D] = [$Model/Claw0/Tip0, $Model/Claw1/Tip1, $Model/Claw2/Tip2]
@onready var muzzle_marker: Node3D = $Model/Muzzle

var claw_rest: Array[Basis] = []
var tube_ends: Array[Vector3] = []               # start and end of each glass tube, in the model's space
var orb_light: OmniLight3D
var core_material: StandardMaterial3D
var core_energy := 1.0
var arcs_mesh: ImmediateMesh
var arc_timer := 0.0
var fire_glow := 0.0                             # 1 right after a shot, fading to 0


func _ready() -> void:
	super._ready()
	muzzle_flash_size = 0.09
	muzzle_flash_time = 0.08
	muzzle_light_energy = 8.0

	# The flash and the light come from between the claw tips
	muzzle_location.global_position = muzzle_marker.global_position
	for claw in claws:
		claw_rest.append(claw.basis)
	for i in TUBE_COUNT:
		tube_ends.append((model.get_node("Tube%dStart" % i) as Node3D).position)
		tube_ends.append((model.get_node("Tube%dEnd" % i) as Node3D).position)
	_setup_orb()
	_setup_arcs()


func _setup_orb() -> void:
	orb_light = OmniLight3D.new()
	orb_light.light_color = Color(0.35, 0.6, 1.0)
	orb_light.light_energy = ORB_LIGHT_ENERGY
	orb_light.omni_range = ORB_LIGHT_RANGE
	orb_light.shadow_enabled = false
	orb.add_child(orb_light)

	# Its own copy of the core's glow, so it can flicker
	core_material = (orb_core.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	core_energy = core_material.emission_energy_multiplier
	orb_core.set_surface_override_material(0, core_material)

	# The glass only tints: the core and the arcs are what glow
	var glass_instance := $Model/OrbGlass as MeshInstance3D
	var glass := (glass_instance.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	glass.emission_enabled = false
	glass.albedo_color.a = 0.12
	glass_instance.set_surface_override_material(0, glass)


func _setup_arcs() -> void:
	var material := LightningBolt.new_material(ARC_ENERGY)
	arcs_mesh = ImmediateMesh.new()
	var arcs := MeshInstance3D.new()
	arcs.name = "Arcs"
	arcs.mesh = arcs_mesh
	arcs.material_override = material
	arcs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(arcs)


func _process(delta: float) -> void:
	super._process(delta)
	fire_glow = maxf(fire_glow - delta / FIRE_GLOW_TIME, 0.0)

	# The globe flickers, and flares after a shot
	var flicker := randf_range(0.75, 1.15)
	orb_light.light_energy = ORB_LIGHT_ENERGY * flicker * (1.0 + 2.5 * fire_glow)
	core_material.emission_energy_multiplier = core_energy * flicker * (1.0 + 2.5 * fire_glow)

	# The claws snap open on a shot and ease shut (positive about a claw's own X swings it outwards)
	var open := CLAW_FLARE * ease(fire_glow, 0.4)
	for i in claws.size():
		claws[i].basis = claw_rest[i] * Basis(Vector3.RIGHT, open)

	arc_timer -= delta
	if arc_timer <= 0.0:
		arc_timer = ARC_REFRESH
		_draw_arcs()


# New random shapes for the arcs: some inside the globe, a couple rattling along each glass tube, sometimes one across
# the claw tips, and right after a shot one from every claw tip to the muzzle. Everything is in the model's own space.
func _draw_arcs() -> void:
	arcs_mesh.clear_surfaces()
	var to_model := model.global_transform.affine_inverse()
	var centre: Vector3 = orb.position
	var radius := 0.075
	var camera := get_viewport().get_camera_3d()
	var eye := to_model * camera.global_position if camera else centre + Vector3.BACK

	var bolts: Array = []
	for i in ORB_ARCS:
		var direction := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		bolts.append([centre + direction * 0.02, centre + direction * radius, 4])
	# In each tube: one arc from an end to somewhere along it, and sometimes a second one bouncing between two points
	for i in TUBE_COUNT:
		var start: Vector3 = tube_ends[i * 2]
		var end: Vector3 = tube_ends[i * 2 + 1]
		var from_start := randf() < 0.5
		var reach := randf_range(0.45, 1.0)
		var a := start if from_start else end
		var b := start.lerp(end, reach) if from_start else end.lerp(start, reach)
		bolts.append([a, b, 6, TUBE_ARC_WIGGLE, TUBE_ARC_WIDTH])
		if randf() < 0.3:
			var t0 := randf_range(0.0, 0.5)
			bolts.append([start.lerp(end, t0), start.lerp(end, t0 + randf_range(0.25, 0.5)), 4, TUBE_ARC_WIGGLE,
					TUBE_ARC_WIDTH])
	var tips: Array[Vector3] = []
	for tip in claw_tips:
		tips.append(to_model * tip.global_position)
	if randf() < CLAW_ARC_CHANCE:
		var a := randi() % tips.size()
		bolts.append([tips[a], tips[(a + 1) % tips.size()], 5])
	if fire_glow > 0.5:
		for tip in tips:
			bolts.append([tip, muzzle_marker.position, 4])

	arcs_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for bolt in bolts:
		_add_bolt(bolt[0], bolt[1], bolt[2], eye, bolt[3] if bolt.size() > 3 else INF,
				bolt[4] if bolt.size() > 4 else ARC_WIDTH)
	arcs_mesh.surface_end()


# A jagged arc from a to b, turned to face the eye: about `kinks` bends, never straying further than max_wiggle from
# the straight line (inside a tube). Thickest in the middle, a little faded at its ends.
func _add_bolt(a: Vector3, b: Vector3, kinks: int, eye: Vector3, max_wiggle := INF, width := ARC_WIDTH) -> void:
	var points := LightningBolt.fractal(a, b, 0.2, a.distance_to(b) / (kinks * 2.0), max_wiggle)
	var widths := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	for i in points.size():
		var t := float(i) / (points.size() - 1)
		widths.append(width * lerpf(0.55, 1.0, sin(PI * t)))
		alphas.append(lerpf(0.6, 1.0, sin(PI * t)))
	LightningBolt.add_ribbon(arcs_mesh, points, widths, alphas, eye)


# ---------------------------
# Firing
# ---------------------------
func fire(_origin: Vector3, _direction: Vector3, camera: Camera3D, raycast: RayCast3D) -> bool:
	if !data or !raycast:
		return false
	if not GlobalVariables.spend_ammo(GlobalVariables.current_weapon, AMMO_PER_SHOT):
		Audio.play("assets/audio/sfx/weapons/empty_gun.mp3")
		return false

	Audio.play(data.sound)
	play_muzzle_flash(true)
	fire_glow = 1.0
	arc_timer = 0.0   # the shot's arcs show on this frame
	trigger_recoil()

	for i in range(data.shot_count):
		var x_spread = deg_to_rad(randf_range(-data.spread, data.spread))
		var y_spread = deg_to_rad(randf_range(-data.spread, data.spread))

		var base_dir = -camera.global_transform.basis.z.normalized()
		var dir = base_dir.rotated(camera.global_transform.basis.x, y_spread)
		dir = dir.rotated(camera.global_transform.basis.y, x_spread)

		raycast.target_position = raycast.to_local(raycast.global_transform.origin + dir * data.max_distance)
		raycast.force_raycast_update()

		# The bolt goes to what the shot hit, or out to the gun's range on a miss
		var bolt_end: Vector3 = raycast.global_transform.origin + dir * data.max_distance
		if raycast.is_colliding():
			bolt_end = raycast.get_collision_point()
		_spawn_shot_bolt(muzzle_location.global_position, bolt_end, raycast.is_colliding())

		if raycast.is_colliding():
			var collider = raycast.get_collider()

			if collider and collider.has_method("damage"):
				# The hit can be a hurtbox or a shield; the chain starts from the enemy it belongs to
				var chain_target = get_hit_enemy(collider)
				flash_hit_enemy(collider, raycast.get_collision_point(), 1.0, HIT_FLASH_COLOR)
				damage_hit(collider, chain_damage, raycast.get_collision_point())

				if chain_target:
					ElectricAura.apply(chain_target)
					_run_chain(chain_target)

			spawn_impact_particles(raycast, camera)
	return true


# The shot itself: a forking bolt from the claws to the hit point that re-strikes and flickers out, flashing light
# and sparks where it lands. It is thin where it leaves the gun (right in front of your face) and swells to full
# width over its first few metres. On a miss there's nothing to land on, so no flash or sparks.
func _spawn_shot_bolt(start: Vector3, end: Vector3, hit: bool) -> void:
	LightningBolt.strike(get_tree(), start, end, {
		"width": BOLT_WIDTH,
		"start_width": BOLT_WIDTH_NEAR,
		"light": hit,
		"sparks": hit,
		"follow": muzzle_location,   # stays on the barrel while you move; the end stays where it landed
	})


# ---------------------------
# Chain Lightning
# ---------------------------
# Everything a chained enemy shows when the lightning reaches it (all purely visual)
func _chain_hit_effects(target: Node3D, from_position: Vector3) -> void:
	var chest := target.global_position + Vector3.UP * 1.2
	var direction := target.global_position - from_position
	direction.y = 0.0
	direction = direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD

	flash_hit_enemy(target, chest, 1.0, HIT_FLASH_COLOR)
	BloodParticles.spawn(get_tree(), chest, direction, 1.0, BloodParticles.thickness_for(target))
	ElectricAura.apply(target)


# Jumps from enemy to enemy, always to the nearest one not hit yet, until max_targets are hit or nobody is in range.
func _run_chain(first_enemy: Node3D) -> void:
	var visited: Array = [first_enemy]
	var from_position := first_enemy.global_position
	while visited.size() < max_targets:
		var next_enemy := _find_next_enemy(from_position, visited)
		if next_enemy == null:
			return
		visited.append(next_enemy)
		_spawn_lightning_arc(from_position, next_enemy.global_position)
		next_enemy.damage(chain_damage, 1)
		_chain_hit_effects(next_enemy, from_position)
		# Remembered now: the enemy may die and be freed before the next jump
		from_position = next_enemy.global_position
		await get_tree().create_timer(CHAIN_HOP_DELAY, false).timeout


# The nearest living enemy within chain_radius of a point that has not been hit by this chain yet.
# Looks through the Enemy group instead of running a physics query: an overlap query only returns a limited
# number of shapes, and every enemy has a dozen hurtbox and vision areas, so in a crowd it missed most enemies.
func _find_next_enemy(from_position: Vector3, visited: Array) -> Node3D:
	var best: Node3D = null
	var best_d2: float = chain_radius * chain_radius
	for candidate in get_tree().get_nodes_in_group("Enemy"):
		var enemy := candidate as Node3D
		if enemy == null or enemy in visited or not enemy.has_method("damage"):
			continue
		if enemy.get("destroyed") == true:
			continue
		var d2 := from_position.distance_squared_to(enemy.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = enemy
	return best


# A jump of the chain from one enemy to the next, chest to chest
func _spawn_lightning_arc(start: Vector3, end: Vector3):
	var chest := Vector3(0, 1.0, 0)
	LightningBolt.strike(get_tree(), start + chest, end + chest, {"width": CHAIN_WIDTH})
