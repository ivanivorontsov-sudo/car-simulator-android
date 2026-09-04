extends VehicleBody3D
class_name PlayerCar

## Semi-realistic drivetrain on Godot VehicleBody3D / VehicleWheel3D.
## Engine RPM + torque curve, gearbox (R + 1-5), speed-sensitive progressive
## steering, brakes / handbrake, suspension, tire slip, anti-spin, cabin driver
## + FPS steering wheel/dash, visual damage deformation (NOT soft-body), and
## auto-restart after critical wreck / cliff fall.

signal telemetry(speed_kmh: float, rpm: float, gear: int, slipping: float, damage: float)
signal wrecked()
signal damage_changed(damage: float)

const IDLE_RPM := 900.0
const REDLINE_RPM := 7500.0
const STALL_RPM := 600.0
const PEAK_TORQUE := 400.0
const PEAK_TORQUE_RPM := 4800.0
const FINAL_DRIVE := 3.55
const DRIVELINE_EFFICIENCY := 0.90
const WHEEL_RADIUS := 0.34
const VISUAL_SCALE := 2.0
const MAX_ENGINE_FORCE := 7800.0
const MAX_YAW_RATE := 2.05
const CRITICAL_DAMAGE := 1.0
const WRECK_RESTART_DELAY := 5.0

# R, 1, 2, 3, 4, 5
const GEAR_RATIOS: Array[float] = [-3.42, 3.58, 2.16, 1.48, 1.12, 0.86]

@export var auto_shift: bool = true
@export var max_steer_angle: float = 0.52
@export var min_steer_angle: float = 0.20
@export var brake_force: float = 34.0
@export var handbrake_force: float = 22.0
## Steer input accel toward full lock (units/sec² feel via ease).
@export var steer_accel: float = 8.2
@export var steer_return_accel: float = 11.5
@export var steer_max_rate: float = 4.4
@export var steer_return_max_rate: float = 6.2

var gear: int = 1
var rpm: float = IDLE_RPM
var throttle_input: float = 0.0
var brake_input: float = 0.0
var steer_input: float = 0.0
var _steer_velocity: float = 0.0
var handbrake_input: float = 0.0
var speed_kmh: float = 0.0
var slipping: float = 0.0
var damage: float = 0.0
var is_wrecked: bool = false
var _shift_lock: float = 0.0
var _spawn_transform: Transform3D
var _manual_override: bool = false
var _prev_velocity: Vector3 = Vector3.ZERO
var _engine_force_smoothed: float = 0.0
var _steer_wheel: Node3D
var _driver_root: Node3D
var _driver_head: Node3D
var _cabin_dash: Node3D
## Instantiated Kenney sedan-sports.glb root (opaque yellow body shell).
var _sedan_visual: Node3D = null
var _fps_hide_nodes: Array[Node3D] = []
var _fps_vis_backup: Dictionary = {}  # instance_id -> was_visible before FPS hide
var _crash_smoke: GPUParticles3D
var _spark_fx: GPUParticles3D
var _crash_audio: AudioStreamPlayer3D
var _scrape_audio: AudioStreamPlayer3D
var _body_mesh_instances: Array[MeshInstance3D] = []
var _body_mesh_backups: Array[Mesh] = []
var _panel_parts: Array[Dictionary] = []  # {node, base_pos, base_rot}
var _bumper: Node3D
var _broken_glass: MeshInstance3D
var _surface_grip: float = 1.0
var _impact_cooldown: float = 0.0
var _airborne_timer: float = 0.0
var _scrape_timer: float = 0.0
var _fps_mode: bool = false
var _world: WorldBuilder
var _reset_seq: int = 0
var _collision_layer_saved: int = 1
var _collision_mask_saved: int = 1
var _unstick_timer: float = 0.0
var _collision_disabled: bool = false

@onready var wheel_fl: VehicleWheel3D = $WheelFL
@onready var wheel_fr: VehicleWheel3D = $WheelFR
@onready var wheel_bl: VehicleWheel3D = $WheelBL
@onready var wheel_br: VehicleWheel3D = $WheelBR
@onready var visual: Node3D = $Visual
@onready var engine_player: AudioStreamPlayer = $EngineAudio
@onready var skid_player: AudioStreamPlayer3D = $SkidAudio
var smoke_fl: GPUParticles3D
var smoke_fr: GPUParticles3D
var smoke_bl: GPUParticles3D
var smoke_br: GPUParticles3D
var skid_marks: SkidMarks


func _ready() -> void:
	_spawn_transform = global_transform
	mass = 1320.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.38, 0.04)
	linear_damp = 0.16
	angular_damp = 2.05
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	_setup_wheels()
	_attach_visuals()
	_attach_driver_and_cabin()
	_setup_smoke()
	_setup_crash_fx()
	_setup_audio()
	_setup_skid_marks()
	body_entered.connect(_on_body_entered)
	call_deferred("_find_world")


func _find_world() -> void:
	var p := get_parent()
	if p:
		_world = p.get_node_or_null("World") as WorldBuilder


func set_spawn(xf: Transform3D) -> void:
	_spawn_transform = xf
	reset_vehicle()


func set_fps_view(enabled: bool) -> void:
	## v1.3.3: hide the entire Kenney body in FPS. The sedan-sports GLB is a
	## solid yellow shell; the FPS eye sits INSIDE it, so leaving the mesh
	## visible fills the screen with yellow interior (not road/sky).
	var entering := enabled and not _fps_mode
	var leaving := (not enabled) and _fps_mode
	_fps_mode = enabled
	if entering:
		_backup_and_hide_fps_occluders()
	elif enabled:
		# Re-assert hide (e.g. after reset while already in FPS).
		_hide_fps_occluders_only()
	elif leaving or not enabled:
		_restore_fps_occluders()
	# Procedural cabin stays: dash (lower) + steering wheel.
	if _cabin_dash and is_instance_valid(_cabin_dash):
		_cabin_dash.visible = true
	if _steer_wheel and is_instance_valid(_steer_wheel):
		_steer_wheel.visible = true


func _fps_occluder_nodes() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	if _sedan_visual:
		nodes.append(_sedan_visual)
	if _driver_root:
		nodes.append(_driver_root)
	if _bumper:
		nodes.append(_bumper)
	if _broken_glass:
		nodes.append(_broken_glass)
	for p in _panel_parts:
		var n: Node3D = p["node"]
		if n:
			nodes.append(n)
	for n in _fps_hide_nodes:
		if n:
			nodes.append(n)
	return nodes


func _backup_and_hide_fps_occluders() -> void:
	_fps_vis_backup.clear()
	for n in _fps_occluder_nodes():
		if not is_instance_valid(n):
			continue
		_fps_vis_backup[n.get_instance_id()] = n.visible
		n.visible = false


func _hide_fps_occluders_only() -> void:
	for n in _fps_occluder_nodes():
		if is_instance_valid(n):
			n.visible = false


func _restore_fps_occluders() -> void:
	for n in _fps_occluder_nodes():
		if not is_instance_valid(n):
			continue
		var id := n.get_instance_id()
		if _fps_vis_backup.has(id):
			n.visible = bool(_fps_vis_backup[id])
		elif n == _sedan_visual or n == _driver_root:
			n.visible = true
		elif n == _bumper:
			n.visible = damage <= 0.75
		elif n == _broken_glass:
			n.visible = damage > 0.55
		else:
			# Deform panels: only show if already damaged.
			n.visible = damage > 0.2
	_fps_vis_backup.clear()


func reset_vehicle() -> void:
	## Hard reset: always yank free of barriers / wreck freeze / contacts.
	_reset_seq += 1
	var seq := _reset_seq
	is_wrecked = false
	Engine.time_scale = 1.0
	_unstick_timer = 0.0
	_collision_disabled = false

	# Capture layers once (first reset may run before physics ready).
	if _collision_layer_saved == 1 and collision_layer != 0:
		_collision_layer_saved = collision_layer
	if _collision_mask_saved == 1 and collision_mask != 0:
		_collision_mask_saved = collision_mask

	# Freeze + drop collisions so barrier contacts cannot hold the body.
	freeze = true
	sleeping = false
	collision_layer = 0
	collision_mask = 0
	_collision_disabled = true

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	_engine_force_smoothed = 0.0
	_steer_velocity = 0.0
	_impact_cooldown = 0.0
	_airborne_timer = 0.0
	_scrape_timer = 0.0
	damage = 0.0
	gear = 1
	rpm = IDLE_RPM
	engine_force = 0.0
	brake = 8.0
	steering = 0.0
	steer_input = 0.0
	throttle_input = 0.0
	brake_input = 0.0
	handbrake_input = 0.0
	_shift_lock = 0.2
	_manual_override = false
	slipping = 0.0
	speed_kmh = 0.0

	global_transform = _spawn_transform
	# Force PhysicsServer state (teleport past active contacts).
	var rid := get_rid()
	if rid.is_valid():
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, _spawn_transform)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)

	if skid_marks:
		skid_marks.clear_marks()
	if _crash_smoke:
		_crash_smoke.emitting = false
	if _spark_fx:
		_spark_fx.emitting = false
	_restore_meshes()
	_reset_panels()
	if _bumper:
		_bumper.visible = true
		_bumper.position = Vector3(0.0, 0.42, -1.55)
		_bumper.rotation = Vector3.ZERO
	if _broken_glass:
		_broken_glass.visible = false
	if engine_player and not engine_player.playing:
		engine_player.play()
	if _scrape_audio and _scrape_audio.playing:
		_scrape_audio.stop()
	damage_changed.emit(damage)
	set_fps_view(_fps_mode)
	_update_steering_wheel()

	# Brief collision-off window so spawn is never wedged; then unfreeze.
	_finish_hard_reset(seq)


func _finish_hard_reset(seq: int) -> void:
	# Two physics frames with collisions off, then restore.
	# set_spawn() may run during parent _ready before SceneTree is fully available.
	if not is_inside_tree() or get_tree() == null:
		call_deferred("_finish_hard_reset", seq)
		return
	await get_tree().physics_frame
	if seq != _reset_seq or not is_inside_tree():
		return
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	await get_tree().physics_frame
	if seq != _reset_seq or not is_inside_tree():
		return
	_restore_collision_and_unfreeze()


func _restore_collision_and_unfreeze() -> void:
	collision_layer = _collision_layer_saved if _collision_layer_saved != 0 else 1
	collision_mask = _collision_mask_saved if _collision_mask_saved != 0 else 1
	_collision_disabled = false
	freeze = false
	sleeping = false
	var rid := get_rid()
	if rid.is_valid():
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)



func _setup_wheels() -> void:
	var wheels: Array[VehicleWheel3D] = [wheel_fl, wheel_fr, wheel_bl, wheel_br]
	for w in wheels:
		w.wheel_radius = WHEEL_RADIUS
		w.wheel_rest_length = 0.15
		w.wheel_friction_slip = 4.7
		w.suspension_stiffness = 72.0
		w.suspension_max_force = 18500.0
		w.suspension_travel = 0.28
		w.damping_compression = 2.85
		w.damping_relaxation = 4.15
		w.wheel_roll_influence = 0.04
	wheel_fl.use_as_steering = true
	wheel_fr.use_as_steering = true
	wheel_bl.use_as_steering = false
	wheel_br.use_as_steering = false
	wheel_fl.use_as_traction = false
	wheel_fr.use_as_traction = false
	wheel_bl.use_as_traction = true
	wheel_br.use_as_traction = true
	wheel_fl.wheel_friction_slip = 5.0
	wheel_fr.wheel_friction_slip = 5.0
	wheel_bl.wheel_friction_slip = 4.65
	wheel_br.wheel_friction_slip = 4.65


func _setup_smoke() -> void:
	var tex: Texture2D = load("res://assets/textures/smoke.png")
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var quad := QuadMesh.new()
	quad.size = Vector2(1.05, 1.05)
	quad.material = mat
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 55.0
	proc.initial_velocity_min = 0.25
	proc.initial_velocity_max = 1.8
	proc.gravity = Vector3(0, 0.7, 0)
	proc.scale_min = 0.4
	proc.scale_max = 1.35
	proc.color = Color(0.72, 0.72, 0.72, 0.5)
	var created: Array[GPUParticles3D] = []
	for w in [wheel_fl, wheel_fr, wheel_bl, wheel_br]:
		var pfx := GPUParticles3D.new()
		pfx.name = "Smoke"
		pfx.amount = 22
		pfx.lifetime = 0.75
		pfx.emitting = false
		pfx.process_material = proc
		pfx.draw_pass_1 = quad
		w.add_child(pfx)
		created.append(pfx)
	smoke_fl = created[0]
	smoke_fr = created[1]
	smoke_bl = created[2]
	smoke_br = created[3]


func _setup_crash_fx() -> void:
	var tex: Texture2D = load("res://assets/textures/smoke.png")
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 2.2)
	quad.material = mat
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 80.0
	proc.initial_velocity_min = 0.6
	proc.initial_velocity_max = 2.8
	proc.gravity = Vector3(0, 1.1, 0)
	proc.scale_min = 0.8
	proc.scale_max = 2.4
	proc.color = Color(0.25, 0.25, 0.25, 0.7)
	_crash_smoke = GPUParticles3D.new()
	_crash_smoke.name = "CrashSmoke"
	_crash_smoke.amount = 48
	_crash_smoke.lifetime = 2.2
	_crash_smoke.emitting = false
	_crash_smoke.process_material = proc
	_crash_smoke.draw_pass_1 = quad
	_crash_smoke.position = Vector3(0, 0.9, 0.6)
	add_child(_crash_smoke)

	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = Color(1.0, 0.75, 0.25)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.55, 0.1)
	spark_mat.emission_energy_multiplier = 4.0
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.04
	spark_mesh.height = 0.08
	spark_mesh.material = spark_mat
	var spark_proc := ParticleProcessMaterial.new()
	spark_proc.direction = Vector3(0, 1, 0)
	spark_proc.spread = 90.0
	spark_proc.initial_velocity_min = 1.5
	spark_proc.initial_velocity_max = 5.0
	spark_proc.gravity = Vector3(0, -9.0, 0)
	spark_proc.scale_min = 0.4
	spark_proc.scale_max = 1.2
	spark_proc.color = Color(1.0, 0.8, 0.3, 1.0)
	_spark_fx = GPUParticles3D.new()
	_spark_fx.name = "Sparks"
	_spark_fx.amount = 36
	_spark_fx.lifetime = 0.45
	_spark_fx.one_shot = true
	_spark_fx.explosiveness = 0.9
	_spark_fx.emitting = false
	_spark_fx.process_material = spark_proc
	_spark_fx.draw_pass_1 = spark_mesh
	_spark_fx.position = Vector3(0, 0.5, -1.2)
	add_child(_spark_fx)

	_crash_audio = AudioStreamPlayer3D.new()
	_crash_audio.name = "CrashAudio"
	_crash_audio.bus = "Master"
	_crash_audio.max_distance = 80.0
	_crash_audio.unit_size = 4.0
	add_child(_crash_audio)

	_scrape_audio = AudioStreamPlayer3D.new()
	_scrape_audio.name = "ScrapeAudio"
	_scrape_audio.bus = "Master"
	_scrape_audio.max_distance = 40.0
	_scrape_audio.unit_size = 3.0
	_scrape_audio.volume_db = -12.0
	add_child(_scrape_audio)


func _setup_skid_marks() -> void:
	skid_marks = SkidMarks.new()
	skid_marks.name = "SkidMarks"
	call_deferred("_parent_skid_marks")


func _parent_skid_marks() -> void:
	if skid_marks == null:
		return
	var host := get_parent()
	if host:
		host.add_child(skid_marks)
	else:
		add_child(skid_marks)


func _attach_visuals() -> void:
	var packed: PackedScene = load("res://assets/models/cars/sedan-sports.glb")
	if packed == null:
		push_warning("Missing sedan-sports.glb")
		return
	var inst: Node3D = packed.instantiate()
	inst.name = "SedanSportsVisual"
	visual.add_child(inst)
	inst.rotation.y = PI
	inst.scale = Vector3(VISUAL_SCALE, VISUAL_SCALE, VISUAL_SCALE)
	inst.position = Vector3(0.0, -0.06, 0.02)
	_sedan_visual = inst

	var wheel_nodes := {
		"wheel-front-left": wheel_fl,
		"wheel-front-right": wheel_fr,
		"wheel-back-left": wheel_bl,
		"wheel-back-right": wheel_br,
	}
	for mesh_name in wheel_nodes.keys():
		var mesh: Node = inst.find_child(mesh_name, true, false)
		if mesh == null:
			continue
		mesh.visible = false
		var dup: Node = mesh.duplicate()
		dup.visible = true
		wheel_nodes[mesh_name].add_child(dup)
		if dup is Node3D:
			(dup as Node3D).position = Vector3.ZERO
			(dup as Node3D).rotation = Vector3.ZERO
			(dup as Node3D).scale = Vector3.ONE * 1.15

	_cache_body_meshes(inst)
	_create_deform_panels()


func _cache_body_meshes(root: Node) -> void:
	for child in root.get_children():
		_cache_body_meshes(child)
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var n := String(mi.name).to_lower()
		if "wheel" in n:
			return
		if mi.mesh == null:
			return
		_body_mesh_instances.append(mi)
		_body_mesh_backups.append(mi.mesh.duplicate())


func _create_deform_panels() -> void:
	# Soft visual "crumple zones" — offset boxes that bend with impact direction.
	var zones := [
		{"name": "NosePanel", "pos": Vector3(0.0, 0.55, -1.55), "size": Vector3(1.35, 0.35, 0.35)},
		{"name": "HoodPanel", "pos": Vector3(0.0, 0.78, -0.85), "size": Vector3(1.2, 0.08, 0.9)},
		{"name": "RoofPanel", "pos": Vector3(0.0, 1.25, 0.15), "size": Vector3(1.05, 0.06, 1.1)},
		{"name": "SideL", "pos": Vector3(-0.78, 0.65, 0.05), "size": Vector3(0.08, 0.45, 1.6)},
		{"name": "SideR", "pos": Vector3(0.78, 0.65, 0.05), "size": Vector3(0.08, 0.45, 1.6)},
		{"name": "TailPanel", "pos": Vector3(0.0, 0.6, 1.55), "size": Vector3(1.3, 0.3, 0.3)},
	]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.16, 0.18, 0.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.85
	for z in zones:
		var mi := MeshInstance3D.new()
		mi.name = z["name"]
		var box := BoxMesh.new()
		box.size = z["size"]
		mi.mesh = box
		mi.position = z["pos"]
		mi.material_override = mat
		mi.visible = false
		visual.add_child(mi)
		_panel_parts.append({"node": mi, "base_pos": mi.position, "base_rot": mi.rotation, "zone": String(z["name"])})

	_bumper = Node3D.new()
	_bumper.name = "FrontBumper"
	_bumper.position = Vector3(0.0, 0.42, -1.55)
	visual.add_child(_bumper)
	var bump_mesh := BoxMesh.new()
	bump_mesh.size = Vector3(1.4, 0.18, 0.22)
	var bmi := MeshInstance3D.new()
	bmi.mesh = bump_mesh
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.12, 0.12, 0.13)
	bmat.roughness = 0.55
	bmat.metallic = 0.35
	bmi.material_override = bmat
	_bumper.add_child(bmi)

	_broken_glass = MeshInstance3D.new()
	_broken_glass.name = "BrokenGlass"
	var gmesh := BoxMesh.new()
	gmesh.size = Vector3(1.05, 0.55, 0.04)
	_broken_glass.mesh = gmesh
	_broken_glass.position = Vector3(0.0, 1.05, -0.55)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.55, 0.7, 0.85, 0.25)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.roughness = 0.15
	gmat.metallic = 0.1
	_broken_glass.material_override = gmat
	_broken_glass.visible = false
	visual.add_child(_broken_glass)


func _attach_driver_and_cabin() -> void:
	_driver_root = Node3D.new()
	_driver_root.name = "Driver"
	_driver_root.position = Vector3(0.28, 0.62, 0.22)
	visual.add_child(_driver_root)

	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.12, 0.14, 0.22)
	suit.roughness = 0.72
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.86, 0.68, 0.54)
	skin.roughness = 0.55
	var helmet := StandardMaterial3D.new()
	helmet.albedo_color = Color(0.82, 0.12, 0.14)
	helmet.roughness = 0.35
	helmet.metallic = 0.15

	_add_part(_driver_root, BoxMesh.new(), Vector3(0.34, 0.42, 0.22), Vector3(0, 0.28, 0.02), suit)
	_add_part(_driver_root, BoxMesh.new(), Vector3(0.32, 0.16, 0.28), Vector3(0, 0.06, 0.06), suit)

	_driver_head = Node3D.new()
	_driver_head.name = "DriverHead"
	_driver_root.add_child(_driver_head)
	_add_part(_driver_head, SphereMesh.new(), Vector3(0.22, 0.22, 0.22), Vector3(0, 0.58, 0.0), helmet)
	_add_part(_driver_head, BoxMesh.new(), Vector3(0.16, 0.06, 0.04), Vector3(0, 0.56, -0.09), skin)

	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.07, 0.22, 0.07), Vector3(-0.22, 0.34, -0.12), suit, Vector3(deg_to_rad(70), 0, deg_to_rad(25)))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.07, 0.22, 0.07), Vector3(0.22, 0.34, -0.12), suit, Vector3(deg_to_rad(70), 0, deg_to_rad(-25)))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.06, 0.18, 0.06), Vector3(-0.18, 0.22, -0.28), skin, Vector3(deg_to_rad(20), 0, 0))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.06, 0.18, 0.06), Vector3(0.18, 0.22, -0.28), skin, Vector3(deg_to_rad(20), 0, 0))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.09, 0.26, 0.09), Vector3(-0.10, 0.02, -0.18), suit, Vector3(deg_to_rad(85), 0, 0))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.09, 0.26, 0.09), Vector3(0.10, 0.02, -0.18), suit, Vector3(deg_to_rad(85), 0, 0))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.07, 0.22, 0.07), Vector3(-0.10, -0.10, -0.42), suit, Vector3(deg_to_rad(10), 0, 0))
	_add_part(_driver_root, CapsuleMesh.new(), Vector3(0.07, 0.22, 0.07), Vector3(0.10, -0.10, -0.42), suit, Vector3(deg_to_rad(10), 0, 0))

	# Steering wheel — proper rim/spokes/hub; readable in lower third of FPS frame.
	_steer_wheel = Node3D.new()
	_steer_wheel.name = "SteeringWheel"
	# Closer/larger than v1.3.1 speck; aligned under RHD eye, below horizon look.
	_steer_wheel.position = Vector3(0.32, 0.90, -0.12)
	_steer_wheel.rotation_degrees = Vector3(-22, 0, 0)
	_steer_wheel.scale = Vector3(1.22, 1.22, 1.22)
	visual.add_child(_steer_wheel)
	_build_steering_wheel_mesh(_steer_wheel)

	# Dash only — procedural hood slab pushed down/short so it cannot occlude
	# the windshield from the FPS eye (was a yellow-stripe / blocked-view culprit).
	_cabin_dash = Node3D.new()
	_cabin_dash.name = "CabinDash"
	visual.add_child(_cabin_dash)
	var dash_mat := StandardMaterial3D.new()
	dash_mat.albedo_color = Color(0.1, 0.11, 0.13)
	dash_mat.roughness = 0.65
	_add_part(_cabin_dash, BoxMesh.new(), Vector3(1.35, 0.10, 0.42), Vector3(0.0, 0.68, -0.55), dash_mat)
	_add_part(_cabin_dash, BoxMesh.new(), Vector3(0.48, 0.05, 0.18), Vector3(0.32, 0.74, -0.42), dash_mat)
	var hood_mat := StandardMaterial3D.new()
	hood_mat.albedo_color = Color(0.18, 0.2, 0.24)
	hood_mat.roughness = 0.35
	hood_mat.metallic = 0.45
	# Thin + low + further forward: cue of a hood lip, not a windshield blocker.
	_add_part(_cabin_dash, BoxMesh.new(), Vector3(1.25, 0.025, 0.50), Vector3(0.0, 0.42, -1.45), hood_mat)


func _build_steering_wheel_mesh(root: Node3D) -> void:
	## Procedural racing wheel: thick rim, 3 spokes, hub, logo disc (CC0 / code only).
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.06, 0.06, 0.07)
	leather.roughness = 0.55
	leather.metallic = 0.05

	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.09, 0.09, 0.10)
	grip.roughness = 0.72

	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.72, 0.74, 0.78)
	chrome.roughness = 0.28
	chrome.metallic = 0.85

	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.75, 0.12, 0.14)
	accent.roughness = 0.4
	accent.metallic = 0.2

	var logo := StandardMaterial3D.new()
	logo.albedo_color = Color(0.15, 0.16, 0.18)
	logo.roughness = 0.35
	logo.metallic = 0.55

	# Main rim (torus in XY plane — faces camera when wheel stands upright).
	var rim := TorusMesh.new()
	rim.inner_radius = 0.022
	rim.outer_radius = 0.155
	rim.rings = 24
	rim.ring_segments = 32
	var rim_mi := MeshInstance3D.new()
	rim_mi.name = "Rim"
	rim_mi.mesh = rim
	rim_mi.material_override = leather
	root.add_child(rim_mi)

	# Grip pads at 10/2/bottom (subtle thickness).
	for ang_deg in [20.0, 160.0, 270.0]:
		var pad := TorusMesh.new()
		pad.inner_radius = 0.028
		pad.outer_radius = 0.158
		pad.rings = 10
		pad.ring_segments = 12
		var pmi := MeshInstance3D.new()
		pmi.mesh = pad
		pmi.material_override = grip
		# Partial look via scale squash — still reads as padded sections.
		pmi.scale = Vector3(1.0, 1.0, 0.55)
		pmi.rotation_degrees = Vector3(0, 0, ang_deg)
		root.add_child(pmi)

	# Hub barrel.
	var hub := CylinderMesh.new()
	hub.top_radius = 0.042
	hub.bottom_radius = 0.048
	hub.height = 0.045
	var hub_mi := MeshInstance3D.new()
	hub_mi.name = "Hub"
	hub_mi.mesh = hub
	hub_mi.rotation_degrees = Vector3(90, 0, 0)
	hub_mi.position = Vector3(0, 0, 0.01)
	hub_mi.material_override = chrome
	root.add_child(hub_mi)

	# Logo disc.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.032
	disc.bottom_radius = 0.032
	disc.height = 0.012
	var disc_mi := MeshInstance3D.new()
	disc_mi.name = "LogoDisc"
	disc_mi.mesh = disc
	disc_mi.rotation_degrees = Vector3(90, 0, 0)
	disc_mi.position = Vector3(0, 0, -0.018)
	disc_mi.material_override = logo
	root.add_child(disc_mi)
	# Tiny accent mark on logo.
	var mark := BoxMesh.new()
	mark.size = Vector3(0.028, 0.008, 0.004)
	var mark_mi := MeshInstance3D.new()
	mark_mi.mesh = mark
	mark_mi.position = Vector3(0, 0, -0.026)
	mark_mi.material_override = accent
	root.add_child(mark_mi)

	# Three racing spokes (Y layout): top + lower L/R.
	var spoke_angles := [90.0, 210.0, 330.0]
	for ang in spoke_angles:
		var spoke_root := Node3D.new()
		spoke_root.rotation_degrees = Vector3(0, 0, ang)
		root.add_child(spoke_root)
		# Arm from hub toward rim.
		var arm := BoxMesh.new()
		arm.size = Vector3(0.028, 0.118, 0.016)
		var arm_mi := MeshInstance3D.new()
		arm_mi.mesh = arm
		arm_mi.position = Vector3(0, 0.062, 0)
		arm_mi.material_override = chrome
		spoke_root.add_child(arm_mi)
		# Wider plate near hub.
		var plate := BoxMesh.new()
		plate.size = Vector3(0.05, 0.035, 0.014)
		var plate_mi := MeshInstance3D.new()
		plate_mi.mesh = plate
		plate_mi.position = Vector3(0, 0.028, 0)
		plate_mi.material_override = chrome
		spoke_root.add_child(plate_mi)

	# Column stub behind hub (depth cue).
	var col := CylinderMesh.new()
	col.top_radius = 0.018
	col.bottom_radius = 0.022
	col.height = 0.08
	var col_mi := MeshInstance3D.new()
	col_mi.mesh = col
	col_mi.rotation_degrees = Vector3(90, 0, 0)
	col_mi.position = Vector3(0, 0, 0.05)
	col_mi.material_override = chrome
	root.add_child(col_mi)



func _add_part(parent: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	elif mesh is SphereMesh:
		(mesh as SphereMesh).radius = size.x * 0.5
		(mesh as SphereMesh).height = size.y
	elif mesh is CapsuleMesh:
		(mesh as CapsuleMesh).radius = size.x * 0.5
		(mesh as CapsuleMesh).height = maxf(size.y, size.x + 0.01)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _setup_audio() -> void:
	var engine_stream: AudioStream = load("res://assets/audio/engine_loop_3.wav")
	if engine_stream is AudioStreamWAV:
		var wav := engine_stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = -1
	engine_player.stream = engine_stream
	engine_player.bus = "Engine"
	engine_player.volume_db = -8.0
	engine_player.play()

	var skid_stream: AudioStream = load("res://assets/audio/tires_squal_loop.wav")
	if skid_stream is AudioStreamWAV:
		var sw := skid_stream as AudioStreamWAV
		sw.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sw.loop_end = -1
	skid_player.stream = skid_stream
	skid_player.bus = "Tires"
	skid_player.volume_db = -40.0
	skid_player.play()


func _unhandled_input(event: InputEvent) -> void:
	if is_wrecked:
		return
	if event.is_action_pressed("shift_up"):
		_manual_override = true
		_change_gear(gear + 1)
	elif event.is_action_pressed("shift_down"):
		_manual_override = true
		_change_gear(gear - 1)


func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)
	_scrape_timer = maxf(_scrape_timer - delta, 0.0)

	if is_wrecked:
		engine_force = 0.0
		brake = 40.0
		steering = 0.0
		if _crash_smoke:
			_crash_smoke.emitting = true
		telemetry.emit(speed_kmh, rpm, gear, 0.0, damage)
		return

	_read_input(delta)
	var forward := -global_transform.basis.z
	var speed_ms := linear_velocity.dot(forward)
	speed_kmh = speed_ms * 3.6

	_update_surface_grip()
	_shift_lock = maxf(_shift_lock - delta, 0.0)
	_update_gearbox(speed_ms)
	_update_engine(delta, speed_ms)
	_apply_steering(delta)
	_apply_brakes()
	_apply_weight_transfer()
	_apply_aero(speed_ms)
	_apply_anti_roll(delta)
	_apply_stability(delta)
	_update_slip_fx()
	_update_steering_wheel()
	_update_audio()
	_check_impacts(delta)
	_update_damage_fx()
	_maybe_auto_unstick(delta)
	_prev_velocity = linear_velocity
	telemetry.emit(speed_kmh, rpm, gear, slipping, damage)


func _read_input(delta: float) -> void:
	throttle_input = Input.get_action_strength("accelerate")
	throttle_input = maxf(throttle_input, _axis_trigger(JOY_AXIS_TRIGGER_RIGHT))
	throttle_input = maxf(throttle_input, TouchInput.throttle)

	var reverse_axis := Input.get_action_strength("brake")
	reverse_axis = maxf(reverse_axis, _axis_trigger(JOY_AXIS_TRIGGER_LEFT))
	reverse_axis = maxf(reverse_axis, TouchInput.brake)
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		reverse_axis = maxf(reverse_axis, 1.0)

	# Hold-to-turn with ease-in/out velocity (not click-to-full-lock).
	var key_axis := 0.0
	if Input.is_action_pressed("steer_left") or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		key_axis -= 1.0
	if Input.is_action_pressed("steer_right") or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		key_axis += 1.0
	key_axis = clampf(key_axis, -1.0, 1.0)

	var pad_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(pad_x) < 0.18:
		pad_x = 0.0
	else:
		pad_x = clampf(pad_x, -1.0, 1.0)

	var desired_axis := key_axis
	if absf(pad_x) > 0.05:
		desired_axis = pad_x
	# Touch / tilt steer overrides when active.
	if absf(TouchInput.steer) > 0.02:
		desired_axis = TouchInput.steer

	_integrate_steer_input(desired_axis, delta)

	handbrake_input = Input.get_action_strength("handbrake")
	if Input.is_physical_key_pressed(KEY_SHIFT):
		handbrake_input = 1.0
	handbrake_input = maxf(handbrake_input, TouchInput.handbrake)

	var space_brake := 1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0

	if reverse_axis > 0.1 and speed_kmh > 8.0 and gear >= 1:
		brake_input = reverse_axis
		throttle_input = 0.0
	elif reverse_axis > 0.4 and speed_kmh < 12.0:
		if gear != 0:
			_change_gear(0)
		throttle_input = reverse_axis
		brake_input = space_brake
	else:
		brake_input = maxf(space_brake, reverse_axis if speed_kmh > 4.0 and throttle_input < 0.1 else 0.0)
		if gear == 0 and throttle_input > 0.15 and reverse_axis < 0.1:
			_change_gear(1)

	brake_input = clampf(maxf(brake_input, handbrake_input * 0.35), 0.0, 1.0)
	throttle_input = clampf(throttle_input, 0.0, 1.0)


func _integrate_steer_input(desired: float, delta: float) -> void:
	## Smooth accel/decel toward desired axis with ease near ends.
	var returning := absf(desired) < 0.01
	var target := desired
	var err := target - steer_input
	var accel := steer_return_accel if returning else steer_accel
	var max_rate := steer_return_max_rate if returning else steer_max_rate
	# Mild ease-out near target; keep initial response snappy.
	var ease := smoothstep(0.0, 1.0, absf(err))
	ease = lerpf(0.55, 1.0, ease)
	var want_vel := signf(err) * max_rate * ease
	if returning:
		want_vel = -signf(steer_input) * max_rate * ease if absf(steer_input) > 0.001 else 0.0
		if absf(steer_input) < 0.02:
			steer_input = 0.0
			_steer_velocity = 0.0
			return
	_steer_velocity = move_toward(_steer_velocity, want_vel, accel * delta)
	steer_input = clampf(steer_input + _steer_velocity * delta, -1.0, 1.0)
	if returning and signf(steer_input) != signf(steer_input + _steer_velocity * delta) and absf(steer_input) < 0.05:
		steer_input = 0.0
		_steer_velocity = 0.0


func _axis_trigger(axis: int) -> float:
	var v := Input.get_joy_axis(0, axis)
	if v < 0.0:
		v = (v + 1.0) * 0.5
	return clampf(v, 0.0, 1.0)


func _change_gear(next: int) -> void:
	next = clampi(next, 0, 5)
	if next == gear:
		return
	gear = next
	_shift_lock = 0.16
	rpm = lerpf(rpm, IDLE_RPM + 400.0, 0.35)


func _update_gearbox(_speed_ms: float) -> void:
	if not auto_shift or _manual_override or _shift_lock > 0.0:
		return
	if gear == 0:
		return
	if rpm > 6400.0 and gear < 5 and throttle_input > 0.2:
		_change_gear(gear + 1)
	elif rpm < 2200.0 and gear > 1 and speed_kmh > 8.0:
		_change_gear(gear - 1)
	elif speed_kmh < 4.0 and throttle_input < 0.05 and gear > 1:
		_change_gear(1)


func _torque_at(engine_rpm: float) -> float:
	var n := clampf(engine_rpm, 700.0, REDLINE_RPM + 400.0)
	var x := (n - PEAK_TORQUE_RPM) / 2600.0
	var shape := exp(-x * x * 1.05)
	var idle_fill := clampf((n - 700.0) / 1300.0, 0.40, 1.0)
	return PEAK_TORQUE * lerpf(0.58, 1.0, shape) * idle_fill


func _update_engine(delta: float, speed_ms: float) -> void:
	var ratio: float = GEAR_RATIOS[gear]
	var driven_rpm := 0.0
	driven_rpm += absf(wheel_bl.get_rpm())
	driven_rpm += absf(wheel_br.get_rpm())
	driven_rpm *= 0.5

	var target_rpm: float
	if absf(ratio) < 0.01:
		target_rpm = lerpf(IDLE_RPM, 3500.0, throttle_input)
	else:
		target_rpm = driven_rpm * absf(ratio) * FINAL_DRIVE
		if absf(speed_ms) < 0.4 and throttle_input < 0.05:
			target_rpm = IDLE_RPM

	if _shift_lock > 0.0:
		target_rpm = lerpf(rpm, IDLE_RPM + throttle_input * 1800.0, 0.4)

	var rpm_lerp := 8.0 if target_rpm < rpm else 13.0
	rpm = lerpf(rpm, clampf(target_rpm, IDLE_RPM * 0.85, REDLINE_RPM + 350.0), 1.0 - exp(-delta * rpm_lerp))

	var throttle_eff := throttle_input
	if rpm > REDLINE_RPM:
		throttle_eff *= 0.12
	if _shift_lock > 0.08:
		throttle_eff *= 0.05
	# Damage cuts power progressively.
	var dmg_power := lerpf(1.0, 0.22, clampf(damage, 0.0, 1.0))
	throttle_eff *= dmg_power

	var torque := _torque_at(rpm) * throttle_eff
	var wheel_force := torque * absf(ratio) * FINAL_DRIVE / WHEEL_RADIUS * DRIVELINE_EFFICIENCY
	if gear == 0:
		wheel_force = -wheel_force
	if throttle_eff < 0.02:
		wheel_force = 0.0

	wheel_force = clampf(wheel_force, -MAX_ENGINE_FORCE, MAX_ENGINE_FORCE)
	_engine_force_smoothed = lerpf(_engine_force_smoothed, wheel_force, 1.0 - exp(-delta * 7.0))
	engine_force = _engine_force_smoothed


func _apply_steering(delta: float) -> void:
	var speed_factor := clampf(absf(speed_kmh) / 200.0, 0.0, 1.0)
	var max_steer := lerpf(max_steer_angle, min_steer_angle, speed_factor)
	# VehicleBody3D: positive steering = LEFT (faces −Z). Axis left=-1 → negate.
	var target := -steer_input * max_steer
	var steer_rate := lerpf(9.5, 5.8, speed_factor)
	steering = lerp_angle(steering, target, 1.0 - exp(-delta * steer_rate))


func _apply_brakes() -> void:
	var front := brake_input * brake_force * 0.64
	var rear := brake_input * brake_force * 0.36
	rear += handbrake_input * handbrake_force
	wheel_fl.brake = front
	wheel_fr.brake = front
	wheel_bl.brake = rear
	wheel_br.brake = rear
	var base_f := 5.0 * _surface_grip
	var base_r := 4.65 * _surface_grip
	var rear_grip := lerpf(base_r, 2.2 * _surface_grip, handbrake_input)
	wheel_fl.wheel_friction_slip = base_f
	wheel_fr.wheel_friction_slip = base_f
	wheel_bl.wheel_friction_slip = rear_grip
	wheel_br.wheel_friction_slip = rear_grip
	brake = brake_input * 2.0


func _update_surface_grip() -> void:
	# Asphalt ≈1.0, gravel ≈0.72, grass/apron ≈0.55 — from world lateral query.
	if _world and _world.has_method("surface_grip_at"):
		_surface_grip = _world.surface_grip_at(global_position)
	else:
		_surface_grip = 1.0


func _apply_weight_transfer() -> void:
	var local_vel := global_transform.basis.inverse() * linear_velocity
	var long_a := clampf((-local_vel.z) * 0.022 + engine_force * 0.000035 - brake_input * 0.38, -1.0, 1.0)
	var lat_a := clampf(local_vel.x * 0.032, -1.0, 1.0)
	# Lower CG + more transfer for planted feel without tippiness.
	center_of_mass = Vector3(lat_a * 0.05, -0.38 - long_a * 0.035, 0.04 - long_a * 0.12)


func _apply_aero(speed_ms: float) -> void:
	var v2 := speed_ms * speed_ms
	apply_central_force(Vector3.DOWN * v2 * 4.4)
	apply_central_force(global_transform.basis.z * v2 * 0.28 * signf(speed_ms))


func _apply_anti_roll(_delta: float) -> void:
	var up := global_transform.basis.y
	var tilt := up.cross(Vector3.UP)
	var amount := tilt.length()
	if amount > 0.015 and up.dot(Vector3.UP) > 0.2:
		apply_torque(tilt.normalized() * amount * 7800.0)


func _apply_stability(delta: float) -> void:
	var max_yaw := lerpf(MAX_YAW_RATE, 1.05, clampf(absf(speed_kmh) / 160.0, 0.0, 1.0))
	if absf(angular_velocity.y) > max_yaw:
		angular_velocity.y = signf(angular_velocity.y) * max_yaw

	if slipping > 0.28 and absf(speed_kmh) > 12.0:
		var damp_k := clampf((slipping - 0.28) / 0.5, 0.0, 1.0)
		angular_velocity.y = lerpf(angular_velocity.y, 0.0, 1.0 - exp(-delta * (3.8 + damp_k * 8.0)))
		engine_force *= lerpf(1.0, 0.25, damp_k)
		if signf(angular_velocity.y) == signf(steering) and absf(steering) > 0.05:
			angular_velocity.y *= 0.90


func _update_slip_fx() -> void:
	var wheels: Array[VehicleWheel3D] = [wheel_fl, wheel_fr, wheel_bl, wheel_br]
	var smokes: Array[GPUParticles3D] = [smoke_fl, smoke_fr, smoke_bl, smoke_br]
	var worst := 1.0
	var right := global_transform.basis.x
	var grounded := 0
	for i in wheels.size():
		var info := wheels[i].get_skidinfo()
		worst = minf(worst, info)
		if wheels[i].is_in_contact():
			grounded += 1
		var emit := info < 0.48 and absf(speed_kmh) > 10.0
		if smokes[i]:
			smokes[i].emitting = emit
		if skid_marks and emit:
			var contact: Vector3 = wheels[i].global_position
			contact += Vector3.DOWN * (WHEEL_RADIUS * 0.92)
			var strength := clampf((0.48 - info) / 0.48, 0.0, 1.0)
			skid_marks.add_mark(contact, right, strength)
	slipping = clampf(1.0 - worst, 0.0, 1.0)
	if grounded == 0:
		_airborne_timer += get_physics_process_delta_time()
	else:
		_airborne_timer = 0.0


func _maybe_auto_unstick(delta: float) -> void:
	## If nearly stopped against Armco/barrier for a few seconds, nudge free.
	if is_wrecked or _collision_disabled:
		_unstick_timer = 0.0
		return
	var against_barrier := false
	if contact_monitor:
		for b in get_colliding_bodies():
			if b is StaticBody3D and String((b as Node).name).begins_with("OuterBarrier"):
				against_barrier = true
				break
	var nearly_stopped := linear_velocity.length() < 1.6 and absf(speed_kmh) < 4.0
	if against_barrier and nearly_stopped:
		_unstick_timer += delta
	else:
		_unstick_timer = maxf(_unstick_timer - delta * 0.5, 0.0)
	if _unstick_timer < 2.8:
		return
	_unstick_timer = 0.0
	# Impulse toward track center (inboard) + slight lift.
	var inward := -global_transform.basis.x
	if _world:
		inward = _world.centerline_inward_at(global_position)
	apply_central_impulse(inward.normalized() * mass * 3.2 + Vector3.UP * mass * 1.1)
	apply_torque_impulse(global_transform.basis.y * mass * 0.15)


func _update_steering_wheel() -> void:
	if _steer_wheel == null:
		return
	var wheel_deg := rad_to_deg(steering) * (450.0 / rad_to_deg(max_steer_angle))
	# Keep base cockpit tilt on X; steer rotates around wheel axis (Z).
	_steer_wheel.rotation = Vector3(deg_to_rad(-28.0), 0.0, deg_to_rad(wheel_deg))


func _check_impacts(_delta: float) -> void:
	# Cliff / void freefall → critical wreck then auto-restart (via game).
	if global_position.y < -6.0:
		_apply_damage(1.0, Vector3(0, 1, 0), true)
		return

	var delta_v := (_prev_velocity - linear_velocity).length()
	var prev_speed := _prev_velocity.length()

	# Hard landing after airborne.
	if _airborne_timer > 0.35 and _prev_velocity.y < -10.0 and linear_velocity.y > _prev_velocity.y + 5.0:
		var land_sev := clampf((-_prev_velocity.y - 8.0) / 22.0, 0.0, 1.0)
		var dir := Vector3(0, 1, 0)
		if absf(_prev_velocity.x) + absf(_prev_velocity.z) > 2.0:
			dir = global_transform.basis.inverse() * (-_prev_velocity.normalized())
		_apply_damage(land_sev * 0.85, dir, land_sev > 0.75)
		return

	if _impact_cooldown > 0.0:
		return

	# Speed-dependent collision impulse approximation.
	if delta_v > 6.5 and prev_speed > 6.0:
		var sev := clampf((delta_v - 6.0) / 28.0, 0.0, 1.0)
		var world_dir := (_prev_velocity - linear_velocity)
		if world_dir.length() < 0.01:
			world_dir = -_prev_velocity
		var local_dir := global_transform.basis.inverse() * world_dir.normalized()
		_apply_damage(sev * 0.7, local_dir, sev > 0.85 and prev_speed > 22.0)
		_impact_cooldown = 0.35


func _on_body_entered(body: Node) -> void:
	if is_wrecked:
		return
	if body is StaticBody3D and (body as StaticBody3D).name == "CrashFloor":
		_apply_damage(1.0, Vector3(0, 1, 0), true)
		return
	if body is StaticBody3D:
		var rel := linear_velocity.length()
		if rel > 10.0:
			var name_s := (body as StaticBody3D).name
			var local_dir := global_transform.basis.inverse() * (-linear_velocity.normalized())
			var sev := clampf((rel - 8.0) / 35.0, 0.0, 1.0)
			if name_s == "OuterBarrier":
				sev = maxf(sev, 0.35)
			_apply_damage(sev * 0.55, local_dir, sev > 0.9)
			if rel > 8.0 and damage > 0.35:
				_play_scrape()


func _apply_damage(severity: float, local_dir: Vector3, force_critical: bool = false) -> void:
	if is_wrecked:
		return
	severity = clampf(severity, 0.0, 1.0)
	if severity < 0.04 and not force_critical:
		return

	var add := severity * lerpf(0.18, 0.55, severity)
	damage = clampf(damage + add, 0.0, 1.0)
	damage_changed.emit(damage)

	_deform_visual(local_dir, severity)
	_play_impact_sound(severity)

	if _spark_fx and severity > 0.35:
		_spark_fx.restart()
		_spark_fx.emitting = true

	if force_critical or damage >= CRITICAL_DAMAGE:
		_enter_wreck()


func _deform_visual(local_dir: Vector3, severity: float) -> void:
	local_dir = local_dir.normalized() if local_dir.length() > 0.01 else Vector3(0, 0, -1)
	var amount := severity * lerpf(0.04, 0.22, clampf(damage, 0.0, 1.0))

	# Vertex crumple on body meshes (practical approximation — not soft-body).
	for i in _body_mesh_instances.size():
		var mi := _body_mesh_instances[i]
		if mi.mesh == null:
			continue
		var am := ArrayMesh.new()
		var src: Mesh = mi.mesh
		for s in src.get_surface_count():
			var arrs := src.surface_get_arrays(s)
			var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL] if arrs[Mesh.ARRAY_NORMAL] else PackedVector3Array()
			for vi in verts.size():
				var v: Vector3 = verts[vi]
				var n: Vector3 = normals[vi] if vi < normals.size() else v.normalized()
				# Push vertices that face the impact inward.
				var facing := n.dot(-local_dir)
				if facing < 0.05:
					continue
				var along := v.dot(local_dir)
				var influence := facing * (0.55 + 0.45 * clampf(absf(along) * 0.4, 0.0, 1.0))
				verts[vi] = v + local_dir * (amount * influence * VISUAL_SCALE * 0.55)
				# Slight lateral squash for side hits.
				if absf(local_dir.x) > 0.55:
					verts[vi].x += local_dir.x * amount * influence * 0.35
			arrs[Mesh.ARRAY_VERTEX] = verts
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
			if src.surface_get_material(s):
				am.surface_set_material(s, src.surface_get_material(s))
		mi.mesh = am

	# Zone panels bend/offset by impact direction.
	for p in _panel_parts:
		var node: MeshInstance3D = p["node"]
		var zone: String = p["zone"]
		var align := 0.0
		match zone:
			"NosePanel", "HoodPanel":
				align = maxf(0.0, -local_dir.z)
			"TailPanel":
				align = maxf(0.0, local_dir.z)
			"SideL":
				align = maxf(0.0, -local_dir.x)
			"SideR":
				align = maxf(0.0, local_dir.x)
			"RoofPanel":
				align = maxf(0.0, local_dir.y)
			_:
				align = 0.3
		if align < 0.15 and severity < 0.5:
			continue
		node.visible = (damage > 0.2) and not _fps_mode
		var mat := node.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.12, 0.12, 0.13, clampf(damage * 0.55, 0.0, 0.7))
		node.position = p["base_pos"] + local_dir * amount * align * 2.2
		node.rotation = p["base_rot"] + Vector3(
			local_dir.z * amount * align * 1.4,
			0.0,
			-local_dir.x * amount * align * 1.4
		)

	# Detach bumper on hard frontal hit.
	if _bumper and -local_dir.z > 0.5 and severity > 0.55 and damage > 0.45:
		_bumper.position += Vector3(local_dir.x * 0.4, -0.15, local_dir.z * 0.6)
		_bumper.rotation += Vector3(0.4, local_dir.x * 0.8, 0.2)
		if damage > 0.75 or _fps_mode:
			_bumper.visible = false

	# Broken windshield on severe frontal / roof hit.
	if _broken_glass and damage > 0.55 and (-local_dir.z > 0.4 or local_dir.y > 0.5):
		_broken_glass.visible = not _fps_mode
		_broken_glass.rotation = Vector3(deg_to_rad(8), 0, local_dir.x * 0.15)


func _restore_meshes() -> void:
	for i in _body_mesh_instances.size():
		if i < _body_mesh_backups.size() and _body_mesh_backups[i]:
			_body_mesh_instances[i].mesh = _body_mesh_backups[i].duplicate()


func _reset_panels() -> void:
	for p in _panel_parts:
		var node: MeshInstance3D = p["node"]
		node.position = p["base_pos"]
		node.rotation = p["base_rot"]
		node.visible = false
		var mat := node.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.15, 0.16, 0.18, 0.0)


func _update_damage_fx() -> void:
	if _crash_smoke:
		_crash_smoke.emitting = damage > 0.55 and not is_wrecked or is_wrecked
		if damage > 0.55:
			_crash_smoke.amount = int(lerpf(24, 48, damage))


func _enter_wreck() -> void:
	if is_wrecked:
		return
	is_wrecked = true
	damage = 1.0
	damage_changed.emit(damage)
	engine_force = 0.0
	brake = 60.0
	steering = 0.0
	linear_velocity *= 0.4
	angular_velocity *= 0.45
	if _crash_smoke:
		_crash_smoke.emitting = true
	if _spark_fx:
		_spark_fx.restart()
		_spark_fx.emitting = true
	_play_impact_sound(1.0)
	if engine_player:
		engine_player.stop()
	wrecked.emit()
	# Soft freeze after brief settle — game.gd restarts after delay.
	var seq := _reset_seq
	get_tree().create_timer(0.45).timeout.connect(func():
		if is_wrecked and seq == _reset_seq:
			freeze = true
	)


func _play_impact_sound(severity: float) -> void:
	if _crash_audio == null:
		return
	var paths := [
		"res://assets/audio/crash_metal_0.ogg",
		"res://assets/audio/crash_metal_1.ogg",
		"res://assets/audio/crash_plate_0.ogg",
	]
	var path: String = paths[randi() % paths.size()]
	var stream: AudioStream = load(path)
	if stream:
		_crash_audio.stream = stream
		_crash_audio.pitch_scale = randf_range(0.85, 1.12)
		_crash_audio.volume_db = lerpf(-10.0, -1.0, clampf(severity, 0.0, 1.0))
		_crash_audio.play()


func _play_scrape() -> void:
	if _scrape_audio == null or _scrape_timer > 0.0:
		return
	_scrape_timer = 0.6
	var stream: AudioStream = load("res://assets/audio/crash_plate_0.ogg")
	if stream:
		_scrape_audio.stream = stream
		_scrape_audio.pitch_scale = randf_range(0.7, 0.95)
		_scrape_audio.volume_db = -14.0
		_scrape_audio.play()


func _update_audio() -> void:
	var rpm_t := clampf((rpm - IDLE_RPM) / (REDLINE_RPM - IDLE_RPM), 0.0, 1.2)
	engine_player.pitch_scale = lerpf(0.55, 2.22, rpm_t)
	var vol := lerpf(-16.0, -3.5, clampf(throttle_input * 0.7 + rpm_t * 0.3, 0.0, 1.0))
	if damage > 0.4:
		vol -= damage * 4.0
		engine_player.pitch_scale *= lerpf(1.0, 0.88, damage)
	engine_player.volume_db = vol

	var skid_vol := lerpf(-48.0, -5.0, clampf((slipping - 0.32) / 0.5, 0.0, 1.0))
	if absf(speed_kmh) < 10.0:
		skid_vol = -48.0
	skid_player.volume_db = skid_vol
	skid_player.pitch_scale = lerpf(0.85, 1.18, clampf(slipping, 0.0, 1.0))


func gear_label() -> String:
	if gear == 0:
		return "R"
	return str(gear)
