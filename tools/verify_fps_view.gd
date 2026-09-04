extends SceneTree

## Headless v1.3.3: FPS must hide Kenney sedan body (yellow shell occlusion).
## Spawns car, switches to FPS, asserts sedan/driver invisible, ray forward
## does not hit a body MeshInstance under SedanSportsVisual.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var code := 0

	var car_src := FileAccess.get_file_as_string("res://scripts/car.gd")
	if car_src.is_empty():
		push_error("cannot read car.gd")
		quit(1)
		return

	for needle in [
		"_sedan_visual",
		"_backup_and_hide_fps_occluders",
		"SedanSportsVisual",
		"_hide_fps_occluders_only",
		"_restore_fps_occluders",
	]:
		if needle not in car_src:
			push_error("missing FPS body-hide piece: %s" % needle)
			code = 1
		else:
			print("found ", needle)

	# Source must hide sedan on FPS enable (not only driver head).
	if "_sedan_visual.visible = not _fps_mode" not in car_src and "n.visible = false" not in car_src:
		push_error("sedan hide path unclear")
		code = 1
	if "Hide driver head/helmet" in car_src and "_sedan_visual" not in car_src:
		push_error("still only hiding driver head")
		code = 1

	var cam_src := FileAccess.get_file_as_string("res://scripts/chase_camera.gd")
	var re_fwd := RegEx.new()
	re_fwd.compile(r"fps_eye_forward: float = ([0-9.]+)")
	var mf := re_fwd.search(cam_src)
	if mf == null:
		push_error("fps_eye_forward missing")
		code = 1
	else:
		var fwd := mf.get_string(1).to_float()
		print("fps_eye_forward=", fwd)
		# Slightly forward of dash (less rearward than old 0.28).
		if fwd < 0.08 or fwd > 0.24:
			push_error("fps_eye_forward out of cockpit range [0.08,0.24]: %s" % fwd)
			code = 1

	# Keep horizon look from 1.3.2.
	var re_look := RegEx.new()
	re_look.compile(r"look_local := Vector3\([^,]+,\s*([0-9.]+),\s*(-?[0-9.]+)\)")
	var mlook := re_look.search(cam_src)
	if mlook == null:
		push_error("FPS look_local not found")
		code = 1
	else:
		var look_y := mlook.get_string(1).to_float()
		var look_z := mlook.get_string(2).to_float()
		print("fps_look_y=", look_y, " fps_look_z=", look_z)
		if look_y < 0.7 or look_y > 1.3:
			push_error("look_y must stay near eye height (got %s)" % look_y)
			code = 1

	var world := WorldBuilder.new()
	root.add_child(world)
	world.build()
	var car: PlayerCar = load("res://scenes/car.tscn").instantiate()
	root.add_child(car)
	await process_frame
	await process_frame
	car.set_spawn(world.spawn_transform)
	await process_frame
	await process_frame

	if car._sedan_visual == null:
		push_error("_sedan_visual was not set — GLB missing or attach failed")
		code = 1
		print("VERIFY_FPS_VIEW_FAIL")
		quit(code)
		return

	print("sedan name=", car._sedan_visual.name, " chase_visible=", car._sedan_visual.visible)
	if not car._sedan_visual.visible:
		push_error("sedan should be visible in chase before FPS")
		code = 1

	# Switch to FPS — body must disappear.
	car.set_fps_view(true)
	await process_frame
	await process_frame

	print("FPS sedan visible=", car._sedan_visual.visible)
	print("FPS driver visible=", car._driver_root.visible if car._driver_root else "null")
	print("FPS dash visible=", car._cabin_dash.visible if car._cabin_dash else "null")
	print("FPS wheel visible=", car._steer_wheel.visible if car._steer_wheel else "null")

	if car._sedan_visual.visible:
		push_error("SEDAN BODY STILL VISIBLE IN FPS — yellow shell occlusion not fixed")
		code = 1
	if car._driver_root and car._driver_root.visible:
		push_error("driver still visible in FPS (must hide entire driver)")
		code = 1
	if car._cabin_dash and not car._cabin_dash.visible:
		push_error("cabin dash should stay visible in FPS")
		code = 1
	if car._steer_wheel and not car._steer_wheel.visible:
		push_error("steering wheel should stay visible in FPS")
		code = 1
	if car._bumper and car._bumper.visible:
		push_error("bumper should be hidden in FPS (windshield cone)")
		code = 1

	# Raycast forward from FPS eye ~20–50 m: must NOT hit sedan body meshes.
	var eye_local := Vector3(0.32, 1.20, 0.18)
	var eye := car.global_transform * eye_local
	var ahead := car.global_transform * (eye_local + Vector3(0.0, -0.05, -35.0))
	var from := eye
	var to := ahead
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = [car.get_rid()]
	var space := car.get_world_3d().direct_space_state
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		print("ray forward: no hit (sky/open) — OK")
	else:
		var collider = hit.get("collider")
		var cname := String(collider.name) if collider else "?"
		print("ray forward hit=", cname, " pos=", hit.get("position"))
		# Ensure hit is not a MeshInstance under sedan (ray hits physics, not meshes —
		# so also walk visual tree: no visible MeshInstance under sedan).
		if collider == car:
			push_error("ray hit car body collider unexpectedly")
			code = 1

	# Sample: every MeshInstance under sedan must be under an invisible ancestor.
	var visible_body_meshes := 0
	visible_body_meshes = _count_visible_meshes(car._sedan_visual)
	print("visible meshes under sedan visual=", visible_body_meshes)
	if visible_body_meshes > 0:
		push_error("sedan body meshes still effectively visible")
		code = 1

	# Restore chase — body back.
	car.set_fps_view(false)
	await process_frame
	print("chase sedan visible=", car._sedan_visual.visible)
	print("chase driver visible=", car._driver_root.visible if car._driver_root else "null")
	if not car._sedan_visual.visible:
		push_error("sedan not restored in chase cam")
		code = 1
	if car._driver_root and not car._driver_root.visible:
		push_error("driver not restored in chase cam")
		code = 1

	# Second FPS toggle (idempotent).
	car.set_fps_view(true)
	await process_frame
	if car._sedan_visual.visible:
		push_error("second FPS toggle left sedan visible")
		code = 1

	if code == 0:
		print("VERIFY_FPS_VIEW_OK")
	else:
		print("VERIFY_FPS_VIEW_FAIL")
	quit(code)


func _count_visible_meshes(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return 0
	# If this node or any ancestor is invisible, meshes under it are not drawn.
	if node is Node3D and not (node as Node3D).visible:
		return 0
	var count := 0
	if node is MeshInstance3D and (node as MeshInstance3D).visible:
		count += 1
	for c in node.get_children():
		count += _count_visible_meshes(c)
	return count
