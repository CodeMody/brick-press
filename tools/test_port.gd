extends SceneTree
# Headless parity test for the Godot port — mirrors breakout-game/tools/test_harness.js.
# Run: Godot_v4.7.2-stable_win64.exe --headless --path <project> --user-data-dir .test_userdata -s res://tools/test_port.gd
# (run `--import` once first so the background PNGs have import artifacts)

const ANCHOR_LEVEL1 := "nnn3....nnn3;nn....tnnt..;....nn3n....;..nnnt....nn"
const ANCHOR_LEVEL2 := ".nn.tn.nn.nn;ng.n3.nn.n3.;n.et.tn.nn.n;.nn.en.nt.nn;ne.nn.3n.nn."   # gold veins (positional rule (c+2r)%11==3, level ≥ 2) render as g — JS-era parity extended by the Godot expansion

var game = null   # Variant on purpose: static analysis rejects script members on a typed Node base
var fails := 0

func ok(msg: String) -> void:
	print("ok  : ", msg)

func fail(msg: String) -> void:
	print("FAIL: ", msg)
	fails += 1

func check(cond: bool, msg: String) -> void:
	if cond: ok(msg)
	else: fail(msg)

func jstr(x: Variant) -> String:
	return JSON.new().stringify(x)   # Godot 4 JSON.stringify is an instance method

func pump(n: int) -> void:
	for _i in n:
		await process_frame

func layout_str() -> String:
	var cells = game.blocks()
	var rows := 0
	for c in cells:
		rows = maxi(rows, c.r + 1)
	var grid := []
	for _r in rows:
		grid.append([".", ".", ".", ".", ".", ".", ".", ".", ".", ".", ".", "."])
	var cmap := {"normal": "n", "tough": "t", "tough3": "3", "explode": "e", "steel": "s", "gold": "g"}
	for c in cells:
		if c.t == "steel": continue   # JS harness layout string skipped steel cells (counted them though)
		grid[c.r][c.c] = cmap[c.t]
	var out := []
	for r in grid:
		out.append("".join(r))   # GDScript 4.7.2: join lives on String, not Array
	return ";".join(out)

func _initialize() -> void:   # SceneTree main-loop entry via -s; root exists here (a coroutine _init would break instantiation)
	seed(12345)   # deterministic global RNG stream for the port's own launch angles
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)   # Godot 4.7 has NO --user-data-dir CLI flag (even absolute paths are silently ignored — probed) and NO OS.set_user_data_dir() anymore either. Flipping this setting before main.tscn exists sends dev-run user:// to %APPDATA%\Breakout Godot — the player's real %APPDATA%\Godot\app_userdata\Breakout Godot stays untouched
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	var da := DirAccess.open("user://")   # fresh storage each run — pumps are real-time so scores vary run to run
	if da and da.file_exists("breakout_high.cfg"):
		da.remove("breakout_high.cfg")
	await process_frame   # belt: ensure tree/root fully live before driving the game
	var scene: PackedScene = load("res://main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	# ---- boot ----
	check(game.has_method("blocks") and game.has_method("destroy_block") and game.has_method("apply_powerup"), "__breakout-equivalent hooks exposed")
	check(game.bg_images.size() == 5, "all 5 background slots registered")   # 5 scan + manifest dupes merged away
	check(layout_str() == ANCHOR_LEVEL1, "LEVEL 1 LAYOUT MATCHES JS GAME: " + layout_str())
	check(game.blocks().size() >= 15, "level has blocks (actual " + str(game.blocks().size()) + ", JS asserts >=15)")

	# ---- main menu ----
	check(game.screen == "menu" and game.main_menu_panel.visible, "boots into the main menu (game frozen behind it)")
	check(game.play_button.text == "Play" and game.settings_button.text == "Settings" and game.quit_button.text == "Quit", "main menu has Play / Settings / Quit")
	var win = game.get_window()   # game is untyped in the harness — no type inference available here
	check(win.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "content scaling on (canvas_items) — resolution changes scale the game itself")
	check(win.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "content scaling uses expand — the game fills the window, no letterbox")
	check(Vector2(win.content_scale_size) == Vector2(960, 640), "content scale base is the 960x640 design space")   # 4.7 types content_scale_size as Vector2i
	check(game._res_values == ["1280x720", "1920x1080", "2560x1440"], "resolution options are 720p / 1080p / 1440p")
	game.handle_mouse_click()
	await process_frame
	check(game.state.balls[0].stuck, "click ignored while the main menu is up (ball still stuck)")
	game.handle_key("escape")
	check(game.menu_open == true and game.back_button.text == "Back to menu", "Esc opens the Settings submenu over the main menu")
	game.handle_key("escape")
	check(game.menu_open == false and game.screen == "menu" and game.main_menu_panel.visible, "Esc again closes Settings back onto the main menu")
	game.play()
	check(game.screen == "game" and not game.main_menu_panel.visible, "Play starts the game")

	# ---- launch ----
	check(game.state.balls.size() == 1, "one ball rendered")
	var p0: Vector2 = Vector2(game.state.balls[0].x, game.state.balls[0].y)
	game.handle_mouse_click()   # canvas mousedown equivalent
	await process_frame
	var p1: Vector2 = Vector2(game.state.balls[0].x, game.state.balls[0].y)
	check(p1 != p0, "ball moves after launch")

	# deterministic section anchor (mirror of the JS harness Math.random override)
	game.override_rand = 0.05

	# ---- powerup tests ----
	game.apply_powerup("MULTI")
	check(game.state.balls.size() == 3, "MULTI spawns extra balls (3 balls)")
	game.apply_powerup("EXPAND")
	check(game.state.active.has("EXPAND") and game.state.active["EXPAND"] > 14.0, "EXPAND timer active")
	game.apply_powerup("LASER")
	await pump(4)
	game.handle_mouse_click()   # fires laser (no launch pending — all balls in flight)
	check(game.state.lasers.size() >= 2, "laser bolts alive (>= 2)")

	# ---- long play run ----
	print("diag: entering 600-frame run")
	var before: int = game.blocks().size()
	var startLevel: int = game.state.level
	await pump(600)
	print("diag: 600-frame run done")
	var destroyed: int = before - game.blocks().size()
	check(destroyed > 0 or game.state.level > startLevel, "blocks destroyed during 600-frame run (" + str(before) + " -> " + str(game.blocks().size()) + ", level " + str(startLevel) + " -> " + str(game.state.level) + ")")

	# ---- mouse no longer steers the paddle (user request: accidental bumps were maddening) ----
	var paddle_x_before: float = game.paddle.x
	game.mouse_x = 120.0
	await process_frame
	check(absf(game.paddle.x - paddle_x_before) < 0.001, "mouse motion no longer moves the paddle — keyboard only (" + str(paddle_x_before) + " -> " + str(game.paddle.x) + ")")
	game.handle_mouse_motion(420.0)
	await process_frame
	game.keys["d"] = true
	var key_x0: float = game.paddle.x
	await process_frame
	game.keys["d"] = false
	check(game.paddle.x > key_x0, "keyboard still steers the paddle (d key moved it " + str(game.paddle.x - key_x0) + " px)")

	# ---- level clear test (user-reported bug #2 regression, ported) ----
	var destructibles := []
	for b in game.blocks():
		if not game.blockTypes[b.t].indestructible:
			destructibles.append(b)
	var lv_before: int = game.state.level
	for b in destructibles:
		game.destroy_block(b, -1, false)   # top-level destructions -> hook fires once
	check(game.state.level == lv_before + 1, "clearing all destructibles advances the level")
	check(game.blocks().size() > 0, "new boxes spawned for the new level")
	check(layout_str() == ANCHOR_LEVEL2, "LEVEL 2 LAYOUT MATCHES JS GAME: " + layout_str())
	check(game.state.balls.size() >= 1 and game.state.balls[0].stuck, "ball respawns stuck on paddle for the new level")

	# ---- life loss (pinned anchor ball, mirror of JS) ----
	var livesBefore: int = game.state.lives
	game.state.balls[0].x = 300.0; game.state.balls[0].y = 300.0
	await pump(2)
	game.state.balls[0].x = 480.0; game.state.balls[0].y = 700.0; game.state.balls[0].vx = 0.0; game.state.balls[0].vy = 300.0; game.state.balls[0].stuck = false
	await pump(4)
	check(game.state.lives == livesBefore - 1, "life lost when all balls leave (" + str(livesBefore) + " -> " + str(game.state.lives) + ")")
	check(game.state.balls.size() == 1 and game.state.balls[0].stuck, "ball respawns stuck on paddle")
	await pump(3)
	game.handle_mouse_click()
	check(not game.state.balls[0].stuck, "click launches respawned ball")

	# ---- background auto-rotation (B is retired — papers rotate with the levels, picker can pin one) ----
	game.state.level = 1; game.build_level()   # deterministic paper bed: the demolition stages above may already have levelled up
	check(game.bg_images.size() >= 1 and game.bg_index == 0, "level 1 wears the first paper stock — auto mode, nobody pressed anything")
	check(game.bg_label() == "background: bg1.png", "background label reflects the live paper: " + game.bg_label())
	game.handle_key("b")   # the retired key must be inert now
	await process_frame
	check(game.bg_label() == "background: bg1.png", "retired B key is inert — papers no longer respond to it")
	game.state.level = 2; game.build_level()
	check(game.bg_label() == "background: bg2.png", "level up rotates to the next paper: " + game.bg_label())
	game._on_bg_selected(3)   # pin bg3.png via the settings picker
	check(game.bg_label() == "background: bg3.png" and String(game.settings["bg"]) == "bg3.png", "picker pins a sheet and persists the pin")
	game.state.level = 4; game.build_level()
	check(game.bg_label() == "background: bg3.png", "a pinned sheet survives level changes: " + game.bg_label())
	game._on_bg_selected(0)   # back to auto
	check(game.bg_label() == "background: bg4.png", "auto re-resolves from the current level: " + game.bg_label())
	game.state.level = 1; game.build_level()   # hand the harness world back exactly as the LEVEL 1 anchors expect

	# ---- pause tests (user-reported bug #1 regression, ported) ----
	check(game.state.balls.size() >= 1, "a ball exists before pause test")
	game.state.balls[0].x = 300.0; game.state.balls[0].y = 300.0   # keep it safely in flight
	game.handle_mouse_click()   # launch if stuck
	await pump(2)
	check(not game.state.balls[0].stuck, "ball in flight for pause test")
	game.handle_key("escape")
	check(game.state.paused == true, "Esc pauses — the one menu key doubles as the pause switch")
	var ballSnapshot: String = jstr(game.state.balls)
	var paddleSnapshot: float = game.paddle.x
	var livesSnapshot: int = game.state.lives
	await pump(60)
	check(jstr(game.state.balls) == ballSnapshot, "paused: ball frozen — no movement, no life loss")
	check(game.paddle.x == paddleSnapshot, "paused: paddle frozen")
	check(game.state.lives == livesSnapshot, "paused: no lives drain while paused")
	game.handle_key("escape")
	check(game.state.paused == false, "Esc again closes the sheet and resumes")
	var ballSnapshot2: String = jstr(game.state.balls)
	await pump(60)
	check(jstr(game.state.balls) != ballSnapshot2, "resumed: ball moving again")

	# ---- game over path (must run unpaused, since a true pause cannot drain lives) ----
	game.state.lives = 1
	for b in game.state.balls:
		b.x = 480.0; b.y = 700.0; b.vx = 0.0; b.vy = 300.0; b.stuck = false
	await pump(3)
	check(game.state.over == true, "game over triggered at 0 lives")
	check(str(game.high_score_saved()) == str(maxi(0, game.state.score)), "high score persisted to user:// (" + str(game.high_score_saved()) + ")")

	# ---- restart ----
	game.handle_key("r")
	check(game.state.over == false and game.state.score == 0 and game.state.lives == 3 and game.state.paused == false, "R restarts the game")

	# ---- music + settings menu (new-feature checks, appended after the original suite) ----
	game.handle_key("escape")
	check(game.menu_open == true, "Esc opens the pause menu in game")
	var menuSnapBalls: String = jstr(game.state.balls)
	var menuSnapPaddle: float = game.paddle.x
	var menuSnapScore: int = game.state.score
	await pump(30)
	check(jstr(game.state.balls) == menuSnapBalls and game.paddle.x == menuSnapPaddle and game.state.score == menuSnapScore, "menu open freezes the game like pause (30 frames, nothing moved)")
	game.handle_key("escape")   # close; then click-launch must reach gameplay again
	game.handle_mouse_click()
	await pump(10)
	check(game.menu_open == false and game.state.paused == false and jstr(game.state.balls) != menuSnapBalls, "Esc closes the menu, game not paused, click-launch moves the ball")
	game.set_setting("sfx", 0.5)
	game.set_setting("music", 0.8)
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.5)) < 0.2, "SFX bus volume ≈ linear_to_db(0.5)")
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.8)) < 0.2, "Music bus volume ≈ linear_to_db(0.8)")
	var sCfg := ConfigFile.new()
	var sErr := sCfg.load("user://breakout_settings.cfg")
	check(sErr == OK and absf(float(sCfg.get_value("settings", "sfx_vol", -1.0)) - 0.5) < 0.01 and absf(float(sCfg.get_value("settings", "music_vol", -1.0)) - 0.8) < 0.01, "settings persisted to user://breakout_settings.cfg")
	game.set_setting("sfx", 1.0)   # restore defaults so the run exits clean
	game.set_setting("music", 0.5)

	# ---- settings reached via the buttons (in-game) ----
	game.settings_button.pressed.emit()
	check(game.menu_open == true and game.pause_row.visible and not game.back_button.visible and str(game.sheet_title.text) == "Paused", "the Settings button in-game pauses too — one unified sheet (Paused + quit row replaces Back to menu)")
	game.back_button.pressed.emit()
	check(game.menu_open == false and game.screen == "game", "the toggle closes the sheet back to the game")

	# ---- lava ball + laser melts steel (new feature checks, appended) ----
	check(game.POWERUPS.has("LAVA") and game.POWERUPS["LAVA"].letter == "L" and game.POWERUPS["LAVA"].good and float(game.POWERUPS["LAVA"].duration) > 0.0, "LAVA power-up registered (letter L, good, timed)")
	game.menu_open = false
	game.state.paused = false
	game.state.drops = []
	game.state.lasers = []   # any stale bolts from the click tests must not score during the deterministic section below
	game.state.active = {}   # deterministic power-up bookkeeping for the section below
	game.state.combo = 0
	game.state.balls = [game.new_ball(480.0, 400.0, -90)]   # one isolated stationary ball in clear air (block rows never reach below y=352)
	game.state.balls[0].vx = 0.0; game.state.balls[0].vy = 0.0
	var steel_a = {"c": 6, "r": 10, "t": "steel", "hp": 0, "color": "#78909c", "x": 480.0 - game.CELL_W / 2.0, "y": 400.0 - game.CELL_H / 2.0}
	game.blocks_data.append(steel_a)
	var score_a: int = game.state.score
	game.update(0.016)
	check(game.blocks().has(steel_a) and int(game.state.score) == score_a + 5, "plain ball cannot break steel (control: +5 clink, block stands)")
	game.apply_powerup("LAVA")
	check(game.state.active.has("LAVA") and float(game.state.active["LAVA"]) > 9.0, "LAVA timer starts (10 s)")
	game.update(0.016)   # molten ball touches the steel block
	check(not game.blocks().has(steel_a) and int(game.state.score) == score_a + 10, "lava ball one-shots indestructible steel")
	game.state.drops = []   # the destroyed steel rolled a drop (override_rand 0.05 < 0.12) — park it out of the next frame's way
	var steel_b = {"c": 2, "r": 10, "t": "steel", "hp": 0, "color": "#78909c", "x": 148.0, "y": 400.0}
	game.blocks_data.append(steel_b)
	game.state.lasers = [{"x": steel_b["x"] + game.CELL_W / 2.0, "y": steel_b["y"] + game.CELL_H * 0.6, "ttl": 1.0}]
	game.update(0.001)   # bolt advances 0.9 px — the tip stays inside the block and vaporizes it
	check(not game.blocks().has(steel_b), "laser bolt breaks metal (steel no longer blocks the laser)")

	# molten ball burns THROUGH blocks instead of bouncing back off them
	var steel_c = {"c": 5, "r": 10, "t": "steel", "hp": 0, "color": "#78909c", "x": 444.0, "y": 374.0}
	game.blocks_data.append(steel_c)
	game.state.balls[0].x = 480.0; game.state.balls[0].y = 400.0; game.state.balls[0].vx = 0.0; game.state.balls[0].vy = -400.0; game.state.balls[0].stuck = false
	game.update(0.016)   # ball flies up into the steel — must eat through it and keep flying
	check(not game.blocks().has(steel_c) and float(game.state.balls[0].vy) < 0.0, "lava ball burns through — keeps flying instead of bouncing")

	# ---- gold blocks, shield floor-guard, combo system (the big expansion pass) ----
	game.override_rand = 0.95   # unfavourable roll from here on: only gold's forced drop may fall in this section
	check(game.POWERUPS.has("SHIELD") and game.POWERUPS["SHIELD"].letter == "G" and game.POWERUPS["SHIELD"].good and float(game.POWERUPS["SHIELD"].duration) > 0.0, "SHIELD power-up registered (letter G, good, timed)")
	var icons_ok := true
	for k in game.POWERUPS.keys():
		var icon: Array = game.POWERUPS[k].icon
		var inked := 0
		if icon.size() != 9:
			icons_ok = false
		for row in icon:
			if row.length() != 13:
				icons_ok = false
			inked += row.length() - row.count(".")   # all-blank padding rows are legal — an all-blank icon is not
		if inked == 0:
			icons_ok = false
	check(icons_ok, "every power-up ships a well-formed 13x9 pixel icon (the capsule letters are legacy data now)")
	check(game.blockTypes.has("gold") and int(game.blockTypes["gold"].score) == 50 and not game.blockTypes["gold"].indestructible, "gold block registered (50 pts, destructible)")
	game.state.drops = []
	var gold_a = {"c": 1, "r": 11, "t": "gold", "hp": 1, "color": "#ffd54f", "x": 240.0, "y": 500.0}
	game.blocks_data.append(gold_a)
	game.destroy_block(gold_a, -1)
	check(game.state.drops.size() == 1, "gold block always drops a capsule (95 % roll would normally miss)")
	var combo_before: int = game.state.combo
	var normals := []
	for blk in game.blocks():
		if String(blk.t) == "normal":
			normals.append(blk)
			if normals.size() >= game.COMBO_STEP:
				break
	for blk in normals:
		game.destroy_block(blk, -1)
	check(normals.size() == game.COMBO_STEP and int(game.state.combo) == combo_before + game.COMBO_STEP, "combo climbs one per block kill (" + str(combo_before) + " -> " + str(game.state.combo) + ")")
	var saw_combo := false
	for pp in game.state.popups:
		if String(pp.text).contains("COMBO"):
			saw_combo = true
	check(saw_combo, "combo pays a floating bonus popup at every step")
	game.state.drops = []
	game.state.active["SHIELD"] = 8.0
	game.state.balls[0].x = 600.0; game.state.balls[0].y = 645.0; game.state.balls[0].vx = 0.0; game.state.balls[0].vy = 400.0; game.state.balls[0].stuck = false
	var lives_s0: int = game.state.lives
	game.update(0.016)   # the ball walks off the floor line — the guard must bounce it
	check(game.state.balls[0].vy < 0.0 and game.state.lives == lives_s0, "shield band bounces the falling ball instead of eating a life")
	check(game.state.trail.size() > 0 and game.state.trail.size() <= game.MAX_TRAIL, "ball trail is alive and bounded")
	for fb in game.state.balls:
		fb.stuck = true; fb.vx = 0.0; fb.vy = 0.0
	for _i in 80:
		game.update(0.033)   # 2.6 s of quiet driven by direct steps — no awaits, so nothing else moves
	check(game.state.popups.size() == 0 and game.state.trail.size() == 0, "popups & trail fully decay once play goes quiet")

	# ---- shipped music (music/neon_corridor.wav) ----
	check(game.music_playlist.size() >= 1, "music folder ships a track (" + str(game.music_playlist.size()) + " loaded)")
	check(game.music_player.stream != null and game.music_player.playing, "theme autoloads and plays at boot")

	# ---- FEVER mode + TNT domino waves (the Excitement! pass) ----
	game.override_rand = 0.95   # no incidental drops from here on (gold never rolls at level 1)
	game.restart()
	game.screen = "game"
	game.menu_open = false
	game.state.paused = false
	game.state.fever = 0.0
	game.state.combo = 0
	game.state.booms = []
	var fever_ball = game.state.balls[0]
	fever_ball.stuck = true; fever_ball.vx = 0.0; fever_ball.vy = 0.0
	check(float(game.state.fever) == 0.0 and int(game.FEVER_TRIGGER) >= 6 and float(game.FEVER_TIME) >= 5.0, "FEVER constants ship (trigger " + str(game.FEVER_TRIGGER) + ", " + str(game.FEVER_TIME) + " s, exit bonus " + str(game.FEVER_BONUS) + ")")
	var ignite_queue := []
	for blk in game.blocks():
		if String(blk.t) != "steel" and ignite_queue.size() < game.FEVER_TRIGGER:
			ignite_queue.append(blk)
	for blk in ignite_queue:
		game.destroy_block(blk, -1)
	check(float(game.state.fever) > 0.0 and int(game.state.combo) >= game.FEVER_TRIGGER, "FEVER ignites at combo " + str(game.state.combo) + " (the " + str(game.FEVER_TRIGGER) + "th consecutive kill starts the fire)")
	game.state.fever = 1.0
	var relight_blk = null
	for blk in game.blocks():
		if String(blk.t) == "normal":
			relight_blk = blk
			break
	game.destroy_block(relight_blk, -1)
	check(float(game.state.fever) == game.FEVER_TIME, "a kill during FEVER re-lights the clock back to full")
	# doubling proof via steel clink: it scores WITHOUT dying, so combo/drops can never muddy the delta
	var steel_x = {"c": 7, "r": 9, "t": "steel", "hp": 0, "color": "#78909c", "x": 444.0, "y": 287.0}
	game.blocks_data.append(steel_x)
	fever_ball.stuck = false
	fever_ball.x = 480.0; fever_ball.y = 300.0; fever_ball.vx = 0.0; fever_ball.vy = 0.0
	game.state.fever = game.FEVER_TIME
	var s_fv0: int = game.state.score
	game.update(0.016)   # ball rests inside the steel — clink at ×2
	var d_fevered: int = int(game.state.score) - s_fv0
	game.state.fever = 0.0
	var s_pl0: int = game.state.score
	game.update(0.016)   # same clink, normal temperature
	var d_plain: int = int(game.state.score) - s_pl0
	check(d_fevered == 10 and d_plain == 5, "FEVER doubles every payout (steel clink " + str(d_plain) + " → " + str(d_fevered) + ")")
	game.state.balls[0].stuck = true
	game.state.balls[0].vx = 0.0; game.state.balls[0].vy = 0.0
	game.state.fever = 0.5
	var s_out0: int = game.state.score
	game.update(0.8)
	var saw_fever_out := false
	for pp in game.state.popups:
		if String(pp.text).contains("FEVER OUT"):
			saw_fever_out = true
	check(float(game.state.fever) == 0.0 and int(game.state.score) == s_out0 + game.FEVER_BONUS and saw_fever_out, "FEVER expires with a parting bonus and a floating popup (+" + str(game.FEVER_BONUS) + ")")
	# TNT domino choreography on a clean field: A (bomb) → B (bomb) → C (normal), steel S hiding under B
	game.state.drops = []
	game.blocks_data.clear()
	var bA := {"c": 4, "r": 5, "t": "explode", "hp": 1, "color": "#ffee58", "x": 300.0, "y": 208.0}
	var bB := {"c": 5, "r": 5, "t": "explode", "hp": 1, "color": "#ffee58", "x": 375.0, "y": 208.0}
	var bC := {"c": 6, "r": 5, "t": "normal", "hp": 1, "color": "#ef5350", "x": 450.0, "y": 208.0}
	var bS := {"c": 5, "r": 6, "t": "steel", "hp": 0, "color": "#78909c", "x": 375.0, "y": 237.0}
	for bb in [bA, bB, bC, bS]:
		game.blocks_data.append(bb)
	var sD0: int = game.state.score
	game.state.booms = []
	game.state.shake = 0.0
	game.destroy_block(bA, -1)
	check(not game.blocks_data.has(bA) and game.blocks_data.has(bB) and bB.get("fuse") != null, "bomb A detonates but its neighbour B stays standing, fuse lit — the wave ROLLS")
	check(not game.blocks_data.has(bS) and game.blocks_data.has(bC), "the 3×3 blast chain-kills its neighbours (steel included), but C sits outside A's radius and stands — the wave must roll one more beat")
	check(game.state.booms.size() >= 1 and float(game.state.shake) >= 7.0, "blast spawns a shockwave ring and shakes the screen (" + str(game.state.booms.size()) + " ring(s), shake " + str(game.state.shake) + ")")
	check(int(game.state.score) >= sD0 + 15, "wave bonus and chain-kill payouts both land (+ wave 10, steel 5 — got " + str(int(game.state.score) - sD0) + ")")
	game.update(0.2)   # past CHAIN_FUSE — the domino must fall on its beat
	check(not game.blocks_data.has(bB) and not game.blocks_data.has(bC) and game.state.booms.size() >= 2, "the fused domino pops on its beat and its own wave takes C with it — second shockwave proves the wave is visible")
	check(int(game.state.level) == 2, "the emptied field auto-clears even when the bomb wave lands the final blow (old code missed that case)")

	# ---- the shipped music set + local leaderboard + pause sheet (menu & menu-adjacent pass) ----
	check(game.music_playlist.size() >= 3, "the music set ships at least three tracks (" + str(game.music_playlist.size()) + " loaded)")
	game.leaderboard.clear()
	game.add_leaderboard_entry(100, 1)
	game.add_leaderboard_entry(500, 3)
	game.add_leaderboard_entry(300, 2)
	check(game.leaderboard.size() == 3 and int(game.leaderboard[0].score) == 500 and int(game.leaderboard[2].score) == 100, "the leaderboard ranks finished runs best-first")
	for i in 10:
		game.add_leaderboard_entry(10 * i + 7, 1)   # 7..97 — all smaller than the three above, so the board must start trimming
	check(game.leaderboard.size() == game.BOARD_MAX, "the leaderboard trims to its " + str(game.BOARD_MAX) + "-best cap")
	var size_before_zero: int = game.leaderboard.size()
	game.add_leaderboard_entry(0, 1)
	check(game.leaderboard.size() == size_before_zero, "a scoreless run never lands on the board")
	game.save_high()
	game.load_leaderboard()
	check(game.leaderboard.size() == game.BOARD_MAX and int(game.leaderboard[0].score) == 500, "the board survives the cfg round-trip (saved, reloaded, still ranked)")
	game.play()
	game.state.score = 420
	game.state.level = 5
	game.toggle_menu()   # THE Esc menu — pause + settings + quit in one sheet
	game.update(0.016)
	check(game.menu_open and bool(game.state.paused) and game.menu_panel.visible and game.pause_row.visible and not game.back_button.visible and str(game.sheet_title.text) == "Paused", "Esc opens ONE sheet that pauses the game: run info on top, Resume / Quit to menu / Quit game inside — no parallel pause menu")
	game.handle_key("escape")
	check(not game.menu_open and not bool(game.state.paused), "Esc again closes the sheet and resumes — the key stays the only menu control")
	game.toggle_menu()
	var board_before: int = game.leaderboard.size()
	game.quit_to_menu()
	var saw_abandoned := false
	for row_entry in game.leaderboard:
		if int(row_entry.score) == 420:
			saw_abandoned = true
	check(game.screen == "menu" and bool(game.state.over) == false and int(game.state.score) == 0 and game.leaderboard.size() == mini(board_before + 1, game.BOARD_MAX) and saw_abandoned, "Quit to menu books the abandoned run (+420), resets the game and hands the title scene back")
	game.open_leaderboard()
	check(game.leaderboard_open and game.leaderboard_panel.visible and game.leaderboard_rows.get_child_count() >= 1 and game.lb_close_button.visible, "the leaderboard opens as its own submenu card over the title scene (rows rebuilt on open — the saved runs are in there)")
	game.handle_key("escape")
	check(not game.leaderboard_open and not game.menu_open, "Esc dismisses the leaderboard — and does not sneak Settings open behind it")
	game.open_leaderboard()
	game.toggle_menu()
	check(bool(game.menu_open) and not bool(game.leaderboard_open), "the two submenus never stack — one modal at a time")
	game.toggle_menu()
	game.restart()
	check(str(game.state.message) == "LEVEL 1" and float(game.state.msgTimer) > 0.0, "a new level announces itself with a brief title card (the permanent HUD LEVEL plate is retired)")
	game.play()
	game.state.score = 310
	var size_pre: int = game.leaderboard.size()
	game._on_window_close()   # simulates the X button mid-run: the pending score must be booked before the app dies
	var saw_close := false
	for row_entry in game.leaderboard:
		if int(row_entry.score) == 310:
			saw_close = true
	check(game.leaderboard.size() == mini(size_pre + 1, game.BOARD_MAX) and saw_close, "closing the window mid-run books the pending run — quitting the game no longer deletes scores")

	print("\n" + ("ALL CHECKS PASSED" if fails == 0 else str(fails) + " CHECK(S) FAILED"))
	quit(0 if fails == 0 else 1)
