extends MeshInstance3D
class_name SkidMarks

## Cheap world-space tire marks. Ring-buffer of quads rebuilt when slipping.

const MAX_SEGS := 360
const HALF_WIDTH := 0.13
const MIN_SPACING := 0.38

var _pts: Array[Dictionary] = []
var _last_pos: Vector3 = Vector3(1e6, 1e6, 1e6)
var _dirty: bool = false
var _accum: float = 0.0


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_texture = load("res://assets/textures/skid.png")
	mat.albedo_color = Color(0.08, 0.07, 0.06, 0.82)
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat


func clear_marks() -> void:
	_pts.clear()
	mesh = null
	_last_pos = Vector3(1e6, 1e6, 1e6)


func add_mark(pos: Vector3, right: Vector3, strength: float) -> void:
	if strength < 0.12:
		return
	if pos.distance_to(_last_pos) < MIN_SPACING:
		return
	_last_pos = pos
	var r := right.normalized() * HALF_WIDTH
	_pts.append({
		"l": pos - r + Vector3.UP * 0.025,
		"r": pos + r + Vector3.UP * 0.025,
		"a": clampf(strength, 0.0, 1.0),
	})
	if _pts.size() > MAX_SEGS:
		_pts.remove_at(0)
	_dirty = true


func _process(delta: float) -> void:
	if not _dirty:
		return
	_accum += delta
	if _accum < 0.05:
		return
	_accum = 0.0
	_dirty = false
	_rebuild()


func _rebuild() -> void:
	if _pts.size() < 2:
		mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, _pts.size()):
		var a: Dictionary = _pts[i - 1]
		var b: Dictionary = _pts[i]
		if (a["l"] as Vector3).distance_to(b["l"]) > 3.5:
			continue
		var alpha := ((a["a"] as float) + (b["a"] as float)) * 0.5
		var col := Color(1, 1, 1, alpha * 0.75)
		st.set_color(col)
		st.set_uv(Vector2(0, 0))
		st.add_vertex(a["l"])
		st.set_uv(Vector2(1, 0))
		st.add_vertex(a["r"])
		st.set_uv(Vector2(1, 1))
		st.add_vertex(b["r"])
		st.set_color(col)
		st.set_uv(Vector2(0, 0))
		st.add_vertex(a["l"])
		st.set_uv(Vector2(1, 1))
		st.add_vertex(b["r"])
		st.set_uv(Vector2(0, 1))
		st.add_vertex(b["l"])
	st.generate_normals()
	mesh = st.commit()
