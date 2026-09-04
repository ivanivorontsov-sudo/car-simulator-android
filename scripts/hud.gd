extends CanvasLayer
class_name DrivingHUD

@onready var speed_label: Label = $Root/SpeedBox/VBox/Speed
@onready var gear_label: Label = $Root/GearBox/Gear
@onready var rpm_bar: ProgressBar = $Root/RpmBox/RpmBar
@onready var rpm_text: Label = $Root/RpmBox/RpmText
@onready var cam_label: Label = $Root/CamLabel
@onready var hint: Label = $Root/Hint
@onready var tach: Tachometer = $Root/Tach
@onready var damage_bar: ProgressBar = $Root/DamageBox/DamageBar
@onready var damage_label: Label = $Root/DamageBox/DamageLabel
@onready var wreck_label: Label = $Root/WreckLabel


func _ready() -> void:
	if wreck_label:
		wreck_label.visible = false
	set_damage(0.0)


func update_telemetry(speed_kmh: float, rpm: float, gear_text: String, slipping: float, damage: float = -1.0) -> void:
	speed_label.text = str(int(round(absf(speed_kmh))))
	gear_label.text = gear_text
	rpm_bar.max_value = 7500.0
	rpm_bar.value = rpm
	rpm_text.text = "%d RPM" % int(rpm)
	var fill := rpm_bar.get("theme_override_styles/fill") as StyleBoxFlat
	if fill:
		if rpm > 6800.0:
			fill.bg_color = Color(0.92, 0.18, 0.22)
		elif rpm > 5400.0:
			fill.bg_color = Color(0.95, 0.72, 0.15)
		else:
			fill.bg_color = Color(0.25, 0.85, 0.55)
	if slipping > 0.55:
		gear_label.modulate = Color(1.0, 0.55, 0.35)
	else:
		gear_label.modulate = Color.WHITE
	if tach:
		tach.set_reading(rpm, gear_text, slipping)
	if damage >= 0.0:
		set_damage(damage)


func set_damage(damage: float) -> void:
	if damage_bar == null:
		return
	damage_bar.value = clampf(damage, 0.0, 1.0) * 100.0
	var dfill := damage_bar.get("theme_override_styles/fill") as StyleBoxFlat
	if dfill:
		if damage >= 0.85:
			dfill.bg_color = Color(0.9, 0.15, 0.12)
		elif damage >= 0.45:
			dfill.bg_color = Color(0.95, 0.55, 0.12)
		else:
			dfill.bg_color = Color(0.35, 0.75, 0.4)
	if damage_label:
		damage_label.text = "DMG  %d%%" % int(round(clampf(damage, 0.0, 1.0) * 100.0))


func set_camera_name(cam_name: String) -> void:
	cam_label.text = ("CAM  %s" % cam_name) if (OS.has_feature("android") or OS.has_feature("ios")) else ("CAM  %s  (C)" % cam_name)


func hide_hint() -> void:
	hint.visible = false


func show_wreck(seconds: float) -> void:
	if wreck_label == null:
		return
	wreck_label.visible = true
	wreck_label.text = "CRASH — restart in %d…" % int(ceil(seconds))


func set_wreck_countdown(seconds: int) -> void:
	if wreck_label == null:
		return
	wreck_label.visible = true
	wreck_label.text = "CRASH — restart in %d…" % seconds


func clear_wreck() -> void:
	if wreck_label:
		wreck_label.visible = false


func set_mobile_hints() -> void:
	if hint:
		hint.text = "Steer pad / tilt · GAS · BRAKE · HB · CAM · RESET"

