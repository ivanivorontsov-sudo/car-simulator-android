extends SceneTree

## Headless check: continuous runoff, cliff void, spawn, physics seconds.

func _init() -> void:
	var code := 0
	var world := WorldBuilder.new()
	root.add_child(world)
	world.build()
	var pts: PackedVector3Array = world._make_centerline()
	if pts.size() < 100:
		push_error("centerline too short: %d" % pts.size())
		code = 1
	var ymin := 1e9
	var ymax := -1e9
	for p in pts:
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	print("centerline points=", pts.size(), " y=[", snapped(ymin, 0.01), ",", snapped(ymax, 0.01), "]")
	if ymin < 2.0:
		push_error("track too low for cliff drop: ymin=%s" % ymin)
		code = 1
	# Shoulder must match track height (no vertical lip).
	var i := 0
	var max_lip := 0.0
	while i < pts.size():
		var f: Dictionary = world._frame_at(pts, i)
		var ty: float = f["p"].y
		var shoulder_y := world._surface_y(ty, WorldBuilder.TRACK_HALF_WIDTH + 3.0)
		var lip := absf(shoulder_y - ty)
		max_lip = maxf(max_lip, lip)
		i += 30
	print("max shoulder lip vs track: ", snapped(max_lip, 0.001), " m")
	if max_lip > 0.02:
		push_error("shoulder not coplanar with track")
		code = 1
	# Soft apron mid stays near track; cliff rim drops hard.
	var soft_y := world._surface_y(6.5, WorldBuilder._APRON_START + WorldBuilder.APRON_WIDTH * 0.3)
	print("soft apron y @ 6.5: ", snapped(soft_y, 0.001))
	if soft_y < 5.5:
		push_error("soft apron drops too early")
		code = 1
	var rim_y := world._surface_y(6.5, WorldBuilder._APRON_END)
	print("cliff rim/end y @ 6.5: ", snapped(rim_y, 0.001), " (expect deep drop)")
	if rim_y > 0.0:
		push_error("cliff end does not drop below zero")
		code = 1
	if world.spawn_transform.origin.y < 3.0:
		push_error("spawn too low")
		code = 1
	print("spawn: ", world.spawn_transform.origin)
	print("TRACK_HALF_WIDTH=", WorldBuilder.TRACK_HALF_WIDTH)
	if WorldBuilder.TRACK_HALF_WIDTH < 9.0:
		push_error("road not wide enough")
		code = 1
	var driveable := world.find_child("DriveableSurface", true, false)
	if driveable == null:
		push_error("missing DriveableSurface collision")
		code = 1
	else:
		print("DriveableSurface ok")
	var crash_floor := world.find_child("CrashFloor", true, false)
	if crash_floor == null:
		push_error("missing CrashFloor")
		code = 1
	else:
		print("CrashFloor ok")
	# Infinite flat ground collider must be gone.
	for c in world.get_children():
		if c is StaticBody3D and c.name != "DriveableSurface" and c.name != "OuterBarrier" and c.name != "InfieldCollision" and c.name != "CrashFloor":
			var cs: CollisionShape3D = c.get_node_or_null("CollisionShape3D")
			if cs and cs.shape is BoxShape3D:
				var b := cs.shape as BoxShape3D
				if b.size.x > 400.0 and b.size.z > 400.0 and absf(cs.position.y) < 2.0:
					push_error("legacy infinite ground collider still present: %s" % c.name)
					code = 1
	var inner_wall := world.find_child("InnerWall", true, false)
	if inner_wall:
		push_error("inner wall should be gone")
		code = 1
	var outer := world.find_child("OuterBarrier", true, false)
	if outer == null:
		push_error("missing OuterBarrier")
		code = 1

	var car_ps: PackedScene = load("res://scenes/car.tscn")
	var car: PlayerCar = car_ps.instantiate()
	root.add_child(car)
	car.set_spawn(world.spawn_transform)
	var frames := 0
	while frames < 90:
		await physics_frame
		frames += 1
	print("car after 90 ticks pos=", car.global_position, " vel=", car.linear_velocity.length())
	if car.global_position.y < 2.0:
		push_error("car fell through world")
		code = 1
	# Driver + steering wheel must exist.
	var driver := car.find_child("Driver", true, false)
	var wheel := car.find_child("SteeringWheel", true, false)
	if driver == null:
		push_error("missing Driver mesh")
		code = 1
	else:
		print("Driver ok")
	if wheel == null:
		push_error("missing SteeringWheel")
		code = 1
	else:
		print("SteeringWheel ok")
	# Nudge onto the shoulder and ensure we don't drop.
	var f0: Dictionary = world._frame_at(pts, 3)
	var shoulder_pos: Vector3 = f0["p"] + f0["right"] * (WorldBuilder.TRACK_HALF_WIDTH + 4.0)
	shoulder_pos.y = f0["p"].y + 0.7
	var xf := Transform3D(world.spawn_transform.basis, shoulder_pos)
	car.set_spawn(xf)
	frames = 0
	var min_y := 1e9
	while frames < 90:
		await physics_frame
		min_y = minf(min_y, car.global_position.y)
		frames += 1
	print("shoulder sit y=", car.global_position.y, " min_y=", min_y, " track_y=", f0["p"].y)
	if min_y < f0["p"].y - 0.5:
		push_error("car dropped off shoulder")
		code = 1
	# Past rim: car must freefall (no soft grass catch).
	car.is_wrecked = false
	car.freeze = false
	var fall_pos: Vector3 = f0["p"] + f0["right"] * (WorldBuilder._RIM + 3.0)
	fall_pos.y = f0["p"].y + 1.0
	car.global_transform = Transform3D(world.spawn_transform.basis, fall_pos)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	frames = 0
	var fell := false
	while frames < 180:
		await physics_frame
		if car.global_position.y < f0["p"].y - 4.0:
			fell = true
			break
		frames += 1
	print("cliff freefall=", fell, " y=", car.global_position.y)
	if not fell:
		push_error("car did not freefall past cliff rim")
		code = 1
	if code == 0:
		print("VERIFY_OK")
	else:
		print("VERIFY_FAIL")
	quit(code)
