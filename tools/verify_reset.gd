extends SceneTree

## Headless: hard reset from wrecked/frozen/barrier-contact, steer sign & rates.

func _init() -> void:
	var code := 0
	# Parse car.gd steer constants without full scene (scripts may need class_name).
	var car_src := FileAccess.get_file_as_string("res://scripts/car.gd")
	if car_src.is_empty():
		push_error("cannot read car.gd")
		quit(1)
		return

	# Steer tuning sanity (middle ground vs sluggish 1.3.0).
	for pair in [
		["steer_accel", 6.0, 12.0],
		["steer_return_accel", 8.0, 16.0],
		["steer_max_rate", 3.5, 7.0],
		["steer_return_max_rate", 4.5, 9.0],
		["min_steer_angle", 0.16, 0.30],
		["max_steer_angle", 0.45, 0.60],
	]:
		var key: String = pair[0]
		var lo: float = pair[1]
		var hi: float = pair[2]
		var re := RegEx.new()
		re.compile(key + r": float = ([0-9.]+)")
		var m := re.search(car_src)
		if m == null:
			push_error("missing export %s" % key)
			code = 1
			continue
		var v := m.get_string(1).to_float()
		print(key, "=", v)
		if v < lo or v > hi:
			push_error("%s out of expected range [%s,%s]: %s" % [key, lo, hi, v])
			code = 1

	# Correct VehicleBody3D sign: target := -steer_input * max_steer
	if 'var target := -steer_input * max_steer' not in car_src:
		push_error("steering sign line missing/changed")
		code = 1
	else:
		print("steer sign OK (A/left = positive VehicleBody3D steering)")

	# Hard reset markers
	for needle in [
		"PhysicsServer3D.body_set_state",
		"_finish_hard_reset",
		"collision_layer = 0",
		"_build_steering_wheel_mesh",
		"_maybe_auto_unstick",
	]:
		if needle not in car_src:
			push_error("missing hard-reset/wheel piece: %s" % needle)
			code = 1
		else:
			print("found ", needle)

	var game_src := FileAccess.get_file_as_string("res://scripts/game.gd")
	if "car.reset_vehicle()" not in game_src:
		push_error("game._restart must call car.reset_vehicle")
		code = 1
	if "Engine.time_scale = 1.0" not in game_src:
		push_error("game._restart must clear time_scale")
		code = 1

	var cam_src := FileAccess.get_file_as_string("res://scripts/chase_camera.gd")
	var re_h := RegEx.new()
	re_h.compile(r"fps_eye_height: float = ([0-9.]+)")
	var mh := re_h.search(cam_src)
	if mh:
		var h := mh.get_string(1).to_float()
		print("fps_eye_height=", h)
		if h < 1.15 or h > 1.28:
			push_error("eye height out of driver range [1.15,1.28]: %s" % h)
			code = 1
	var re_lat := RegEx.new()
	re_lat.compile(r"fps_eye_lateral: float = ([0-9.]+)")
	var mlat := re_lat.search(cam_src)
	if mlat:
		print("fps_eye_lateral=", mlat.get_string(1))
	var re_look := RegEx.new()
	# look_local y must be near eye height (not ~0.05 asphalt aim)
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
		if look_z > -15.0 or look_z < -30.0:
			push_error("look_z should be mid-distance ahead [-30,-15] (got %s)" % look_z)
			code = 1
	if "deg_to_rad(-2.8)" in cam_src:
		push_error("old steep downward pitch -2.8° still present")
		code = 1
	var re_f := RegEx.new()
	re_f.compile(r"fps_fov: float = ([0-9.]+)")
	var mf := re_f.search(cam_src)
	if mf:
		print("fps_fov=", mf.get_string(1))

	# v1.3.4 cornering feel: no hard power-cut on normal slip + lower scrub
	for needle in [
		"powered_corner",
		"engine_force *= lerpf(1.0, 0.88, damp_k)",
		"angular_damp = 1.0",
		"wheel_friction_slip = 4.1",
		"base_f := 4.1 * _surface_grip",
	]:
		if needle not in car_src:
			push_error("missing cornering retune: %s" % needle)
			code = 1
		else:
			print("found ", needle)
	if "engine_force *= lerpf(1.0, 0.25, damp_k)" in car_src:
		push_error("old hard power-cut (0.25) still present")
		code = 1
	var re_yaw := RegEx.new()
	re_yaw.compile(r"MAX_YAW_RATE := ([0-9.]+)")
	var myaw := re_yaw.search(car_src)
	if myaw == null:
		push_error("MAX_YAW_RATE missing")
		code = 1
	else:
		var yawv := myaw.get_string(1).to_float()
		print("MAX_YAW_RATE=", yawv)
		if yawv < 2.2 or yawv > 2.8:
			push_error("MAX_YAW_RATE out of [2.2,2.8]: %s" % yawv)
			code = 1

	# Live world + car reset path
	var world := WorldBuilder.new()
	root.add_child(world)
	world.build()
	var car: PlayerCar = load("res://scenes/car.tscn").instantiate()
	root.add_child(car)
	await process_frame
	await process_frame
	car.set_spawn(world.spawn_transform)
	await process_frame

	# Simulate wreck + freeze hung on barrier pose
	car.is_wrecked = true
	car.freeze = true
	car.damage = 1.0
	car.global_position = world.spawn_transform.origin + Vector3(12, 0.4, 3)
	car.linear_velocity = Vector3(2, 0, 1)
	car.angular_velocity = Vector3(0.2, 0.5, 0.1)
	print("pre-reset pos=", car.global_position, " freeze=", car.freeze, " wrecked=", car.is_wrecked)

	car.reset_vehicle()
	# Allow hard-reset await frames
	await process_frame
	await process_frame
	await process_frame
	await process_frame

	var err_pos := car.global_position.distance_to(world.spawn_transform.origin)
	print("post-reset pos=", car.global_position, " err=", snapped(err_pos, 0.001))
	print("freeze=", car.freeze, " wrecked=", car.is_wrecked, " damage=", car.damage)
	print("vel=", car.linear_velocity, " ang=", car.angular_velocity)
	print("collision_layer=", car.collision_layer, " mask=", car.collision_mask)

	if car.is_wrecked:
		push_error("still wrecked after reset")
		code = 1
	if car.freeze:
		push_error("still frozen after reset")
		code = 1
	if car.damage > 0.01:
		push_error("damage not cleared")
		code = 1
	if err_pos > 0.75:
		push_error("not teleported to spawn (err=%s)" % err_pos)
		code = 1
	if car.linear_velocity.length() > 0.25 or car.angular_velocity.length() > 0.25:
		push_error("velocities not cleared")
		code = 1
	if car.collision_layer == 0:
		push_error("collision_layer still 0 after reset window")
		code = 1
	if car._steer_wheel == null:
		push_error("steering wheel missing")
		code = 1
	else:
		print("steer wheel children=", car._steer_wheel.get_child_count())
		print("steer wheel pos=", car._steer_wheel.position, " scale=", car._steer_wheel.scale)
		if car._steer_wheel.get_child_count() < 6:
			push_error("steering wheel mesh too primitive")
			code = 1
		if car._steer_wheel.scale.x < 1.05:
			push_error("steering wheel still too small for FPS presence")
			code = 1
		if car._steer_wheel.position.z < -0.25:
			push_error("steering wheel too far forward (tiny in frame)")
			code = 1

	# Steer input direction: hold left should move steer_input toward -1, VehicleBody steering +
	car.steer_input = 0.0
	car._steer_velocity = 0.0
	for i in 30:
		car._integrate_steer_input(-1.0, 1.0 / 60.0)
	print("after left hold steer_input=", car.steer_input)
	if car.steer_input > -0.35:
		push_error("steer-in too slow (steer_input=%s)" % car.steer_input)
		code = 1
	car._apply_steering(1.0 / 60.0)
	print("steering rad after left=", car.steering)
	if car.steering <= 0.0:
		push_error("A/left did not produce positive VehicleBody3D steering")
		code = 1

	# Return to center
	for i in 45:
		car._integrate_steer_input(0.0, 1.0 / 60.0)
	print("after release steer_input=", car.steer_input)
	if absf(car.steer_input) > 0.15:
		push_error("steer return too slow")
		code = 1

	var barrier := world.find_child("OuterBarrier", true, false)
	if barrier == null:
		push_error("OuterBarrier missing")
		code = 1
	else:
		var pm = (barrier as StaticBody3D).physics_material_override
		print("barrier phys mat=", pm)
		if pm == null:
			push_error("barrier missing physics material")
			code = 1

	if code == 0:
		print("VERIFY_RESET_OK")
	else:
		print("VERIFY_RESET_FAIL")
	quit(code)
