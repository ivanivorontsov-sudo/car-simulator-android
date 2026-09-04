extends Control
class_name Tachometer

var rpm: float = 900.0
var redline: float = 7500.0
var gear: String = "1"
var slipping: float = 0.0


func set_reading(p_rpm: float, p_gear: String, p_slip: float) -> void:
	rpm = p_rpm
	gear = p_gear
	slipping = p_slip
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.42
	draw_circle(c, radius + 16.0, Color(0.05, 0.06, 0.08, 0.88))
	draw_arc(c, radius + 2.0, 0.0, TAU, 48, Color(0.95, 0.78, 0.22, 0.55), 2.0, true)

	var start_ang := deg_to_rad(140.0)
	var sweep := deg_to_rad(260.0)
	var max_rpm := 8000.0
	for i in 9:
		var t := float(i) / 8.0
		var ang := start_ang + sweep * t
		var dir := Vector2(cos(ang), sin(ang))
		var red := i >= 7
		var col := Color(0.92, 0.22, 0.22) if red else Color(0.92, 0.93, 0.95)
		draw_line(c + dir * (radius - 14.0), c + dir * (radius + 2.0), col, 2.5, true)
		var lbl := str(i)
		var font := ThemeDB.fallback_font
		var fs := 13
		var sz := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var lp := c + dir * (radius - 28.0) - sz * 0.5
		draw_string(font, lp, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# Needle
	var nt := clampf(rpm / max_rpm, 0.0, 1.05)
	var nang := start_ang + sweep * nt
	var ndir := Vector2(cos(nang), sin(nang))
	var ncol := Color(0.95, 0.2, 0.18) if rpm > redline * 0.88 else Color(0.98, 0.92, 0.55)
	if slipping > 0.55:
		ncol = Color(1.0, 0.55, 0.28)
	draw_line(c - ndir * 12.0, c + ndir * (radius - 18.0), ncol, 3.0, true)
	draw_circle(c, 7.0, Color(0.12, 0.12, 0.14, 1.0))
	draw_circle(c, 3.5, ncol)

	var font2 := ThemeDB.fallback_font
	var gcol := Color(1.0, 0.55, 0.35) if slipping > 0.55 else Color(1.0, 0.92, 0.45)
	var gsz := font2.get_string_size(gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
	draw_string(font2, Vector2(c.x - gsz.x * 0.5, c.y + radius * 0.42), gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, gcol)
	var rpm_s := "%d" % int(rpm)
	var rsz := font2.get_string_size(rpm_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font2, Vector2(c.x - rsz.x * 0.5, c.y + radius * 0.58), rpm_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.78, 0.82))
