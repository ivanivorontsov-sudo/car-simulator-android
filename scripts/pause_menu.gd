extends CanvasLayer
class_name PauseMenu

signal resumed
signal restarted
signal quit_requested

@onready var panel: Control = $Center/Panel


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Center/Panel/VBox/Resume.pressed.connect(func(): resumed.emit())
	$Center/Panel/VBox/Restart.pressed.connect(func(): restarted.emit())
	$Center/Panel/VBox/Quit.pressed.connect(func(): quit_requested.emit())


func show_menu() -> void:
	visible = true
	$Center/Panel/VBox/Resume.grab_focus()


func hide_menu() -> void:
	visible = false
