extends Node
## Autoload: analog touch overlays + one-shot camera/reset/pause for Android.

var throttle: float = 0.0
var brake: float = 0.0
var steer: float = 0.0
var handbrake: float = 0.0

signal camera_requested
signal reset_requested
signal pause_requested


func clear_driving() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	handbrake = 0.0


func request_camera() -> void:
	camera_requested.emit()


func request_reset() -> void:
	reset_requested.emit()


func request_pause() -> void:
	pause_requested.emit()
