extends CanvasLayer
class_name TouchControls
## On-screen driving overlay (landscape phones). Keyboard still works in editor.

@onready var steer_pad: Control = $Root/SteerPad
@onready var steer_knob: Control = $Root/SteerPad/Knob
@onready var btn_gas: Button = $Root/RightButtons/Gas
@onready var btn_brake: Button = $Root/RightButtons/Brake
@onready var btn_handbrake: Button = $Root/TopButtons/Handbrake
@onready var btn_cam: Button = $Root/TopButtons/Camera
@onready var btn_reset: Button = $Root/TopButtons/Reset
@onready var btn_pause: Button = $Root/TopButtons/Pause

var _steer_touch_id: int = -1
var _use_tilt: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = _should_show()
	btn_gas.button_down.connect(func(): TouchInput.throttle = 1.0)
	btn_gas.button_up.connect(func(): TouchInput.throttle = 0.0)
	btn_brake.button_down.connect(func(): TouchInput.brake = 1.0)
	btn_brake.button_up.connect(func(): TouchInput.brake = 0.0)
	btn_handbrake.button_down.connect(func(): TouchInput.handbrake = 1.0)
	btn_handbrake.button_up.connect(func(): TouchInput.handbrake = 0.0)
	btn_cam.pressed.connect(func(): TouchInput.request_camera())
	btn_reset.pressed.connect(func(): TouchInput.request_reset())
	btn_pause.pressed.connect(func(): TouchInput.request_pause())
	# Optional device tilt assist when no finger is on the pad.
	_use_tilt = OS.has_feature("mobile")
	if _use_tilt:
		Input.set_use_accumulated_input(true)


func _should_show() -> bool:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return true
	# Show in editor / desktop for layout testing when DisplayServer reports touch.
	return DisplayServer.is_touchscreen_available()


func _process(_delta: float) -> void:
	if not visible:
		return
	if _steer_touch_id < 0 and _use_tilt:
		var grav := Input.get_gravity()
		# Landscape: roll around Z → left/right steer.
		var tilt := clampf(-grav.x / 4.5, -1.0, 1.0)
		if absf(tilt) < 0.12:
			tilt = 0.0
		# Only apply light tilt if pad not in use; keep gentle.
		TouchInput.steer = tilt * 0.85
		_update_knob(TouchInput.steer)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _point_in_steer(st.position):
			_steer_touch_id = st.index
			_apply_steer_from_pos(st.position)
			get_viewport().set_input_as_handled()
		elif not st.pressed and st.index == _steer_touch_id:
			_steer_touch_id = -1
			TouchInput.steer = 0.0
			_update_knob(0.0)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _steer_touch_id:
			_apply_steer_from_pos(sd.position)
			get_viewport().set_input_as_handled()
	# Mouse fallback for editor testing
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed and _point_in_steer(mb.position):
			_steer_touch_id = 0
			_apply_steer_from_pos(mb.position)
		elif not mb.pressed and _steer_touch_id == 0:
			_steer_touch_id = -1
			TouchInput.steer = 0.0
			_update_knob(0.0)
	elif event is InputEventMouseMotion and _steer_touch_id == 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_apply_steer_from_pos((event as InputEventMouseMotion).position)


func _point_in_steer(global_pos: Vector2) -> bool:
	var r := steer_pad.get_global_rect()
	return r.has_point(global_pos)


func _apply_steer_from_pos(global_pos: Vector2) -> void:
	var r := steer_pad.get_global_rect()
	var local_x := (global_pos.x - r.position.x) / maxf(r.size.x, 1.0)
	var axis := clampf((local_x - 0.5) * 2.0, -1.0, 1.0)
	TouchInput.steer = axis
	_update_knob(axis)


func _update_knob(axis: float) -> void:
	if steer_knob == null:
		return
	var pad_w := steer_pad.size.x
	var pad_h := steer_pad.size.y
	var kw := steer_knob.size.x
	var kh := steer_knob.size.y
	steer_knob.position = Vector2(
		(pad_w - kw) * 0.5 + axis * (pad_w * 0.35),
		(pad_h - kh) * 0.5
	)
