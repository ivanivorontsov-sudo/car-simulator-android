extends Node3D
class_name WorldBuilder

## Closed asphalt circuit with continuous-height runoff, then a real cliff drop
## beyond the apron (no infinite flat collider catching the car).

var spawn_transform: Transform3D = Transform3D.IDENTITY
var _centerline: PackedVector3Array = PackedVector3Array()

## ~20 m full asphalt width (real-road feel).
const TRACK_HALF_WIDTH := 10.0
const RUMBLE_WIDTH := 0.95
const SHOULDER_WIDTH := 9.5
## Soft runoff before the cliff rim.
const APRON_WIDTH := 6.5
const SEGMENTS := 440
const ROAD_LIFT := 0.02
const CLIFF_DEPTH := 30.0

const _SHOULDER_START := TRACK_HALF_WIDTH + RUMBLE_WIDTH
const _APRON_START := TRACK_HALF_WIDTH + RUMBLE_WIDTH + SHOULDER_WIDTH
## Collision ends here (rim). Visual cliff continues below.
const _RIM := TRACK_HALF_WIDTH + RUMBLE_WIDTH + SHOULDER_WIDTH + APRON_WIDTH
const _WALL_OFFSET := TRACK_HALF_WIDTH + RUMBLE_WIDTH + SHOULDER_WIDTH + APRON_WIDTH * 0.35
## Kept for verify_track.gd compatibility (rim == former apron end).
const _APRON_END := _RIM


func build() -> void:
	_setup_environment()
	var centerline := _make_centerline()
	_centerline = centerline
	_build_infield(centerline)
	_build_track(centerline)
	_build_cliffs(centerline)
	_build_crash_floor()
	_place_props(centerline)
	_place_parked_cars(centerline)
	_compute_spawn(centerline)



func surface_grip_at(world_pos: Vector3) -> float:
	## Asphalt 1.0, gravel/shoulder ~0.72, grass apron ~0.55, unknown 0.85.
	if _centerline.is_empty():
		return 1.0
	var best_d := 1e9
	var best_lat := 0.0
	var n := _centerline.size()
	var step := maxi(1, int(n / 80))
	for i in range(0, n, step):
		var f := _frame_at(_centerline, i)
		var p: Vector3 = f["p"]
		var right: Vector3 = f["right"]
		var delta := world_pos - p
		delta.y = 0.0
		var d := delta.length()
		if d < best_d:
			best_d = d
			best_lat = delta.dot(right)
	var ad := absf(best_lat)
	if ad <= TRACK_HALF_WIDTH:
		return 1.0
	if ad <= _SHOULDER_START:
		return 0.88  # rumble
	if ad <= _APRON_START:
		return 0.72  # gravel
	if ad <= _RIM:
		return 0.55  # grass apron
	return 0.45


func centerline_inward_at(world_pos: Vector3) -> Vector3:
	## Unit vector from world_pos toward the nearest centerline point (XZ).
	if _centerline.is_empty():
		var fallback := Vector3(-world_pos.x, 0.0, -world_pos.z)
		return fallback.normalized() if fallback.length() > 0.01 else Vector3.FORWARD
	var best_i := 0
	var best_d := INF
	var n := _centerline.size()
	var step := maxi(1, n / 80)
	var i := 0
	while i < n:
		var d: float = Vector2(world_pos.x - _centerline[i].x, world_pos.z - _centerline[i].z).length_squared()
		if d < best_d:
			best_d = d
			best_i = i
		i += step
	var f := _frame_at(_centerline, best_i)
	var to_center: Vector3 = f["p"] - world_pos
	to_center.y = 0.0
	if to_center.length() < 0.01:
		# On center — use opposite of outward.
		var outward: Vector3 = f["right"] * _outward_sign(f)
		to_center = -outward
		to_center.y = 0.0
	return to_center.normalized()


func _setup_environment() -> void:
	var hdri: Texture2D = load("res://assets/hdri/kloofendal_43d_clear_2k.hdr")
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = hdri
	sky_mat.energy_multiplier = 1.28
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.58
	env.ambient_light_energy = 0.78
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.02
	env.ssao_enabled = true
	env.ssao_radius = 1.8
	env.ssao_intensity = 2.25
	env.ssil_enabled = true
	env.ssil_intensity = 0.9
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.08
	env.ssr_fade_out = 1.8
	env.glow_enabled = true
	env.glow_intensity = 0.58
	env.glow_bloom = 0.14
	env.glow_hdr_threshold = 0.82
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.78, 0.90)
	env.fog_density = 0.00035
	env.fog_aerial_perspective = 0.75
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0055
	env.volumetric_fog_albedo = Color(0.76, 0.83, 0.92)
	env.volumetric_fog_anisotropy = 0.28
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.14
	env.adjustment_contrast = 1.05
	env.adjustment_brightness = 1.03

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, 42.0, 0.0)
	sun.light_energy = 1.85
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.05
	sun.directional_shadow_max_distance = 380.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_specular = 1.05
	sun.light_angular_distance = 0.35
	add_child(sun)


func _make_centerline() -> PackedVector3Array:
	var ctrl: Array[Vector3] = [
		Vector3(124.0, 0.0, -14.0),
		Vector3(72.0, 0.0, -16.0),
		Vector3(18.0, 0.0, -20.0),
		Vector3(-28.0, 0.0, -38.0),
		Vector3(-62.0, 0.0, -64.0),
		Vector3(-108.0, 0.0, -52.0),
		Vector3(-142.0, 0.0, -12.0),
		Vector3(-128.0, 0.0, 36.0),
		Vector3(-88.0, 0.0, 70.0),
		Vector3(-46.0, 0.0, 54.0),
		Vector3(-14.0, 0.0, 78.0),
		Vector3(22.0, 0.0, 58.0),
		Vector3(52.0, 0.0, 82.0),
		Vector3(92.0, 0.0, 60.0),
		Vector3(128.0, 0.0, 74.0),
		Vector3(158.0, 0.0, 32.0),
		Vector3(150.0, 0.0, -6.0),
	]
	var nctrl := ctrl.size()
	var dense := PackedVector3Array()
	var samples_per := 28
	for i in nctrl:
		var p0: Vector3 = ctrl[(i - 1 + nctrl) % nctrl]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[(i + 1) % nctrl]
		var p3: Vector3 = ctrl[(i + 2) % nctrl]
		for s in samples_per:
			var t := float(s) / float(samples_per)
			dense.append(_catmull(p0, p1, p2, p3, t))
	var even := _resample_closed(dense, SEGMENTS)
	var total := 0.0
	var n := even.size()
	for i in n:
		total += even[i].distance_to(even[(i + 1) % n])
	var acc := 0.0
	for i in n:
		var a := acc / maxf(total, 0.001) * TAU
		# Elevated circuit so apron → cliff has real drop to void.
		var y := 6.5 + 1.55 * sin(a * 2.0) * 0.55 + 0.55 * sin(a * 3.2) + 0.22 * sin(a * 5.0)
		even[i].y = y
		acc += even[i].distance_to(even[(i + 1) % n])
	return even


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


func _resample_closed(src: PackedVector3Array, count: int) -> PackedVector3Array:
	var n := src.size()
	var cum := PackedFloat32Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	for i in n:
		cum[i + 1] = cum[i] + src[i].distance_to(src[(i + 1) % n])
	var total := cum[n]
	var out := PackedVector3Array()
	var si := 0
	for k in count:
		var target := total * float(k) / float(count)
		while si < n and cum[si + 1] < target:
			si += 1
		var span := cum[si + 1] - cum[si]
		var lt := 0.0 if span < 0.0001 else (target - cum[si]) / span
		out.append(src[si].lerp(src[(si + 1) % n], lt))
	return out


func _frame_at(pts: PackedVector3Array, i: int) -> Dictionary:
	var n := pts.size()
	var p: Vector3 = pts[i]
	var prev: Vector3 = pts[(i - 1 + n) % n]
	var nxt: Vector3 = pts[(i + 1) % n]
	var tangent: Vector3 = nxt - prev
	tangent.y = 0.0
	if tangent.length() < 0.0001:
		tangent = Vector3.FORWARD
	tangent = tangent.normalized()
	var right: Vector3 = Vector3.UP.cross(tangent).normalized()
	var up: Vector3 = tangent.cross(right).normalized()
	return {"p": p, "tangent": tangent, "right": right, "up": up}


func _outward_sign(f: Dictionary) -> float:
	var p: Vector3 = f["p"]
	var right: Vector3 = f["right"]
	var flat := Vector3(p.x, 0.0, p.z)
	return 1.0 if flat.dot(right) >= 0.0 else -1.0


func _surface_y(track_y: float, lateral: float) -> float:
	## Continuous: road + rumble + shoulder at track height, soft apron, then cliff drop.
	var ad := absf(lateral)
	if ad <= _APRON_START:
		return track_y
	if ad >= _RIM:
		return track_y - CLIFF_DEPTH
	var t := (ad - _APRON_START) / APRON_WIDTH
	t = clampf(t, 0.0, 1.0)
	# First 55%: gentle runoff (escapable). Last 45%: steep cliff face.
	if t < 0.55:
		var u := t / 0.55
		u = u * u * (3.0 - 2.0 * u)
		return lerpf(track_y, track_y - 0.55, u)
	var u2 := (t - 0.55) / 0.45
	u2 = u2 * u2
	return lerpf(track_y - 0.55, track_y - CLIFF_DEPTH, u2)


func _build_infield(pts: PackedVector3Array) -> void:
	## Grass island INSIDE the inner apron — with matching collision (no infinite plane).
	var n := pts.size()
	var inner_lat := -(_APRON_START + 1.5)
	# Fan from centroid of flattened path.
	var centroid := Vector3.ZERO
	for i in n:
		var f := _frame_at(pts, i)
		var edge: Vector3 = f["p"] + f["right"] * inner_lat
		edge.y = 0.02
		centroid += edge
	centroid /= float(n)
	centroid.y = 0.02

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass_mat := _grass_mat()
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		var a0: Vector3 = a["p"] + a["right"] * inner_lat
		var b0: Vector3 = b["p"] + b["right"] * inner_lat
		a0.y = 0.02
		b0.y = 0.02
		# Metric UVs so grass isn't skewed.
		st.set_uv(Vector2(centroid.x * 0.08, centroid.z * 0.08))
		st.add_vertex(centroid)
		st.set_uv(Vector2(a0.x * 0.08, a0.z * 0.08))
		st.add_vertex(a0)
		st.set_uv(Vector2(b0.x * 0.08, b0.z * 0.08))
		st.add_vertex(b0)
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "InfieldGrass"
	mi.mesh = mesh
	mi.material_override = grass_mat
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "InfieldCollision"
	var col := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(mesh.get_faces())
	col.shape = concave
	body.add_child(col)
	add_child(body)


func _grass_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/aerial_grass_rock_diff_1k.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/aerial_grass_rock_nor_gl_1k.jpg")
	mat.roughness_texture = load("res://assets/textures/aerial_grass_rock_rough_1k.jpg")
	mat.uv1_scale = Vector3(1, 1, 1)
	mat.roughness = 1.0
	return mat


func _offsets() -> PackedFloat32Array:
	## Collision ribbons: asphalt → rumble → shoulder → soft apron → rim (then void).
	var o := PackedFloat32Array()
	for v in [
		-_RIM,
		-(_APRON_START + APRON_WIDTH * 0.55),
		-_APRON_START,
		-(_SHOULDER_START),
		-TRACK_HALF_WIDTH,
		0.0,
		TRACK_HALF_WIDTH,
		_SHOULDER_START,
		_APRON_START,
		_APRON_START + APRON_WIDTH * 0.55,
		_RIM,
	]:
		o.append(v)
	return o


func _build_track(pts: PackedVector3Array) -> void:
	_build_driveable_collision(pts)
	_build_asphalt_visual(pts)
	_build_gravel_visual(pts)
	_build_apron_visual(pts)
	_build_curbs(pts)
	_build_center_line(pts)
	_build_edge_lines(pts)
	_build_start_finish(pts)
	_build_outer_barriers(pts)


func _emit_strip(
	st: SurfaceTool,
	pts: PackedVector3Array,
	lat0: float,
	lat1: float,
	y_off: float,
	uv_per_m: float,
	use_surface_y: bool
) -> void:
	var n := pts.size()
	var dist := 0.0
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		var step: float = (b["p"] as Vector3).distance_to(a["p"])
		var a0 := _lat_point(a, lat0, y_off, use_surface_y)
		var a1 := _lat_point(a, lat1, y_off, use_surface_y)
		var b0 := _lat_point(b, lat0, y_off, use_surface_y)
		var b1 := _lat_point(b, lat1, y_off, use_surface_y)
		# Metric UVs (meters) — same scale on U and V so asphalt/grass aren't skewed.
		var u0 := lat0 * uv_per_m
		var u1 := lat1 * uv_per_m
		var v0 := dist * uv_per_m
		var v1 := (dist + step) * uv_per_m
		_quad(st, a0, a1, b1, b0, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))
		dist += step


func _lat_point(f: Dictionary, lat: float, y_off: float, use_surface_y: bool) -> Vector3:
	var p: Vector3 = f["p"]
	var right: Vector3 = f["right"]
	var pos: Vector3 = p + right * lat
	if use_surface_y:
		pos.y = _surface_y(p.y, lat) + y_off
	else:
		pos.y = p.y + y_off
	return pos


func _build_driveable_collision(pts: PackedVector3Array) -> void:
	## Continuous trimesh through rim. Beyond rim = freefall (no ground plane).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var offs := _offsets()
	var n := pts.size()
	var ncols := offs.size()
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		for c in ncols - 1:
			# Stop collision before the vertical cliff face so the car freefalls.
			var lat_a := offs[c]
			var lat_b := offs[c + 1]
			var mid := (absf(lat_a) + absf(lat_b)) * 0.5
			if mid > _APRON_START + APRON_WIDTH * 0.55:
				continue
			var a0 := _lat_point(a, lat_a, ROAD_LIFT, true)
			var a1 := _lat_point(a, lat_b, ROAD_LIFT, true)
			var b0 := _lat_point(b, lat_a, ROAD_LIFT, true)
			var b1 := _lat_point(b, lat_b, ROAD_LIFT, true)
			_quad(st, a0, a1, b1, b0, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
	st.generate_normals()
	var mesh := st.commit()
	var body := StaticBody3D.new()
	body.name = "DriveableSurface"
	var col := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(mesh.get_faces())
	col.shape = concave
	body.add_child(col)
	add_child(body)


func _asphalt_mat() -> StandardMaterial3D:
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_texture = load("res://assets/textures/asphalt_02_diff_1k.jpg")
	asphalt.albedo_color = Color(0.68, 0.70, 0.73)
	asphalt.normal_enabled = true
	asphalt.normal_texture = load("res://assets/textures/asphalt_02_nor_gl_1k.jpg")
	asphalt.roughness_texture = load("res://assets/textures/asphalt_02_rough_1k.jpg")
	asphalt.roughness = 0.18
	asphalt.metallic = 0.18
	asphalt.clearcoat_enabled = true
	asphalt.clearcoat = 0.55
	asphalt.clearcoat_roughness = 0.08
	asphalt.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	asphalt.uv1_scale = Vector3(1, 1, 1)
	return asphalt


func _build_asphalt_visual(pts: PackedVector3Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Match collision height (use_surface_y) so visuals aren't floating / drive-through.
	_emit_strip(st, pts, -TRACK_HALF_WIDTH, TRACK_HALF_WIDTH, ROAD_LIFT + 0.012, 0.28, true)
	st.generate_normals()
	st.generate_tangents()
	var road_mi := MeshInstance3D.new()
	road_mi.mesh = st.commit()
	road_mi.material_override = _asphalt_mat()
	add_child(road_mi)


func _build_gravel_visual(pts: PackedVector3Array) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/asphalt_02_diff_1k.jpg")
	mat.albedo_color = Color(0.58, 0.52, 0.40)
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/asphalt_02_nor_gl_1k.jpg")
	mat.roughness = 0.92
	mat.uv1_scale = Vector3(1, 1, 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_strip(st, pts, -_APRON_START, -TRACK_HALF_WIDTH, ROAD_LIFT + 0.01, 0.32, true)
	_emit_strip(st, pts, TRACK_HALF_WIDTH, _APRON_START, ROAD_LIFT + 0.01, 0.32, true)
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _build_apron_visual(pts: PackedVector3Array) -> void:
	var mat := _grass_mat()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_strip(st, pts, -_RIM, -_APRON_START, 0.015, 0.22, true)
	_emit_strip(st, pts, _APRON_START, _RIM, 0.015, 0.22, true)
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _build_cliffs(pts: PackedVector3Array) -> void:
	## Visual rock face below the rim on BOTH sides — no collision (freefall).
	var rock := StandardMaterial3D.new()
	rock.albedo_texture = load("res://assets/textures/aerial_grass_rock_diff_1k.jpg")
	rock.albedo_color = Color(0.45, 0.40, 0.34)
	rock.normal_enabled = true
	rock.normal_texture = load("res://assets/textures/aerial_grass_rock_nor_gl_1k.jpg")
	rock.roughness = 0.95
	rock.uv1_scale = Vector3(1, 1, 1)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var rim_lat := _APRON_START + APRON_WIDTH * 0.55
	for side in [-1.0, 1.0]:
		var dist := 0.0
		for i in n:
			var a := _frame_at(pts, i)
			var b := _frame_at(pts, (i + 1) % n)
			var step: float = (b["p"] as Vector3).distance_to(a["p"])
			var top_a := _lat_point(a, side * rim_lat, 0.0, true)
			var top_b := _lat_point(b, side * rim_lat, 0.0, true)
			var bot_a: Vector3 = top_a + Vector3(0, -CLIFF_DEPTH - 4.0, 0) + (a["right"] as Vector3) * side * 2.5
			var bot_b: Vector3 = top_b + Vector3(0, -CLIFF_DEPTH - 4.0, 0) + (b["right"] as Vector3) * side * 2.5
			var u0 := dist * 0.15
			var u1 := (dist + step) * 0.15
			if side > 0.0:
				_quad(st, top_a, top_b, bot_b, bot_a, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 2.5), Vector2(u0, 2.5))
			else:
				_quad(st, top_b, top_a, bot_a, bot_b, Vector2(u1, 0), Vector2(u0, 0), Vector2(u0, 2.5), Vector2(u1, 2.5))
			dist += step
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "CliffFaces"
	mi.mesh = st.commit()
	mi.material_override = rock
	add_child(mi)


func _build_crash_floor() -> void:
	## Deep catch pad under the void — impact triggers crash (not a soft grass land).
	var body := StaticBody3D.new()
	body.name = "CrashFloor"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(700, 2.0, 700)
	col.shape = box
	col.position.y = -CLIFF_DEPTH - 8.0
	body.add_child(col)
	add_child(body)

	# Dark visual so freefall isn't empty void forever.
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	mi.mesh = plane
	mi.position.y = -CLIFF_DEPTH - 7.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.11, 0.10)
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)


func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2) -> void:
	st.set_uv(uv0)
	st.add_vertex(p0)
	st.set_uv(uv1)
	st.add_vertex(p1)
	st.set_uv(uv2)
	st.add_vertex(p2)
	st.set_uv(uv0)
	st.add_vertex(p0)
	st.set_uv(uv2)
	st.add_vertex(p2)
	st.set_uv(uv3)
	st.add_vertex(p3)


func _build_curbs(pts: PackedVector3Array) -> void:
	var n := pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist := 0.0
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		var step: float = (b["p"] as Vector3).distance_to(a["p"])
		var stripe := 1.0 if int(dist / 1.8) % 2 == 0 else 0.0
		var col := Color(0.92, 0.14, 0.16) if stripe > 0.5 else Color(0.96, 0.96, 0.97)
		for side in [-1.0, 1.0]:
			var inner := TRACK_HALF_WIDTH - 0.04
			var outer := TRACK_HALF_WIDTH + RUMBLE_WIDTH
			var ya := _surface_y(a["p"].y, side * inner) + 0.03
			var yb := _surface_y(b["p"].y, side * outer) + 0.035
			var inner_a: Vector3 = a["p"] + a["right"] * side * inner
			inner_a.y = ya
			var outer_a: Vector3 = a["p"] + a["right"] * side * outer
			outer_a.y = _surface_y(a["p"].y, side * outer) + 0.035
			var inner_b: Vector3 = b["p"] + b["right"] * side * inner
			inner_b.y = _surface_y(b["p"].y, side * inner) + 0.03
			var outer_b: Vector3 = b["p"] + b["right"] * side * outer
			outer_b.y = yb
			st.set_color(col)
			if side > 0.0:
				_quad(st, inner_a, outer_a, outer_b, inner_b, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			else:
				_quad(st, outer_a, inner_a, inner_b, outer_b, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
		dist += step
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.42
	mi.material_override = mat
	add_child(mi)


func _build_center_line(pts: PackedVector3Array) -> void:
	var n := pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dash := true
	var acc := 0.0
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		var step: float = (b["p"] as Vector3).distance_to(a["p"])
		acc += step
		if acc > 4.2:
			dash = not dash
			acc = 0.0
		if dash:
			var hw := 0.10
			var a_l: Vector3 = a["p"] - a["right"] * hw
			a_l.y = a["p"].y + 0.04
			var a_r: Vector3 = a["p"] + a["right"] * hw
			a_r.y = a["p"].y + 0.04
			var b_l: Vector3 = b["p"] - b["right"] * hw
			b_l.y = b["p"].y + 0.04
			var b_r: Vector3 = b["p"] + b["right"] * hw
			b_r.y = b["p"].y + 0.04
			st.set_color(Color(0.96, 0.93, 0.62))
			_quad(st, a_l, a_r, b_r, b_l, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.55
	mi.material_override = mat
	add_child(mi)


func _build_edge_lines(pts: PackedVector3Array) -> void:
	var n := pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		for side in [-1.0, 1.0]:
			var i0 := TRACK_HALF_WIDTH - 0.28
			var i1 := TRACK_HALF_WIDTH - 0.10
			var a0: Vector3 = a["p"] + a["right"] * side * i0
			a0.y = a["p"].y + 0.038
			var a1: Vector3 = a["p"] + a["right"] * side * i1
			a1.y = a["p"].y + 0.038
			var b0: Vector3 = b["p"] + b["right"] * side * i0
			b0.y = b["p"].y + 0.038
			var b1: Vector3 = b["p"] + b["right"] * side * i1
			b1.y = b["p"].y + 0.038
			st.set_color(Color(0.95, 0.95, 0.97))
			if side > 0.0:
				_quad(st, a0, a1, b1, b0, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			else:
				_quad(st, a1, a0, b0, b1, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.5
	mi.material_override = mat
	add_child(mi)


func _build_start_finish(pts: PackedVector3Array) -> void:
	var a := _frame_at(pts, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := TRACK_HALF_WIDTH - 0.25
	var depth := 3.2
	var p0: Vector3 = a["p"] - a["right"] * w - a["tangent"] * depth
	p0.y = a["p"].y + 0.045
	var p1: Vector3 = a["p"] + a["right"] * w - a["tangent"] * depth
	p1.y = a["p"].y + 0.045
	var p2: Vector3 = a["p"] + a["right"] * w + a["tangent"] * 0.35
	p2.y = a["p"].y + 0.045
	var p3: Vector3 = a["p"] - a["right"] * w + a["tangent"] * 0.35
	p3.y = a["p"].y + 0.045
	_quad(st, p0, p1, p2, p3, Vector2(0, 0), Vector2(12, 0), Vector2(12, 1), Vector2(0, 1))
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/checker.png")
	mat.uv1_scale = Vector3(1, 1, 1)
	mi.material_override = mat
	add_child(mi)

	for row in 3:
		for col in 2:
			var gst := SurfaceTool.new()
			gst.begin(Mesh.PRIMITIVE_TRIANGLES)
			var lat := -2.6 + float(col) * 5.2
			var long := -6.5 - float(row) * 5.4
			var hw := 1.15
			var hd := 2.2
			var g0: Vector3 = a["p"] + a["right"] * (lat - hw) + a["tangent"] * (long - hd)
			g0.y = a["p"].y + 0.042
			var g1: Vector3 = a["p"] + a["right"] * (lat + hw) + a["tangent"] * (long - hd)
			g1.y = a["p"].y + 0.042
			var g2: Vector3 = a["p"] + a["right"] * (lat + hw) + a["tangent"] * (long + hd)
			g2.y = a["p"].y + 0.042
			var g3: Vector3 = a["p"] + a["right"] * (lat - hw) + a["tangent"] * (long + hd)
			g3.y = a["p"].y + 0.042
			_quad(gst, g0, g1, g2, g3, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			gst.generate_normals()
			var gmi := MeshInstance3D.new()
			gmi.mesh = gst.commit()
			var gmat := StandardMaterial3D.new()
			gmat.albedo_color = Color(0.92, 0.92, 0.95) if (row + col) % 2 == 0 else Color(0.2, 0.2, 0.22)
			gmat.roughness = 0.6
			gmi.material_override = gmat
			add_child(gmi)


func _build_outer_barriers(pts: PackedVector3Array) -> void:
	## Low Armco past the gravel, before the cliff rim — not on the racing line.
	## Softer / lower so cars wedge less often on top of the rail.
	var n := pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := 0.58
	var thick := 0.16
	var wall_lat := _APRON_START + 2.1
	for i in n:
		var a := _frame_at(pts, i)
		var b := _frame_at(pts, (i + 1) % n)
		var side := _outward_sign(a)
		var a0: Vector3 = a["p"] + a["right"] * side * wall_lat
		var a1: Vector3 = a["p"] + a["right"] * side * (wall_lat + thick)
		var b0: Vector3 = b["p"] + b["right"] * side * wall_lat
		var b1: Vector3 = b["p"] + b["right"] * side * (wall_lat + thick)
		a0.y = _surface_y(a["p"].y, side * wall_lat)
		a1.y = a0.y
		b0.y = _surface_y(b["p"].y, side * wall_lat)
		b1.y = b0.y
		var a0t := a0 + Vector3.UP * height
		var a1t := a1 + Vector3.UP * height
		var b0t := b0 + Vector3.UP * height
		var b1t := b1 + Vector3.UP * height
		var col := Color(0.78, 0.22, 0.18) if int(i / 6) % 2 == 0 else Color(0.93, 0.93, 0.94)
		st.set_color(col)
		_quad(st, a0, b0, b0t, a0t, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
		_quad(st, a1, a1t, b1t, b1, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
		_quad(st, a0t, b0t, b1t, a1t, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.38
	mat.metallic = 0.35
	mi.material_override = mat
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "OuterBarrier"
	var phys := PhysicsMaterial.new()
	phys.friction = 0.28
	phys.bounce = 0.02
	phys.absorbent = true
	body.physics_material_override = phys
	var col := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(mesh.get_faces())
	col.shape = concave
	body.add_child(col)
	add_child(body)


func _spawn_model(path: String, pos: Vector3, rot_y: float, scl: float) -> Node3D:
	var res: Resource = load(path)
	if res == null:
		return null
	var node: Node3D
	if res is PackedScene:
		node = (res as PackedScene).instantiate()
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		node = mi
	else:
		return null
	add_child(node)
	node.position = pos
	node.rotation.y = rot_y
	node.scale = Vector3.ONE * scl
	return node


func _place_props(pts: PackedVector3Array) -> void:
	var n := pts.size()
	var trees := [
		"res://assets/models/nature/tree_oak.glb",
		"res://assets/models/nature/tree_detailed.glb",
		"res://assets/models/nature/tree_default.glb",
		"res://assets/models/nature/tree_pineDefaultA.glb",
		"res://assets/models/nature/tree_pineTallA_detailed.glb",
		"res://assets/models/nature/tree_cone.glb",
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260904

	# Dense roadside — placed on infield / beyond rim visually, not on driveable asphalt.
	for i in 190:
		var idx := rng.randi_range(0, n - 1)
		var f := _frame_at(pts, idx)
		var side := _outward_sign(f) if rng.randf() > 0.4 else -_outward_sign(f)
		var dist := rng.randf_range(_RIM + 3.0, _RIM + 42.0)
		var pos: Vector3 = f["p"] + f["right"] * side * dist
		# Sit on cliff-top / void edge visually near rim height, else infield/ground.
		if absf(side) > 0.0 and dist < _RIM + 8.0:
			pos.y = f["p"].y - 0.4
		else:
			pos.y = 0.0
		var path: String = trees[rng.randi_range(0, trees.size() - 1)]
		_spawn_model(path, pos, rng.randf() * TAU, rng.randf_range(1.7, 2.9))

	for i in 100:
		var idx := rng.randi_range(0, n - 1)
		var f := _frame_at(pts, idx)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		# Bushes on infield side of inner apron — not on shoulder.
		var pos: Vector3 = f["p"] + f["right"] * side * rng.randf_range(_APRON_START + 2.5, _APRON_START + 8.0)
		pos.y = 0.02
		# Only keep if roughly inside (toward center).
		if Vector3(pos.x, 0, pos.z).length() > 30.0 and rng.randf() > 0.35:
			pos = f["p"] - f["right"] * _outward_sign(f) * rng.randf_range(8.0, 22.0)
			pos.y = 0.02
		var bush := "res://assets/models/nature/plant_bushLarge.glb" if rng.randf() > 0.5 else "res://assets/models/nature/plant_bush.glb"
		_spawn_model(bush, pos, rng.randf() * TAU, rng.randf_range(1.4, 2.3))

	for i in 40:
		var idx := rng.randi_range(0, n - 1)
		var f := _frame_at(pts, idx)
		var pos: Vector3 = f["p"] + f["right"] * (1.0 if rng.randf() > 0.5 else -1.0) * rng.randf_range(_RIM + 4.0, _RIM + 28.0)
		pos.y = f["p"].y - 1.5
		var rock := "res://assets/models/nature/rock_largeA.glb" if rng.randf() > 0.4 else "res://assets/models/nature/rock_smallA.glb"
		_spawn_model(rock, pos, rng.randf() * TAU, rng.randf_range(1.5, 3.2))

	for i in 8:
		var f := _frame_at(pts, (4 + i * 2) % n)
		var side := _outward_sign(f)
		var pos: Vector3 = f["p"] + f["right"] * side * (TRACK_HALF_WIDTH + RUMBLE_WIDTH * 0.55)
		pos.y = f["p"].y + 0.02
		_spawn_model("res://assets/models/props/cone.glb", pos, f["tangent"].signed_angle_to(Vector3.FORWARD, Vector3.UP), 1.15)

	var start := _frame_at(pts, 6)
	var yaw_s := Vector3.FORWARD.signed_angle_to(start["tangent"], Vector3.UP)
	var out_s := _outward_sign(start)
	var gs_pos: Vector3 = start["p"] + start["right"] * out_s * (_RIM + 6.0)
	gs_pos.y = start["p"].y - 0.5
	_spawn_model("res://assets/models/track/grandStand.obj", gs_pos, yaw_s + (0.0 if out_s > 0.0 else PI), 2.6)
	var flag_pos: Vector3 = start["p"] + start["right"] * out_s * (TRACK_HALF_WIDTH + 2.4)
	flag_pos.y = start["p"].y
	_spawn_model("res://assets/models/track/flagCheckers.obj", flag_pos, yaw_s, 1.9)
	_spawn_model(
		"res://assets/models/track/lightPostLarge.obj",
		start["p"] + start["right"] * out_s * (TRACK_HALF_WIDTH + RUMBLE_WIDTH + 2.2) + Vector3(0, start["p"].y, 0),
		yaw_s,
		1.55
	)

	var wall_lat := _APRON_START + 1.8
	for i in range(0, n, 12):
		var f := _frame_at(pts, i)
		var yaw := Vector3.FORWARD.signed_angle_to(f["tangent"], Vector3.UP)
		var side := _outward_sign(f)
		var pos: Vector3 = f["p"] + f["right"] * side * (wall_lat - 0.1)
		pos.y = _surface_y(f["p"].y, side * wall_lat)
		var mdl := "res://assets/models/track/barrierRed.obj" if (i / 12) % 2 == 0 else "res://assets/models/track/barrierWhite.obj"
		_spawn_model(mdl, pos, yaw, 1.7)
		if i % 36 == 0:
			var pyl: Vector3 = f["p"] + f["right"] * side * (wall_lat + 1.0)
			pyl.y = pos.y
			_spawn_model("res://assets/models/track/pylon.obj", pyl, yaw, 1.5)


func _place_parked_cars(pts: PackedVector3Array) -> void:
	var cars := [
		"res://assets/models/cars/hatchback-sports.glb",
		"res://assets/models/cars/suv.glb",
		"res://assets/models/cars/taxi.glb",
		"res://assets/models/cars/police.glb",
		"res://assets/models/cars/race.glb",
	]
	var f := _frame_at(pts, 14)
	var inward := -_outward_sign(f)
	for i in cars.size():
		var pos: Vector3 = f["p"] + f["right"] * inward * (18.0 + float(i) * 3.8) - f["tangent"] * 8.0
		pos.y = 0.02
		var yaw := Vector3.FORWARD.signed_angle_to(f["tangent"], Vector3.UP) + PI * 0.5
		var node := _spawn_model(cars[i], pos, yaw, 1.7)
		if node:
			node.rotate_y(PI)


func _compute_spawn(pts: PackedVector3Array) -> void:
	var f := _frame_at(pts, 3)
	var origin: Vector3 = f["p"] - f["right"] * 2.6 + Vector3.UP * 0.62
	var basis := Basis()
	var fwd: Vector3 = f["tangent"]
	var right: Vector3 = f["right"]
	var up: Vector3 = f["up"]
	basis.x = right
	basis.y = up
	basis.z = -fwd
	basis = basis.orthonormalized()
	spawn_transform = Transform3D(basis, origin)
