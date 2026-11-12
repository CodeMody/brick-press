extends SceneTree
# TEMP DIAG — run against the EXPORTED exe (tools/ must be temporarily un-excluded):
#   Breakout.exe --headless -s res://tools/pack_probe.gd
# Prints what the exported PCK really contains/loads around music, then quits.

func _initialize() -> void:
	print("PROBE: dirs at root: ", _list("res://", true))
	print("PROBE: music dir: ", _list("res://music", false))
	print("PROBE: file_exists music wav: ", FileAccess.file_exists("res://music/neon_corridor.wav"))
	print("PROBE: ResourceLoader.exists music wav: ", ResourceLoader.exists("res://music/neon_corridor.wav"))
	var sp := _first_sample()
	print("PROBE: sample path: ", sp)
	if sp != "":
		print("PROBE: sample file_exists: ", FileAccess.file_exists(sp), " · ResourceLoader.exists: ", ResourceLoader.exists(sp))
		var a = load(sp)
		print("PROBE: sample load type: ", typeof(a), " class: ", (a.get_class() if a != null else "null"))
		if a != null:
			var p := AudioStreamPlayer.new()
			root.add_child(p)
			p.stream = a
			p.play()
			print("PROBE: sample play playing: ", p.playing, " len: ", a.get_length())
	# also prove what PNG load looks like (known-good control)
	print("PROBE: bg1 exists: ", FileAccess.file_exists("res://backgrounds/bg1.png"), " · load ok: ", load("res://backgrounds/bg1.png") != null)
	quit()

func _list(path: String, dirs_only: bool) -> String:
	var d := DirAccess.open(path)
	if d == null:
		return "<unopenable>"
	var s := ""
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if (not dirs_only) or d.current_is_dir():
			s += f + " "
		f = d.get_next()
	d.list_dir_end()
	return s

func _first_sample() -> String:
	var d := DirAccess.open("res://.godot/imported")
	if d == null:
		return "<no .godot/imported dir>"
	d.list_dir_begin()
	var f := d.get_next()
	var out := ""
	while f != "":
		if f.begins_with("neon_corridor") and f.get_extension() == "sample":
			out = "res://.godot/imported/" + f
			break
		f = d.get_next()
	d.list_dir_end()
	return out
