extends SceneTree
# Dev tool: boots main.tscn in a REAL window, snapshots the rendered viewport at
# eleven UI states (main menu / leaderboard submenu / gameplay / lava ball / juice shot: trail+popups+shield+combo /
# background showcase / the REPLACED bg2 / FEVER mode / live bomb blast / the unified PAUSED sheet / Settings face from the menu)
# straight from the GPU texture, then exits. No window-focus assumptions — immune to whatever is on top.

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)   # same dev redirect as the harness — without it, a shots run would book its 160-pt demo score onto the PLAYER's real %APPDATA% board
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	DirAccess.make_dir_absolute("res://.shots")
	var game = load("res://main.tscn").instantiate()
	get_root().add_child(game)
	await create_timer(1.6).timeout   # real frames render while we wait
	_snap(game, "1_menu")
	game.open_leaderboard()           # the submenu pattern — a card modal just like Settings, reached from the menu button
	await create_timer(0.30).timeout
	_snap(game, "11_boards")
	game.close_leaderboard()
	game.play()                        # drive through the API — no keyboard roulette
	await create_timer(0.7).timeout
	_snap(game, "2_game")
	game.apply_powerup("LAVA")          # molten ball + orange paddle glow + HUD timer line
	await create_timer(0.5).timeout
	_snap(game, "4_lava")
	game.launch_all()                          # set the ball flying — the ghost trail shows up in the next shot
	await create_timer(0.45).timeout
	game.destroy_block(game.blocks()[0], -1)   # a real kill: floating +score popup, sparks
	game.apply_powerup("SHIELD")
	game.state.message = ""             # hero shot stays popup-free — the Shield band + HUD timers do the talking
	game.state.combo = 6                        # warm the pulsing combo pill for the shot
	await create_timer(0.55).timeout
	_snap(game, "5_fun")
	game.set_background(2)              # aurora — showcases the repainted background set
	await create_timer(0.30).timeout
	_snap(game, "6_bg")
	game.set_background(1)              # bg2 — the REPLACED background (Amethyst Cathedral, player-request swap)
	await create_timer(0.30).timeout
	_snap(game, "10_bg2")
	# FEVER mode: amber tint over the field, fever pill, hot trail, warm ball — the hot-streak payoff state
	game.state.fever = 6.0
	game.state.combo = 12
	game.boom(300.0, 220.0, 1)
	game.launch_all()
	await create_timer(0.40).timeout
	_snap(game, "7_fever")
	# a live bomb blast mid-wave: ring expanding, neighbour bomb still standing with its fuse lit, chain popups
	game.state.fever = 0.0
	game.state.combo = 0
	game.blocks_data.append({"c": 5, "r": 9, "t": "explode", "hp": 1, "color": "#ffee58", "x": 406.5, "y": 331.0})
	game.blocks_data.append({"c": 6, "r": 9, "t": "explode", "hp": 1, "color": "#ffee58", "x": 481.5, "y": 331.0})
	game.blocks_data.append({"c": 7, "r": 9, "t": "normal", "hp": 1, "color": "#ef5350", "x": 556.5, "y": 331.0})
	game.destroy_block(game.blocks_data[-3], -1)   # detonate the first bomb
	await create_timer(0.07).timeout               # freeze mid-chain: the domino has yet to fall
	_snap(game, "8_boom")
	await create_timer(0.25).timeout               # let the domino pop land before the sheet opens
	game.set_background(0)              # back to the bg1 starfield as the pause/settings backdrop
	game.toggle_menu()                  # THE unified pause menu: run info + Resume / Quit to menu / Quit game over the frozen field
	await create_timer(0.35).timeout
	_snap(game, "9_pause")
	game.toggle_menu()                  # away again — and back to the title scene, so 3_settings captures the plain Settings face
	await create_timer(0.20).timeout
	game.quit_to_menu()
	await create_timer(0.30).timeout
	game.toggle_menu()
	await create_timer(0.35).timeout
	_snap(game, "3_settings")
	var ev := InputEventMouseMotion.new()
	var wl := Vector2(640, 360)   # synthetic cursor nudge at screen center, in WINDOW-local coords so window position can't skew the math
	ev.position = wl
	ev.global_position = Vector2(game.get_window().get_position()) + wl   # 4.7: get_position() returns Vector2i — make the addition explicit
	Input.parse_input_event(ev)
	await process_frame
	print("MOUSECHECK winpos=", game.get_window().get_position(), " winsize=", game.get_window().size, " local=", ev.position, " viewrect=", game.get_viewport().get_visible_rect(), " globalmouse=", game.get_global_mouse_position(), " paddle.x=", game.paddle.x)
	print("SHOTS_DONE")
	quit(0)

func _snap(game: Node, name: String) -> void:
	RenderingServer.force_draw()   # 4.7 API (Viewport.render() no longer exists): flush rendering NOW — a background window can throttle to ~1 fps and then the swapchain image lags a frame or more
	var img: Image = root.get_texture().get_image()
	var err := img.save_png("res://.shots/%s.png" % name)
	print("SNAP ", name, " size=", img.get_size(), " err=", err)
