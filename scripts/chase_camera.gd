extends Camera3D
class_name ChaseCamera

## Chase (third-person) and true first-person driver eye. FPS never lags behind
## the car — position is snapped to the cabin eye point every frame.

enum Mode { CHASE, FPS }

signal mode_changed(mode: Mode)

@export var chase_distance: float = 7.6
@export var chase_height: float = 2.45
@export var chase_look_height: float = 1.05
## Eye height above vehicle origin (through windshield, not roof).
@export var fps_eye_height: float = 1.20
## Along vehicle forward (−Z). Positive Z is rearward — sit behind the wheel.
@export var fps_eye_forward: float = 0.18
## Lateral — right-hand seat.
@export var fps_eye_lateral: float = 0.32
@export var follow_speed: float = 5.4
@export var look_speed: float = 7.5
@export var base_fov: float = 70.0
@export var fps_fov: float = 78.0
@export var max_fov: float = 88.0

var target: Node3D
var mode: Mode = Mode.CHASE
var _look_point: Vector3 = Vector3.ZERO
var _look_ready: bool = false


func _ready() -> void:
	near = 0.05
	far = 2000.0
	fov = base_fov


func toggle_mode() -> void:
	mode = Mode.FPS if mode == Mode.CHASE else Mode.CHASE
	_look_ready = false
	mode_changed.emit(mode)


func set_mode(m: Mode) -> void:
	if mode == m:
		return
	mode = m
	_look_ready = false
	mode_changed.emit(mode)


func mode_name() -> String:
	return "FPS" if mode == Mode.FPS else "CHASE"


func is_fps() -> bool:
	return mode == Mode.FPS


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var speed := 0.0
	var vel := Vector3.ZERO
	if target is RigidBody3D:
		vel = (target as RigidBody3D).linear_velocity
		speed = vel.length()
	var fwd := -target.global_transform.basis.z
	var right := target.global_transform.basis.x
	var steer := 0.0
	if target is PlayerCar:
		steer = (target as PlayerCar).steering
	var travel := fwd
	if speed > 5.0:
		var vd := vel.normalized()
		if vd.dot(fwd) > -0.15:
			travel = fwd.lerp(vd, 0.42).normalized()

	var speed_kmh := speed * 3.6

	if mode == Mode.FPS:
		_update_fps(delta, speed_kmh, steer)
	else:
		_update_chase(delta, speed_kmh, travel, right, steer)


func _update_fps(delta: float, speed_kmh: float, steer: float) -> void:
	# TRUE first-person: snap to eye — never lerp/lag behind on acceleration.
	# Eye behind the wheel (RHD), looking out through the windshield glass.
	var local_eye := Vector3(fps_eye_lateral + steer * 0.012, fps_eye_height, fps_eye_forward)
	global_position = target.global_transform * local_eye

	# Look point must stay near eye height: a near-ground look_y (e.g. 0.05) aims
	# steeply at the asphalt so the yellow center stripe fills the frame instead
	# of road-to-horizon through the windshield. Keep look_y ≈ eye height (±0.3).
	var look_local := Vector3(fps_eye_lateral * 0.15 - steer * 0.85, 1.00, -22.0)
	var look: Vector3 = target.global_transform * look_local
	if not _look_ready:
		_look_point = look
		_look_ready = true
	_look_point = _look_point.lerp(look, 1.0 - exp(-delta * 22.0))
	look_at(_look_point, Vector3.UP)
	# Tiny nose-down only — enough for a hint of dash/hood, not asphalt-fill.
	rotate_object_local(Vector3.RIGHT, deg_to_rad(-0.5))

	var fov_t := clampf(speed_kmh / 210.0, 0.0, 1.0)
	var fps_target := lerpf(fps_fov, max_fov, fov_t)
	fov = lerpf(fov, fps_target, 1.0 - exp(-delta * 2.4))


func _update_chase(delta: float, speed_kmh: float, travel: Vector3, right: Vector3, steer: float) -> void:
	var fov_t := clampf(speed_kmh / 210.0, 0.0, 1.0)
	fov = lerpf(fov, lerpf(base_fov, max_fov, fov_t), 1.0 - exp(-delta * 2.2))
	var dist := chase_distance + clampf(speed_kmh * 0.012, 0.0, 3.2)
	var height := chase_height + clampf(speed_kmh * 0.004, 0.0, 0.8)
	var desired: Vector3 = target.global_position - travel * dist + Vector3.UP * height
	desired.y = maxf(desired.y, target.global_position.y + 1.35)
	global_position = global_position.lerp(desired, 1.0 - exp(-delta * follow_speed))
	var look: Vector3 = (
		target.global_position
		+ Vector3.UP * chase_look_height
		+ travel * (5.5 + clampf(speed_kmh * 0.04, 0.0, 8.0))
		+ -right * steer * (7.5 + speed_kmh * 0.02)
	)
	if not _look_ready:
		_look_point = look
		_look_ready = true
	_look_point = _look_point.lerp(look, 1.0 - exp(-delta * look_speed))
	look_at(_look_point, Vector3.UP)
