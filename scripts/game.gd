extends Node3D


@onready var world: WorldBuilder = $World
@onready var car: PlayerCar = $Car
@onready var camera: ChaseCamera = $ChaseCamera
@onready var hud: DrivingHUD = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu

var _hint_timer: float = 8.0
var _restart_pending: bool = false
var _wreck_timer: float = 0.0
const WRECK_RESTART_SEC := 5.0


func _ready() -> void:
	world.build()
	car.set_spawn(world.spawn_transform)
	camera.target = car
	camera.current = true
	hud.set_camera_name(camera.mode_name())
	car.telemetry.connect(_on_telemetry)
	car.wrecked.connect(_on_wrecked)
	car.damage_changed.connect(_on_damage)
	camera.mode_changed.connect(_on_camera_mode)
	pause_menu.resumed.connect(_set_paused.bind(false))
	pause_menu.restarted.connect(_restart)
	pause_menu.quit_requested.connect(func(): get_tree().quit())
	car.set_fps_view(camera.is_fps())
	TouchInput.camera_requested.connect(_on_touch_camera)
	TouchInput.reset_requested.connect(_on_touch_reset)
	TouchInput.pause_requested.connect(_on_touch_pause)
	if OS.has_feature("android") or OS.has_feature("ios"):
		hud.set_mobile_hints()


func _process(delta: float) -> void:
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			hud.hide_hint()
	if _restart_pending:
		_wreck_timer -= delta
		hud.set_wreck_countdown(maxi(ceili(_wreck_timer), 0))
		if _wreck_timer <= 0.0:
			_restart_pending = false
			hud.clear_wreck()
			_restart()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset") and not get_tree().paused:
		_restart_pending = false
		hud.clear_wreck()
		_restart()
	elif event.is_action_pressed("camera_toggle") and not get_tree().paused:
		camera.toggle_mode()
		hud.set_camera_name(camera.mode_name())
	elif event.is_action_pressed("toggle_fullscreen"):
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_telemetry(speed_kmh: float, rpm: float, gear: int, slipping: float, damage: float) -> void:
	var g := "R" if gear == 0 else str(gear)
	hud.update_telemetry(speed_kmh, rpm, g, slipping, damage)


func _on_damage(damage: float) -> void:
	hud.set_damage(damage)


func _on_wrecked() -> void:
	if _restart_pending:
		return
	_restart_pending = true
	_wreck_timer = WRECK_RESTART_SEC
	hud.show_wreck(WRECK_RESTART_SEC)


func _on_camera_mode(mode: ChaseCamera.Mode) -> void:
	car.set_fps_view(mode == ChaseCamera.Mode.FPS)
	hud.set_camera_name(camera.mode_name())


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	if p:
		pause_menu.show_menu()
	else:
		pause_menu.hide_menu()


func _restart() -> void:
	## Shared hard reset path for R key, pause Restart, and wreck countdown.
	Engine.time_scale = 1.0
	_set_paused(false)
	_restart_pending = false
	_wreck_timer = 0.0
	hud.clear_wreck()
	# Ensure input is live again after pause / wreck.
	get_viewport().gui_release_focus()
	car.reset_vehicle()
	car.set_fps_view(camera.is_fps())
	camera.current = true


func _on_touch_camera() -> void:
	if get_tree().paused:
		return
	camera.toggle_mode()
	hud.set_camera_name(camera.mode_name())


func _on_touch_reset() -> void:
	if get_tree().paused:
		return
	_restart_pending = false
	hud.clear_wreck()
	_restart()


func _on_touch_pause() -> void:
	_set_paused(not get_tree().paused)

