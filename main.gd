extends Control
# Breakout — Godot 4 port of breakout-game/game.js (single-file philosophy).
# Everything renders via _draw() on this root Control; audio via on-demand WAV tones.

const W := 960.0
const H := 640.0
const PADDLE_BASE_W := 120.0
const PADDLE_H := 16.0
const BALL_R := 8.0
const BALL_BASE_SPEED := 340.0
const BALL_SPEED_STEP := 6.0
const BALL_MAX_SPEED := 560.0
const GRID_COLS := 12
const CELL_W := 72.0
const CELL_H := 26.0
const GAP := 3.0
const FIELD_TOP := 55.0
const DROP_CHANCE := 0.12
const DROP_SPEED := 140.0
const TRAIL_LIFE := 0.3
const MAX_TRAIL := 120
const POPUP_LIFE := 1.1
const MAX_POPUPS := 40
const COMBO_STEP := 4      # every N consecutive block kills = one combo tier payout
const COMBO_BONUS := 50    # bonus points per tier (tier capped at 5)
const FEVER_TRIGGER := 10  # combo hits needed to ignite FEVER mode
const FEVER_TIME := 8.0    # seconds — every kill during FEVER re-lights the clock
const FEVER_BONUS := 100   # the parting gift when the heat finally goes cold
const CHAIN_FUSE := 0.13   # seconds before a lit domino bomb pops — the chain visibly rolls
const PU_PIXEL := 2.0      # screen px per icon pixel — the 13x9 POWERUPS sprites draw at up to 26x18 px
const NEAR_MISS_BONUS := 25       # a last-gasp save (shield floor, paddle edge, wall graze) pays for the nerve
const COMBO_SPEED_STEP := 3.5     # extra ball speed per combo tier on the next paddle bounce — streaks are a gamble
const PRESS_INTERVAL := 25.0      # seconds between the brick field dropping a row — the press is always coming
const PRESS_WARN := 5.0           # warn this long before a descent
const RUSH_TIME := 8.0            # every third level: a gold rush with regenerating blocks and ×3 scoring
const RUSH_WAVES := 5
const RUSH_MULT := 3.0

# mulberry32 exact emulation (32-bit semantics on GDScript's 64-bit ints)
class RNG32:
	var s := 0
	func setup(seedval: int) -> void: s = seedval & 0xFFFFFFFF
	func u32(v: int) -> int: return v & 0xFFFFFFFF
	func s32(v: int) -> int:
		var u: int = v & 0xFFFFFFFF
		return u if u < 2147483648 else u - 4294967296
	func ushift(v: int, n: int) -> int: return (v & 0xFFFFFFFF) >> n
	func imul(a: int, b: int) -> int: return s32(a * b)
	func next() -> float:
		s = s32(s + 0x6D2B79F5)
		var t: int = imul(s32(s ^ ushift(s, 15)), s32(1 | s))
		var a: int = t
		t = s32(s32(a + imul(s32(a ^ ushift(a, 7)), s32(61 | a))) ^ a)
		return float(u32(s32(t) ^ ushift(t, 14))) / 4294967296.0

const BLOCK_TYPES := {
	"normal": { "hp": 1, "score": 10, "palette": ["#c8402e", "#c96f2a", "#c9a227", "#4c8a54", "#2a5f8f", "#7b5e8c"], "label": "", "stroke": Color(0,0,0,0), "stroke_alpha": 0.0, "indestructible": false },
	"tough": { "hp": 2, "score": 25, "palette": ["#7a5c49"], "label": "", "stroke": Color(0,0,0,0), "stroke_alpha": 0.0, "indestructible": false },
	"tough3": { "hp": 3, "score": 40, "palette": ["#3f5a66"], "label": "", "stroke": Color(0,0,0,0), "stroke_alpha": 0.0, "indestructible": false },
	"explode": { "hp": 1, "score": 30, "palette": ["#d8c24a"], "label": "*", "stroke": Color("#a05210", 1.0), "stroke_alpha": 1.0, "indestructible": false },
	"steel": { "hp": 0, "score": 5, "palette": ["#67757a"], "label": "", "stroke": Color(0,0,0,0), "stroke_alpha": 0.0, "indestructible": true },
	"gold": { "hp": 1, "score": 50, "palette": ["#c9971f"], "label": "★", "stroke": Color("#a05210", 1.0), "stroke_alpha": 0.9, "indestructible": false },
	"boss": { "hp": 8, "score": 500, "palette": ["#6b2f2a"], "label": "◆", "stroke": Color("#d8c24a", 1.0), "stroke_alpha": 1.0, "indestructible": false },
}

const BOSS_ICON := [   # 13x9 skull — bone-white on the dark boss brick, with dark eye sockets and teeth
	"...KKKKKKK...",
	"..KWWWWWWWK..",
	".KWWWWWWWWWK.",
	".KWKKWWWKKWK.",
	".KWKKWWWKKWK.",
	".KWWWWWWWWWK.",
	"..KWWKWWKWWK.",
	"..K.WW.WW.W..",
	".............",
]
const TNT_ICON := [   # 9x7 red stick with a band and a lit fuse
	"...KFK...",
	"..KKKKK..",
	".KFFFFFK.",
	".KFWWWFK.",
	".KFDDFDK.",
	".KFFFFFK.",
	"..KKKKK..",
]
const GOLD_ICON := [   # 9x7 glinting star — "this brick drops a power-up"
	"....F....",
	"...FFF...",
	".FFFWFFF.",
	"..FFFFF..",
	"...FFF...",
	"..FF.FF..",
	".F.....F.",
]

# Power-up drops render as pixel-art sprites, never letters: "icon" is a 13x9 char grid drawn at PU_PIXEL px.
# Legend: "." transparent · F fill (p.color) · D dark edge (darkened 0.45) · L light edge (lightened 0.35,
# light from top-left) · K ink (COLOR_SLOTS white) · W paper-white glint — applied by draw_pixel_icon.
const POWERUPS := {
	"MULTI": { "letter": "M", "name": "Multiball", "good": true, "color": Color("#1e7268"), "duration": 0.0, "icon": ["...FF...FF...", "..FFWF.FFWF..", "..FFFF.FFFF..", "...FF...FF...", ".............", ".....FFF.....", "....FWWWF....", "....FFFFF....", ".....FFF....."] },
	"EXPAND": { "letter": "W", "name": "Expand paddle", "good": true, "color": Color("#1e7268"), "duration": 15.0, "icon": [".............", ".............", "K...........K", "KK...FFF...KK", "KKK.FFFFF.KKK", "KK...DDD...KK", "K...........K", ".............", "............."] },
	"SHRINK": { "letter": "S", "name": "Shrink paddle", "good": false, "color": Color("#a83326"), "duration": 10.0, "icon": [".............", ".............", "KKK.......KKK", ".KK..FFF..KK.", "..K.FFFFF.K..", ".KK..DDD..KK.", "KKK.......KKK", ".............", "............."] },
	"SLOW": { "letter": "T", "name": "Slow ball", "good": true, "color": Color("#1e7268"), "duration": 12.0, "icon": [".............", "...KKKKKKK...", "...KWWWWWK...", "....KWWWK....", ".....KWK.....", "......K......", ".....KFK.....", "....KFFFK....", "...KKKKKKK..."] },
	"FAST": { "letter": "F", "name": "Fast ball", "good": false, "color": Color("#a83326"), "duration": 10.0, "icon": [".............", ".....KKK.....", "....KKK......", "...KKKKKKKK..", "..KKKKKKK....", ".....KKK.....", "....KKK......", "....KK.......", "............."] },
	"LIFE": { "letter": "+", "name": "Extra life", "good": true, "color": Color("#1e7268"), "duration": 0.0, "icon": [".............", "..KK.....KK..", ".KWFK...KFFK.", "KFFFFK.KFFFFK", "KFFFFFFFFFFFK", ".KFFFFFFFFFK.", "..KFFFFFFFK..", "...KFFFFFK...", "....KFFFK...."] },
	"LASER": { "letter": "Z", "name": "Laser", "good": true, "color": Color("#1e7268"), "duration": 12.0, "icon": ["...K.....K...", "...K.....K...", "...K.....K...", "...K.....K...", "...K.....K...", "...K.....K...", "..KKKKKKKKK..", "..FFFFFFFFF..", "..DDDDDDDDD.."] },
	"STICKY": { "letter": "C", "name": "Sticky paddle", "good": true, "color": Color("#1e7268"), "duration": 15.0, "icon": [".............", ".....FFF.....", "....FWWWF....", "....FFFFF....", ".....DDD.....", "......K......", "...KKKKKKK...", "...FFFFFFF...", "...DDDDDDD..."] },
	"LAVA": { "letter": "L", "name": "Lava ball", "good": true, "color": Color("#b8501e"), "duration": 10.0, "icon": [".............", "......F......", ".....LFF.....", "....LFFFF....", "...LLFFFFF...", "..LLFFFFFD...", "..LFFFFFFFD..", "...FFFFFFFD..", "....DDDDDD..."] },
	"SHIELD": { "letter": "G", "name": "Shield", "good": true, "color": Color("#2a5f8f"), "duration": 8.0, "icon": ["..KKKKKKKKK..", "..KFFFFFFFK..", "..KFFFFFFFK..", "..KFFWWWFFK..", "..KFFFFFFFK..", "...KFFFFFK...", "...KFFFFFK...", "....KFFFK....", ".....KFK....."] },
}

const COLOR_SLOTS := {
	"white": Color("#2b2620", 1.0),
	"white70": Color("#2b2620", 0.70),
	"dim_white": Color("#2b2620", 0.4),
	"dark_white": Color("#2b2620", 0.25),
	"dark_overlay": Color(0, 0, 0, 0.5),
	"dim_overlay": Color(0, 0, 0, 0.28),
	"banner_overlay": Color(0.96, 0.93, 0.86, 0.92),
	"hud_dim": Color("#67757a", 1.0),
	"hud_green": Color("#25756b", 1.0),
	"hud_red": Color("#9c4a3e", 1.0),
	"glow_blue": Color("#2a5f8f", 1.0),
	"glow_teal": Color("#1e7268", 1.0),
	"glow_red": Color("#93202f", 1.0),
	"glow_lava": Color("#b8501e", 1.0),
	"brown_label": Color("#4a3826", 1.0),
	"grad_top": Color("#f2e8d5", 1.0),
	"grad_bottom": Color("#e6d7ba", 1.0),
	"black": Color(0, 0, 0, 1.0),
}

var state := {
	"running": true, "paused": false, "over": false, "message": "", "msgTimer": 0.0, "msgPlain": false,
	"score": 0, "high": 0, "level": 1, "lives": 3,
	"paddleW": PADDLE_BASE_W,
	"active": {},
	"balls": [], "drops": [], "lasers": [], "particles": [],
	"trail": [], "popups": [],
	"combo": 0, "comboBest": 0, "flash": 0.0,
	"shake": 0.0,
	"fever": 0.0, "booms": [],
	"pressTimer": PRESS_INTERVAL, "pressWarned": false,
	"rush": false, "rushTimer": 0.0, "rushWaveTimer": 0.0, "rushWavesLeft": 0,
}
var paddle := {"x": W / 2 - PADDLE_BASE_W / 2, "y": H - 40.0, "squash": 0.0}
var keys := {}
var mouse_x: Variant = null

# ---------------- Mobile touch input state ----------------
var touch_id_left: int = -1        # finger tracking left-side joystick
var touch_id_right: int = -1       # finger tracking right-side tap zone
var touch_pos_left: Vector2 = Vector2.INF
var touch_pos_right: Vector2 = Vector2.INF
var joystick_active: bool = false  # is left-side touch currently active?
var joystick_origin: Vector2 = Vector2(80.0, H - 100.0)  # joystick center
var joystick_radius: float = 50.0  # joystick visual radius
var joystick_stick: Vector2 = Vector2.ZERO  # current stick displacement
var pause_button_rect := Rect2(16.0, 84.0, 45.0, 34.0)  # pause button area (top-left, under the score/hi/fever stack)
var touch_hint_timer: float = 0.0  # fade timer for the on-screen instruction
var touch_hint_visible: bool = true  # show hint during first few seconds of play
var _touch_seen := false              # flips true the first time a real finger lands — proves touch without trusting hardware probes
var bg_time := 0.0   # free-running visual clock (star drift/twinkle, bobbing, pulses) — never consumes the rr() stream
var sticky_ball: Variant = null
var blocks_data: Array = []
var bg_names: Array = []
var override_rand: float = -1.0   # test hook: >= 0 forces this value for all game random decisions
var blockTypes := BLOCK_TYPES   # lowercase alias — harness uses game.blockTypes (JS API parity, camelCase required)

func blocks() -> Array: return blocks_data   # harness API mirrors the JS game's blocks() function

# ---------------- Backgrounds (PNG paper stocks, auto-rotating) ----------------
# Drop PNGs in backgrounds/; backgrounds/manifest.json merges extra names.
# settings["bg"] = "auto" (default — a different paper stock every level) or a pinned file name.
var bg_images := {}   # name -> texture
var bg_index := -1    # -1 = default plain gradient (fallback only, when no PNGs are installed)
var bg_label_str := "background: (default gradient)"

func scan_bg_names() -> Array:
	var out := []
	var da := DirAccess.open("res://backgrounds")
	if da:
		da.list_dir_begin() # TODOConverter3To4 fill missing arguments https://github.com/godotengine/godot/pull/40547
		var f := da.get_next()
		while f != "":
			if f.get_extension().to_lower() == "png":
				out.append(f)
			f = da.get_next()
		da.list_dir_end()
	out.sort()
	return out

func load_backgrounds() -> void:
	var names := scan_bg_names()
	var manifest := FileAccess.get_file_as_string("res://backgrounds/manifest.json")
	if manifest != "":
		var j = JSON.parse_string(manifest)
		if typeof(j) == TYPE_DICTIONARY and typeof(j.get("backgrounds", null)) == TYPE_ARRAY:
			for n in j["backgrounds"]:
				if typeof(n) == TYPE_STRING and not names.has(n):
					names.append(n)
	bg_names = names   # scan+manifest merged list feeds bg_label_update() via the index
	for n in names:
		var tex = load("res://backgrounds/" + n)
		if tex:
			bg_images[n] = tex
	bg_label_update()
	print("backgrounds: ", bg_images.size(), "/", names.size(), " loaded — ", ", ".join(names))

func bg_count() -> int: return bg_images.size()

func bg_label() -> String: return bg_label_str   # harness API mirrors the JS game's bgLabel

func bg_label_update() -> void:
	bg_label_str = "background: " + ("(default gradient)" if bg_index < 0 else str(bg_names[bg_index]))
	if bg_images.size() == 0: bg_index = -1

func set_background(i: int) -> void:
	if bg_images.size() == 0:   # GDScript crashes on % 0 — guard before the modulo
		bg_index = -1
		bg_label_update()
		return
	bg_index = ((i % bg_images.size()) + bg_images.size()) % bg_images.size()
	bg_label_update()

func auto_background() -> void:   # "auto" paper mode: level N wears stock (N-1) % count — every level a different sheet, nobody presses anything
	if String(settings.get("bg", "auto")) != "auto":
		return   # the settings picker pinned a specific sheet
	if bg_count() == 0:
		bg_index = -1   # no PNGs installed: the plain gradient carries the menu and the field
		bg_label_update()
		return
	set_background(int(state.level) - 1)

func apply_bg_setting() -> void:   # resolve settings["bg"] ("auto" | file name) onto the live index — boot path only, build_level owns rotation after that
	if String(settings.get("bg", "auto")) != "auto":
		var i: int = bg_names.find(String(settings["bg"]))
		if i >= 0:
			set_background(i)
			return
		settings["bg"] = "auto"   # a saved name that fell off the disk can't strand the game on nothing
	auto_background()

# ---------------- Audio (tiny synth tones, generated on demand) ----------------
const SAMPLE_RATE := 44100

func make_tone(freq: float, type: String, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var pbytes := PackedByteArray()
	pbytes.resize(n * 2)   # 2 bytes per 16-bit sample
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		var phase: float = fmod(freq * t, 1.0)
		var wave := 0.0
		if type == "square": wave = 1.0 if phase < 0.5 else -1.0
		elif type == "sawtooth": wave = 2.0 * phase - 1.0
		else: wave = sin(TAU * phase)
		var env: float = vol * pow(0.001 / vol, t / dur)
		var sv: int = int(clampf(32767.0 * env * wave, -32768.0, 32767.0))
		pbytes[i * 2] = sv & 0xFF
		pbytes[i * 2 + 1] = (sv >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS   # 16-bit PCM class constant (nested Format.FORMAT_PCM not exposed as static scope here)
	wav.data = pbytes   # raw 16-bit PCM, little-endian — written per byte above
	return wav

var audio_pool := []

func play_tone(freq: float, dur: float, type: String, vol: float) -> void:
	var p = null
	for pl in audio_pool:
		if not pl.playing:
			p = pl
			break
	if p == null:
		p = audio_pool[0]   # steal the oldest — matches the browser behavior of many overlapping beeps
	p.stream = make_tone(freq, type, dur, vol)
	p.play()

var pending_tones := []   # {at, freq, type, dur, vol} — real-time queue (JS setTimeout equivalent)

func schedule_tone(delay: float, freq: float, dur: float, type: String, vol: float) -> void:
	pending_tones.append({"at": delay, "freq": freq, "type": type, "dur": dur, "vol": vol})

# ---------------- Utilities ----------------
func rr() -> float: return override_rand if override_rand >= 0.0 else randf()

func mulberry32(seedval: int) -> RNG32:
	var r := RNG32.new()
	r.setup(seedval)
	return r

func bw(b) -> float: return float(b.get("w", CELL_W))   # per-block width — only the boss is bigger than a cell
func bh(b) -> float: return float(b.get("h", CELL_H))

func ball_speed() -> float:
	var s: float = BALL_BASE_SPEED + float(state.level - 1) * 20.0
	if state.active.get("SLOW", 0.0) > 0.0: s *= 0.65
	if state.active.get("FAST", 0.0) > 0.0: s *= 1.5
	return min(s, BALL_MAX_SPEED)

func new_ball(x: float, y: float, angle_deg: float) -> Dictionary:
	var a: float = angle_deg * PI / 180.0
	var s: float = ball_speed()
	return {"x": x, "y": y, "vx": cos(a) * s, "vy": sin(a) * s, "stuck": false}

func reset_ball_on_paddle() -> void:
	state.balls = [new_ball(paddle.x + state.paddleW / 2.0, paddle.y - BALL_R, -90)]
	state.balls[0].stuck = true
	sticky_ball = null

# ---------------- Level generation ----------------
func generate_level(n: int) -> Array:
	var rng := mulberry32(n * 7919 + 13)
	var rows: int = int(min(4 + floor(float(n) / 2.0), 9))
	var hard_chance: float = min(0.10 + n * 0.045, 0.4)
	var steel_chance: float = min(0.015 + n * 0.005, 0.05) if n >= 3 else 0.0   # rare, never the old 12 % wall-of-metal
	var steel_cap: int = mini(3 + int(n / 3.0), 6)                              # hard ceiling per level
	var explode_chance: float = 0.06 if n >= 2 else 0.0
	var patterns := ["rows", "checker", "pyramid", "diamond", "columns", "clusters", "zigzag", "arch", "castle", "pillars", "crossfire", "sieve"]
	var pattern: String = patterns[int(floor(rng.next() * patterns.size()))]

	var cells := []
	var steel_count := 0
	var steel_cols := {}   # column -> last row that got steel: no vertical stacks, so no steel walls
	var pick_type = func(c: int, r: int) -> String:
		var p: float = rng.next()
		if p < explode_chance: return "explode"
		var steel_ok: bool = n >= 3 and steel_count < steel_cap and r < rows - 1 and not steel_cols.has(c)
		if steel_ok and p < explode_chance + steel_chance:
			steel_count += 1
			steel_cols[c] = r
			return "steel"
		if p < explode_chance + steel_chance + hard_chance: return "tough" if rng.next() < 0.6 else "tough3"
		return "normal"

	var in_shape = func(c: int, r: int) -> bool:
		var mid: float = (GRID_COLS - 1) / 2.0
		match pattern:
			"rows": return true
			"checker": return (c + r) % 2 == 0
			"pyramid": return absf(c - mid) <= (mid + 1.0) * (r + 1.0) / rows
			"diamond": return absf(c - mid) + absf(r - rows / 2.0) * (GRID_COLS / rows) <= GRID_COLS * 0.62
			"columns": return (r + c) % 3 != 0
			"clusters": return rng.next() < 0.62
			"zigzag": return int(floor(c / 2.0) + r) % 4 < 2                     # fat diagonal light/dark bands
			"arch": return absf(c - mid) >= mid * (1.0 - (r + 1.0) / float(rows)) * 1.2 - 0.5   # portal arch: converging side walls, open throat
			"castle": return r >= rows - 2 or c <= 1 or c >= GRID_COLS - 2       # battlement: solid keep base + corner towers
			"pillars": return c % 3 == 0 or r == 0                               # colonnade: full columns 0/3/6/9 under a lintel row
			"crossfire": return absf((c - mid) - (r - (rows - 1) / 2.0) * 2.2) <= 1.2 or absf((c - mid) + (r - (rows - 1) / 2.0) * 2.2) <= 1.2   # big X across the field
			"sieve": return (c * 7 + r * 5) % 11 > 2                             # punched field, deterministic holes
		return true

	for r in range(rows):
		for c in range(GRID_COLS):
			if in_shape.call(c, r):
				if c >= 0 and c < GRID_COLS and r >= 0 and r < rows:
					var tn: String = pick_type.call(c, r)
					if n >= 2 and tn == "normal" and (c + 2 * r) % 11 == 3:
						tn = "gold"   # fixed gold veins — purely positional, never touches the seeded rng, so the layout anchors stay stable
					cells.append({"c": c, "r": r, "t": tn})
	if n % 4 == 0 and cells.size() > 0:   # every fourth level gets a mini-boss at the most central cell
		var mid: float = (GRID_COLS - 1) / 2.0
		var boss_cell = null
		var best_d: float = 1e9
		for x in cells:
			var d: float = absf(float(x.c) - mid) + absf(float(x.r) - 1.0) * 0.35
			if d < best_d:
				best_d = d
				boss_cell = x
		if boss_cell != null:
			boss_cell.t = "boss"
			for x in cells.duplicate():   # the boss is two rows tall — free the cell underneath it
				if x != boss_cell and int(x.c) == int(boss_cell.c) and int(x.r) == int(boss_cell.r) + 1:
					cells.erase(x)
	var has_clearable := false
	for x in cells:
		if x.t != "steel": has_clearable = true
	if cells.size() > 0 and not has_clearable:
		for x in cells: x.t = "normal"
	return cells

func build_level() -> void:
	blocks_data.clear()
	auto_background()   # the single choke point every level transition shares (boot, restart, level-up) — the paper rotates here for all of them
	for cell in generate_level(state.level):
		var t = BLOCK_TYPES[cell.t]
		var pal: Array = t.palette
		var col: String = pal[(cell.r + cell.c) % pal.size()]
		var boss: bool = String(cell.t) == "boss"
		blocks_data.append({
			"c": cell.c, "r": cell.r, "t": cell.t, "hp": t.hp, "color": col,
			"x": (W - GRID_COLS * (CELL_W + GAP) + GAP) / 2.0 + cell.c * (CELL_W + GAP),
			"y": FIELD_TOP + cell.r * (CELL_H + GAP),
			"w": CELL_W,   # same width, twice the height — unmistakably the big one
			"h": CELL_H * 2.0 + GAP if boss else CELL_H,
		})
	state.drops = []
	state.lasers = []
	state.active = {}
	state.paddleW = PADDLE_BASE_W
	state.combo = 0
	state.comboBest = 0
	state.trail = []
	state.popups = []
	state.fever = 0.0
	state.pressTimer = PRESS_INTERVAL
	state.pressWarned = false
	var rush_level: bool = int(state.level) > 0 and int(state.level) % 3 == 0
	state.rush = rush_level
	state.rushTimer = RUSH_TIME if rush_level else 0.0
	state.rushWaveTimer = RUSH_TIME / float(RUSH_WAVES) if rush_level else 0.0
	state.rushWavesLeft = RUSH_WAVES if rush_level else 0
	reset_ball_on_paddle()
	sync_music_energy()   # a rush level takes the high-energy theme with it

# ---------------- Core actions ----------------
func launch_ball(ball) -> void:
	if ball == null or not ball.stuck: return
	var a: float = (-60.0 - rr() * 60.0) * PI / 180.0
	var s: float = ball_speed()
	ball.vx = cos(a) * s
	ball.vy = sin(a) * s
	ball.stuck = false
	paddle["squash"] = maxf(float(paddle.get("squash", 0.0)), 0.7)   # the paddle springs as it fires the ball off
	if sticky_ball == ball: sticky_ball = null

func launch_all() -> void:
	for b in state.balls:
		if b.stuck: launch_ball(b)

func fire_laser() -> void:
	if not state.active.has("LASER") or (state.balls.size() > 0 and state.balls[0].stuck):
		launch_all()
		return
	state.lasers.append({"x": paddle.x + 12.0, "y": paddle.y, "ttl": 1.2})
	state.lasers.append({"x": paddle.x + state.paddleW - 12.0, "y": paddle.y, "ttl": 1.2})
	play_tone(180, 0.09, "sawtooth", 0.06)

func hit_block(b, from_explosion: bool = false) -> bool:
	var t = BLOCK_TYPES[b.t]
	if t.indestructible and not from_explosion:
		state.score += int(t.score * score_mult())
		play_tone(300, 0.05, "square", 0.04)
		return false
	b.hp -= 1
	state.score += int(t.score * score_mult())
	if b.hp > 0:
		play_tone(520, 0.05, "square", 0.05)
		if String(b.t) == "boss" and int(b.hp) == int(t.hp) / 2:   # phase two: the press cracks and sheds a drop shower
			state.shake = maxf(float(state.shake), 9.0)
			state.flash = maxf(float(state.flash), 0.6)
			boom(b.x + bw(b) / 2.0, b.y + bh(b) / 2.0, 2, Color("#d8c24a"))
			flash_message("THE BOSS CRACKS!", 1.2, true)
			for _i in 3: spawn_drop(b.x + bw(b) / 2.0, b.y + bh(b) / 2.0)
			schedule_tone(0.0, 110.0, 0.18, "sawtooth", 0.07)
			schedule_tone(0.12, 880.0, 0.14, "square", 0.06)
		return false
	destroy_block(b, -1)
	return true

func lava_break(b) -> void:   # molten ball: any block — even indestructible steel — goes down in one shot
	var t = BLOCK_TYPES[b.t]
	state.score += int(t.score * score_mult())
	play_tone(196, 0.12, "sawtooth", 0.05)   # low molten rumble under destroy_block's pop
	destroy_block(b, -1)

# ---------------- Excitement: FEVER mode + TNT domino waves ----------------
func fever_mult() -> float:
	return 2.0 if float(state.fever) > 0.0 else 1.0

func score_mult() -> float:   # FEVER and a gold rush stack — a rushing, burning run pays ×6
	var m: float = fever_mult()
	if bool(state.get("rush", false)): m *= RUSH_MULT
	return m

func near_miss(x: float, y: float, label: String = "CLOSE!") -> void:   # a nerve-wracking save pays a small, noisy bonus
	state.score += int(NEAR_MISS_BONUS * score_mult())
	popup(x, y, label + " +" + str(NEAR_MISS_BONUS), Color("#a05a1e"))
	state.flash = maxf(float(state.flash), 0.25)
	play_tone(740, 0.06, "square", 0.05)
	schedule_tone(0.06, 988.0, 0.09, "square", 0.04)

func press_descend() -> void:   # the press comes down one row; if it reaches the paddle the run pays a life and the level resets
	state.pressTimer = PRESS_INTERVAL
	state.pressWarned = false
	state.shake = maxf(float(state.shake), 8.0)
	state.flash = maxf(float(state.flash), 0.45)
	boom(W / 2.0, FIELD_TOP + 30.0, 2, Color("#8a5a1d"))
	schedule_tone(0.0, 90.0, 0.20, "sawtooth", 0.07)
	var crushed := false
	for blk in blocks_data:
		blk.r = int(blk.get("r", 0)) + 1
		blk.y = float(blk.y) + CELL_H + GAP
		if float(blk.y) + bh(blk) >= paddle.y - 8.0: crushed = true
	if crushed:
		flash_message("CRUSHED!", 1.4, true)
		lose_ball()
		if not bool(state.over): build_level()

func rush_spawn_wave() -> void:   # gold rush: print a handful of fresh (mostly gold) blocks into empty cells
	var occupied := {}
	for b in blocks_data: occupied[str(b.c) + "," + str(b.r)] = true
	var candidates := []
	var rows: int = int(min(4 + floor(float(state.level) / 2.0), 9))
	for r in range(rows):
		for c in range(GRID_COLS):
			if not occupied.has(str(c) + "," + str(r)): candidates.append([c, r])
	var spawned := 0
	while spawned < 6 and candidates.size() > 0:
		var idx: int = int(rr() * candidates.size()) % candidates.size()
		var cell: Array = candidates[idx]
		candidates.remove_at(idx)
		var tn: String = "gold" if rr() < 0.5 else "normal"
		var t = BLOCK_TYPES[tn]
		blocks_data.append({
			"c": cell[0], "r": cell[1], "t": tn, "hp": t.hp, "color": t.palette[0],
			"x": (W - GRID_COLS * (CELL_W + GAP) + GAP) / 2.0 + float(cell[0]) * (CELL_W + GAP),
			"y": FIELD_TOP + float(cell[1]) * (CELL_H + GAP),
		})
		spawned += 1
	boom(paddle.x + state.paddleW / 2.0, FIELD_TOP + 46.0, 1, Color("#c9971f"))
	schedule_tone(0.0, 587.0, 0.10, "square", 0.05)

func sync_music_energy() -> void:   # FEVER / gold rush borrow the fastest theme, then hand the shuffle back
	if String(settings.get("track", "auto")) != "auto" or music_playlist.is_empty(): return
	var high: bool = float(state.fever) > 0.0 or bool(state.get("rush", false))
	if high == music_adaptive: return
	music_adaptive = high
	if high: play_music_index(_energy_track_idx(), true)
	else: play_music_index(music_base_idx, true)

func brick_near(x: float, y: float, reach: float = 26.0) -> bool:   # did the ball skim a brick on this wall bounce?
	for blk in blocks_data:
		var nx: float = clampf(x, blk.x, blk.x + bw(blk))
		var ny: float = clampf(y, blk.y, blk.y + bh(blk))
		var dx: float = x - nx
		var dy: float = y - ny
		if dx * dx + dy * dy <= reach * reach:
			return true
	return false

func start_fever() -> void:
	state.fever = FEVER_TIME
	flash_message("FEVER!", 1.3)
	state.shake = maxf(float(state.shake), 5.0)
	state.flash = maxf(float(state.flash), 0.7)
	boom(paddle.x + state.paddleW / 2.0, paddle.y - 30.0, 1, Color("#ff9800"))
	play_tone(523.0, 0.09, "square", 0.06)
	schedule_tone(0.11, 659.0, 0.09, "square", 0.06)
	schedule_tone(0.22, 784.0, 0.18, "square", 0.06)
	sync_music_energy()   # the fastest theme rides the streak

func boom(x: float, y: float, depth: int, col: Color = Color("#d8c24a")) -> void:   # expanding shockwave ring — pure visual, zero rr
	state.booms.append({"x": x, "y": y, "t": 0.0, "ttl": 0.44 if depth <= 1 else 0.34, "color": col, "r0": 16.0 + 10.0 * mini(depth, 4)})
	if state.booms.size() > 26:
		state.booms.pop_front()

func do_explode(b, depth: int) -> void:   # a bomb dies: shockwave + 3×3 kill-wave; survivor bombs get fuses so the chain ROLLS like dominoes
	var cx: float = b.x + bw(b) / 2.0
	var cy: float = b.y + bh(b) / 2.0
	boom(cx, cy, depth, Color("#c9971f") if depth == 1 else Color("#ffb300"))
	state.shake = maxf(float(state.shake), 6.0 + float(depth))
	if depth >= 2:
		schedule_tone(0.0, 120.0 + 30.0 * float(depth), 0.12, "sawtooth", 0.06)   # the wave whooshes deeper
	var wave_bonus: int = int(10 * mini(depth, 5) * score_mult())
	state.score += wave_bonus
	if depth == 1:
		popup(cx, b.y - 10.0, "BOOM! +" + str(wave_bonus), Color("#d8c24a"))
	for o in blocks_data.duplicate():   # snapshot: JS iterated a copy
		if o == b:
			continue
		if absf(o.c - b.c) <= 1 and absf(o.r - b.r) <= 1:
			if String(o.t) == "explode" and o.get("fuse") == null:
				o["fuse"] = CHAIN_FUSE          # lit neighbour — pops on the next beat, domino style
				o["fuse_depth"] = depth + 1
			else:
				state.score += int(BLOCK_TYPES[o.t].score * score_mult())   # chain-kills pay their score too — explosions are generous
				o.hp = 1
				destroy_block(o, blocks_data.find(o))

func check_clear() -> void:   # level clear once all destructible blocks are gone — safe to call repeatedly, only the death-blow frame passes
	for x in blocks_data:
		if not BLOCK_TYPES[x.t].indestructible:
			return
	level_clear()

func destroy_block(b, fromExplosion: int = -1, _top_level: bool = true) -> void:
	blocks_data.erase(b)
	spark(b.x + bw(b) / 2.0, b.y + bh(b) / 2.0, b.color)
	if fromExplosion >= 0:
		play_tone(140, 0.15, "sawtooth", 0.07)
	else:
		play_tone(660, 0.06, "square", 0.07)
	if b.t == "gold":
		schedule_tone(0.07, 1175.0, 0.1, "square", 0.05)   # coin chime over the pop
	if String(b.t) == "boss":   # the big finish: twice the rumble, a gold ring and a shout
		state.shake = maxf(float(state.shake), 11.0)
		state.flash = maxf(float(state.flash), 0.8)
		boom(b.x + bw(b) / 2.0, b.y + bh(b) / 2.0, 3, Color("#d8c24a"))
		flash_message("BOSS DOWN!", 1.4, true)   # level_clear() below folds this into the LEVEL N card instead of erasing it
		schedule_tone(0.0, 1318.0, 0.16, "square", 0.06)
		schedule_tone(0.14, 1760.0, 0.22, "square", 0.06)
	if BLOCK_TYPES[b.t].label == "*" and fromExplosion < 0:   # bomb: shockwave + domino wave around it (do_explode owns the blast now)
		do_explode(b, 1)
	if fromExplosion < 0 and (b.t == "gold" or rr() < DROP_CHANCE):   # gold drops no matter what — the roll is short-circuited away
		spawn_drop(b.x + bw(b) / 2.0, b.y + bh(b) / 2.0)
	if fromExplosion < 0:
		state.combo += 1
		state.comboBest = int(max(state.comboBest, state.combo))
		popup(b.x + bw(b) / 2.0, b.y + 2.0, "+" + str(BLOCK_TYPES[b.t].score), Color(b.color))
		if state.combo % COMBO_STEP == 0:
			var tier: int = mini(int(state.combo / COMBO_STEP), 5)
			var bonus: int = COMBO_BONUS * tier
			state.score += bonus
			popup(b.x + bw(b) / 2.0, b.y + bh(b) + 12.0, "COMBO ×" + str(state.combo) + "  +" + str(bonus), Color("#8f5f1f"))
			schedule_tone(0.0, 660.0 + 80.0 * float(tier), 0.12, "square", 0.05)
		if float(state.fever) > 0.0:
			state.fever = FEVER_TIME   # a kill during FEVER re-lights the clock — the streak keeps burning
		elif int(state.combo) >= FEVER_TRIGGER:
			start_fever()
	check_clear()   # every top-level death (and every blast wave, which lands inside this call) checks the field

func spawn_drop(x: float, y: float) -> void:
	var pool := []
	for k in POWERUPS.keys():
		if POWERUPS[k].good or state.level > 1:
			pool.append(k)
	var key: String = pool[int(rr() * pool.size())]
	state.drops.append({"key": key, "x": x, "y": y, "vy": DROP_SPEED})

func apply_powerup(key: String) -> void:
	var p = POWERUPS[key]
	var overcharged: bool = float(p.duration) > 0.0 and float(state.active.get(key, 0.0)) > 0.0
	var carry: float = float(state.active.get(key, 0.0)) if overcharged else 0.0
	if overcharged:   # a second copy of a live powerup extends it and pays a bonus — chasing drops now has a point
		var obonus := 100
		state.score += int(obonus * score_mult())
		popup(paddle.x + state.paddleW / 2.0, paddle.y - 44.0, "OVERCHARGE +" + str(obonus), Color("#c9971f"))
		flash_message("OVERCHARGE " + p.name + "!", 1.2, true)
		state.shake = maxf(float(state.shake), 3.0)
		state.flash = maxf(float(state.flash), 0.55)
		play_tone(1046.0, 0.10, "square", 0.06)
		schedule_tone(0.08, 1318.0, 0.14, "square", 0.06)
	else:
		if p.good: play_tone(880, 0.12, "sine", 0.08)
		else: play_tone(220, 0.12, "square", 0.08)
		flash_message(p.name + "!", 1.2, true)
		state.flash = 0.45
	if key == "SHIELD":
		play_tone(520, 0.25, "sine", 0.05)   # soft energy-hum layer for the floor barrier
	if key == "MULTI":
		var src = state.balls[0]
		for _i in 2:
			var b: Dictionary = new_ball(src.x, src.y, -60.0 - rr() * 60.0)
			state.balls.append(b)
	elif key == "LIFE":
		state.lives = int(min(state.lives + 1, 9))
	elif key == "EXPAND":
		state.paddleW = 160.0
		state.active["EXPAND"] = 15.0 + carry
		state.active.erase("SHRINK")
	elif key == "SHRINK":
		state.paddleW = 80.0
		state.active["SHRINK"] = 10.0 + carry
		state.active.erase("EXPAND")
	elif key != "":
		state.active[key] = float(p.duration) + carry
		if key != "SLOW": state.active.erase("SLOW")
		if key != "FAST": state.active.erase("FAST")
	normalize_speeds()

func normalize_speeds() -> void:
	for b in state.balls:
		var m: float = sqrt(b.vx * b.vx + b.vy * b.vy)
		if m == 0.0: m = 1.0
		var s: float = ball_speed()
		b.vx = b.vx / m * s
		b.vy = b.vy / m * s

func flash_message(text: String, secs: float, plain: bool = false) -> void:
	state.message = text
	state.msgTimer = secs
	state.msgPlain = plain

func popup(x: float, y: float, text: String, col: Color) -> void:   # floating rising text — score gains, combo payouts
	state.popups.append({"x": x, "y": y, "text": text, "ttl": POPUP_LIFE, "color": col})
	if state.popups.size() > MAX_POPUPS:
		state.popups.pop_front()

func level_clear() -> void:
	play_tone(988, 0.1, "square", 0.05)
	schedule_tone(0.12, 1319.0, 0.15, "square", 0.05)
	state.level += 1
	state.score += 100
	if state.level % 3 == 0: state.lives = int(min(state.lives + 1, 9))
	var boss_shout: bool = String(state.message).contains("BOSS DOWN")
	flash_message(("BOSS DOWN!  ·  " if boss_shout else "") + "LEVEL " + str(state.level), 2.0, true)
	build_level()
	# the celebration pass — fanfare top note, white blink, paddle squash, a shockwave ring off the paddle and a big floating payout
	schedule_tone(0.26, 1760.0, 0.2, "square", 0.05)
	state.shake = maxf(float(state.shake), 9.0)
	state.flash = 1.0
	paddle["squash"] = 1.0
	boom(paddle.x + state.paddleW / 2.0, paddle.y - 22.0, 1, Color(0.20, 0.18, 0.15, 1))
	popup(paddle.x + state.paddleW / 2.0, paddle.y - 60.0, "LEVEL CLEAR +100", Color("#c9971f"))

func lose_ball() -> void:
	state.lives -= 1
	play_tone(120, 0.3, "sawtooth", 0.08)
	state.shake = 8.0
	if state.lives <= 0:
		game_over()
		return
	state.paddleW = PADDLE_BASE_W
	state.active = {}
	state.combo = 0
	state.fever = 0.0
	reset_ball_on_paddle()

func game_over() -> void:
	state.over = true
	state.high = int(max(state.high, state.score))
	if int(state.score) > 0:
		add_leaderboard_entry(int(state.score), int(state.level))
	save_high()
	_refresh_leaderboard_rows()
	flash_message("GAME OVER — tap the screen to restart" if _is_touch_device() else "GAME OVER — click or press R", 999.0)

# ---------------- Leaderboard (locally stored best runs, shown on the main menu card) ----------------
const BOARD_MAX := 8   # best runs kept on disk — the submenu card lists them all
var leaderboard := []   # Array[Dictionary]: {"score": int, "level": int, "when": "dd/mm hh:mm"}
# Scores no longer live in a plain-text .cfg: a signed, obfuscated binary blob deters casual
# text-editor tampering. (A client-side game can never be truly cheat-proof — the key ships
# with it — but editing this file by hand now fails the integrity check and zeroes the board.)
const SCORE_FILE := "user://brick_press_scores.bin"
const SETTINGS_FILE := "user://brick_press_settings.cfg"
const SCORE_MAGIC := "BPSC"
const SCORE_VERSION := 1
const SCORE_KEY := "brick-press|score|2026|7f3a9c2e4d8b6a10|0x5c1e"
var _score_cache = null   # parsed score payload, or null until first read

func _score_digest(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(SCORE_KEY.to_utf8_buffer())
	ctx.update(data)
	return ctx.finish()

func _score_xor(data: PackedByteArray) -> PackedByteArray:   # symmetric — encode and decode are the same pass
	var key := SCORE_KEY.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(data.size())
	for i in data.size():
		out[i] = (data[i] ^ key[i % key.size()] ^ ((i * 37 + 11) & 0xFF)) & 0xFF
	return out

func load_score_data() -> Dictionary:
	if _score_cache != null: return _score_cache
	var out := {"high": 0, "board": []}
	_score_cache = out
	if not FileAccess.file_exists(SCORE_FILE): return out
	var f := FileAccess.open(SCORE_FILE, FileAccess.READ)
	if f == null: return out
	if f.get_buffer(4).get_string_from_ascii() != SCORE_MAGIC: return out
	var ver: int = f.get_32()
	var n: int = f.get_32()
	if ver != SCORE_VERSION or n < 2 or n > 1048576: return out
	var enc := f.get_buffer(n)
	var sig := f.get_buffer(32)
	if sig.size() != 32 or sig != _score_digest(enc):
		push_warning("brick_press_scores.bin failed its integrity check — high score and board reset")
		return out
	var parsed = JSON.parse_string(_score_xor(enc).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY: return out
	out.high = maxi(0, int(parsed.get("high", 0)))
	var pb = parsed.get("board", [])
	if typeof(pb) == TYPE_ARRAY:
		for e in pb:
			if typeof(e) != TYPE_DICTIONARY: continue
			var sc: int = int(e.get("score", 0))
			if sc <= 0: continue
			out.board.append({"score": sc, "level": maxi(1, int(e.get("level", 1))), "when": String(e.get("when", ""))})
		out.board.sort_custom(func(a, b): return int(a.score) > int(b.score))
		if out.board.size() > BOARD_MAX: out.board.resize(BOARD_MAX)
	_score_cache = out
	return out

func load_leaderboard() -> void:
	leaderboard = []
	for e in load_score_data().board:
		leaderboard.append({"score": int(e.score), "level": int(e.level), "when": String(e.when)})

func add_leaderboard_entry(sc: int, lvl: int) -> void:
	if sc <= 0:
		return
	var d := Time.get_datetime_dict_from_system()
	leaderboard.append({"score": sc, "level": lvl, "when": "%02d/%02d %02d:%02d" % [d.day, d.month, d.hour, d.minute]})
	leaderboard.sort_custom(func(a, b): return int(a.score) > int(b.score))
	if leaderboard.size() > BOARD_MAX:
		leaderboard.resize(BOARD_MAX)

func quit_to_menu() -> void:   # "Quit to menu" from the paused sheet — an abandoned run still makes the leaderboard, then everything resets behind the title scene
	if not bool(state.over) and int(state.score) > 0:
		add_leaderboard_entry(int(state.score), int(state.level))
	state.high = int(max(state.high, state.score))
	save_high()
	restart()
	screen = "menu"
	menu_open = false
	menu_panel.visible = false
	main_menu_panel.visible = true
	_refresh_dim()
	play_button.grab_focus()

func _on_window_close() -> void:   # the X button / Alt-F4 must never lose a run: the pending score is booked before the app dies — and the close banks everything, every time
	if screen == "game" and not bool(state.over) and int(state.score) > 0:
		add_leaderboard_entry(int(state.score), int(state.level))
		state.high = int(max(state.high, state.score))
	save_high()
	save_settings()

func quit_game() -> void:   # "Quit game" — same last write, then straight back to the desktop
	_on_window_close()
	get_tree().quit()

# High score + board travel together in one signed binary file — they can never drift apart.
func load_high() -> int:
	return int(load_score_data().high)

func save_high() -> void:
	var board := []
	for e in leaderboard:
		board.append({"score": int(e.score), "level": int(e.level), "when": String(e.when)})
	var payload := {"high": int(state.high), "board": board}
	var enc := _score_xor(JSON.new().stringify(payload).to_utf8_buffer())
	var f := FileAccess.open(SCORE_FILE, FileAccess.WRITE)
	if f == null:
		push_warning("could not write " + SCORE_FILE)
		return
	f.store_buffer(SCORE_MAGIC.to_utf8_buffer())
	f.store_32(SCORE_VERSION)
	f.store_32(enc.size())
	f.store_buffer(enc)
	f.store_buffer(_score_digest(enc))
	f.close()
	_score_cache = payload   # keep the in-memory mirror in sync with disk

func high_score_saved() -> int:   # test hook — force a fresh disk read so it proves persistence
	_score_cache = null
	return int(load_score_data().high)

# ---------------- Settings (persisted via user:// ConfigFile — mirrors the high-score pair's style) ----------------
var settings := {"sfx_vol": 1.0, "music_vol": 0.5, "fullscreen": false, "size": "1280x720", "bg": "auto", "track": "auto"}   # linear 0.0-1.0 for the two volume keys; bg/track = "auto" or a pinned file name
var menu_open := false   # settings menu counts as a full freeze (the harness reads this member directly)
var menu_return := "game"   # "menu" | "game" — where the Back button / Esc lands when the settings overlay closes
var menu_panel: PanelContainer
var res_option: OptionButton
var fs_check: CheckButton
var sfx_slider: HSlider
var music_slider: HSlider
var bg_option: OptionButton
var bg_cycle: Button   # the phone's stand-in for bg_option — Android hangs when an OptionButton opens its popup window
var music_option: OptionButton   # the music-track picker ("auto — shuffle" plus one row per scanned file)
var music_cycle: Button          # its tap-to-cycle stand-in on phones
var back_button: Button
var screen := "menu"   # "menu" = main menu shown (game frozen behind it) | "game" = playing / paused / game over
var main_menu_panel: PanelContainer
var main_menu_dim: ColorRect   # full-window dark overlay behind the main menu (eats clicks down to the game)
var play_button: Button
var settings_button: Button
var quit_button: Button
var leaderboard_button: Button   # the main menu card's way into the leaderboard submenu
var leaderboard_panel: PanelContainer   # a Settings-sibling modal card — best local runs, rebuilt every time it opens
var leaderboard_rows: VBoxContainer
var lb_close_button: Button
var leaderboard_open := false
var sheet_title: Label   # the settings sheet doubles as the pause menu — these three labels retitle it per context
var sheet_status: Label
var sheet_hints: Label
var pause_row: HBoxContainer   # Resume / Quit to menu / Quit game — shown only when the sheet opens over a live run
var resume_button: Button
var quit_menu_button: Button
var quit_game_button: Button
var _res_items := ["1280x720 (720p)", "1920x1080 (1080p)", "2560x1440 (1440p)"]   # OptionButton display labels
var _res_values := ["1280x720", "1920x1080", "2560x1440"]   # the bare WxH the labels stand for — persisted as settings["size"]

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://brick_press_settings.cfg") == OK:
		settings.sfx_vol = float(cf.get_value("settings", "sfx_vol", 1.0))
		settings.music_vol = float(cf.get_value("settings", "music_vol", 0.5))
		settings.fullscreen = bool(cf.get_value("settings", "fullscreen", false))
		var sz := str(cf.get_value("settings", "size", "1280x720"))
		if not _res_values.has(sz): sz = "1280x720"   # migrate sizes saved by older builds (960x640, 1280x800, ...)
		settings["size"] = sz   # bracket form: settings.size would collide with Dictionary.size()
		settings["bg"] = str(cf.get_value("settings", "bg", "auto"))   # saves written before the paper rotation shipped simply default to auto
		settings["track"] = str(cf.get_value("settings", "track", "auto"))   # older saves simply shuffle

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("settings", "sfx_vol", settings.sfx_vol)
	cf.set_value("settings", "music_vol", settings.music_vol)
	cf.set_value("settings", "fullscreen", settings.fullscreen)
	cf.set_value("settings", "size", settings["size"])
	cf.set_value("settings", "bg", settings["bg"])
	cf.set_value("settings", "track", settings["track"])
	cf.save("user://brick_press_settings.cfg")

func set_setting(key: String, value: Variant) -> void:   # test hook + menu path — apply immediately, persist always
	var k := key
	if k == "sfx": k = "sfx_vol"
	elif k == "music": k = "music_vol"
	settings[k] = value
	if k == "track": apply_track_setting()
	apply_audio_volumes()
	save_settings()

func apply_audio_volumes() -> void:
	for pair in [["sfx_vol", "SFX"], ["music_vol", "Music"]]:
		var idx := AudioServer.get_bus_index(pair[1])   # buses land at indices 1/2 — never hardcode, resolve by name
		if idx < 0: continue
		var v: float = float(settings[pair[0]])
		AudioServer.set_bus_volume_db(idx, linear_to_db(v))   # settings are linear 0-1 -> bus dB
		AudioServer.set_bus_mute(idx, v <= 0.0)

func apply_settings_at_boot() -> void:
	apply_audio_volumes()
	if bool(settings.fullscreen):
		get_window().mode = Window.MODE_FULLSCREEN
	else:
		_resize_window(str(settings["size"]))

func _resize_window(size_str: String) -> void:
	if _is_mobile_os(): return   # on a phone the window IS the screen — asking Android for 1280x720 just wedges the frame loop, it never resizes anything
	var parts := size_str.split("x")
	if parts.size() != 2: return
	get_window().size = Vector2i(int(parts[0]), int(parts[1]))
	get_window().move_to_center()

func apply_display_stretch() -> void:   # the 960x640 design space IS scaled to the window — "expand" grows the visible world instead of letterboxing, so the game fills every resolution
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(int(W), int(H))   # 4.7 types this property as Vector2i — the design space 960x640 scales to whatever the window is

func _world_rect() -> Rect2:   # the whole visible area in canvas coordinates — bigger than 960x640 whenever the window is wider/taller than the base aspect
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var a := inv * Vector2.ZERO
	var b := inv * get_viewport_rect().size
	return Rect2(a.min(b), (b - a).abs())

func toggle_menu() -> void:   # THE menu — Esc only: pauses behind the sheet in game, opens plain Settings from the main menu
	close_leaderboard()   # the two submenus are mutually exclusive — one modal at a time
	menu_open = not menu_open
	if menu_open:
		menu_return = screen
		refresh_content()   # music/backgrounds dropped since boot show up without a restart (once imported)
		menu_panel.move_to_front()   # the settings overlay stacks above the main menu
		_refresh_menu_sheet()
	menu_panel.visible = menu_open
	if screen == "game":
		state.paused = menu_open and not bool(state.over)   # the sheet IS the pause — one freeze switch, no parallel pause-key system
	_refresh_dim()
	_center_menu_cards()   # the sheet changes size between its paused (tall) and settings (short) shapes — re-pin the card
	if not menu_open:
		if screen == "menu":
			play_button.grab_focus()   # back on the main menu — Space/Enter on Play works again
		else:
			grab_focus()   # root has focus_mode ALL — gameplay keys work again

func _refresh_menu_sheet() -> void:   # one sheet, two faces: PAUSED over a live run (run info + hints + quit row) vs plain Settings from the menu
	var in_game := screen == "game"
	sheet_title.text = "Paused" if in_game else "Settings"
	sheet_status.text = ("LEVEL " + str(state.level) + "  ·  SCORE " + str(state.score) + "  ·  LIVES " + "●".repeat(maxi(int(state.lives), 0))) if in_game else "everything here saves itself"
	sheet_status.add_theme_font_size_override("font_size", 14 if in_game else 12)
	sheet_hints.visible = in_game
	pause_row.visible = in_game
	back_button.visible = not in_game
	back_button.text = "Back to menu"   # the menu-open face only ever shows this text — the paused face uses the quit row instead

func refresh_content() -> void:
	load_backgrounds()   # re-scan + reload the PNG slots (cached loads are cheap)
	refresh_bg_option()
	rescan_music()

# ---------------- Main menu screen ----------------
func build_main_menu() -> void:
	main_menu_dim = ColorRect.new()   # dark veil under the cards; huge fixed reach covers the whole world in any window shape
	main_menu_dim.color = COLOR_SLOTS["dark_overlay"]
	main_menu_dim.set_anchors_preset(Control.PRESET_CENTER)
	main_menu_dim.offset_left = -6000.0
	main_menu_dim.offset_right = 6000.0
	main_menu_dim.offset_top = -6000.0
	main_menu_dim.offset_bottom = 6000.0
	main_menu_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(main_menu_dim)
	main_menu_panel = PanelContainer.new()
	main_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	main_menu_panel.add_theme_stylebox_override("panel", _card_style())
	main_menu_panel.custom_minimum_size = Vector2(440, 520)   # four big buttons + title + footer — no leaderboard rows inside anymore, that's a submenu of its own
	add_child(main_menu_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	main_menu_panel.add_child(box)
	var title := Label.new()
	title.text = "BRICK PRESS"
	title.add_theme_font_override("font", load("res://fonts/ArchivoBlack-Regular.ttf"))
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.20, 0.18, 0.15, 0.97))
	title.add_theme_color_override("font_shadow_color", Color("#7a5c49", 0.35))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Drag the left half to move · Tap the right half to launch" if _is_touch_device() else "A · D / arrows move the paddle — click or space launches"
	sub.add_theme_color_override("font_color", Color("#6f6757"))
	sub.add_theme_font_size_override("font_size", 13)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # wrap inside the card instead of widening it
	sub.custom_minimum_size = Vector2(340, 0)
	box.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	box.add_child(spacer)
	play_button = _big_button("Play")
	_style_button(play_button, true)   # Play is the action button — it wears the accent blue
	settings_button = _big_button("Settings")
	leaderboard_button = _big_button("Leaderboards")
	quit_button = _big_button("Quit")
	box.add_child(play_button)
	box.add_child(settings_button)
	box.add_child(leaderboard_button)
	box.add_child(quit_button)
	var footer := Label.new()
	footer.text = "Pause button top-left · The left half moves the paddle" if _is_touch_device() else "Esc opens settings · F toggles fullscreen"
	footer.add_theme_color_override("font_color", Color("#5b5347"))
	footer.add_theme_font_size_override("font_size", 12)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(footer)
	play_button.pressed.connect(play)
	settings_button.pressed.connect(_on_menu_settings_pressed)
	leaderboard_button.pressed.connect(open_leaderboard)
	quit_button.pressed.connect(quit_game)
	play_button.grab_focus()   # Space/Enter on the focused button works straight away
	_refresh_dim()   # veil hidden over the title screen (it only dims gameplay behind the settings overlay)
	_center_menu_cards()

func build_leaderboard_panel() -> void:   # the submenu pattern, same trick as Settings: one card modal over the title scene, Esc/Close dismisses
	leaderboard_panel = PanelContainer.new()
	leaderboard_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	leaderboard_panel.add_theme_stylebox_override("panel", _card_style())
	leaderboard_panel.custom_minimum_size = Vector2(480, 450)
	add_child(leaderboard_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	leaderboard_panel.add_child(box)
	var head := Label.new()
	head.text = "Leaderboards"
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", Color("#2b2620", 0.95))
	head.add_theme_color_override("font_shadow_color", Color("#7a5c49", 0.35))
	head.add_theme_constant_override("shadow_offset_x", 0)
	head.add_theme_constant_override("shadow_offset_y", 2)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var sub := Label.new()
	sub.text = "best local runs — saved on this computer"
	sub.add_theme_color_override("font_color", Color("#6f6757"))
	sub.add_theme_font_size_override("font_size", 12)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	leaderboard_rows = VBoxContainer.new()
	leaderboard_rows.add_theme_constant_override("separation", 5)
	box.add_child(leaderboard_rows)
	lb_close_button = _small_button("Close")
	lb_close_button.custom_minimum_size = Vector2(180, 42)
	lb_close_button.add_theme_font_size_override("font_size", 16)
	_style_button(lb_close_button)
	lb_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(lb_close_button)
	lb_close_button.pressed.connect(close_leaderboard)
	leaderboard_panel.visible = false

func open_leaderboard() -> void:
	if leaderboard_open:
		return
	if menu_open:   # one modal at a time — step aside from Settings if it somehow holds the floor
		menu_open = false
		menu_panel.visible = false
	leaderboard_open = true
	_refresh_leaderboard_rows()   # always fresh — a run may have landed while the card sat closed
	leaderboard_panel.visible = true
	leaderboard_panel.move_to_front()
	_refresh_dim()
	lb_close_button.grab_focus()

func close_leaderboard() -> void:
	if not leaderboard_open:
		return   # toggle_menu calls this defensively on every open
	leaderboard_open = false
	leaderboard_panel.visible = false
	_refresh_dim()
	if screen == "menu":
		play_button.grab_focus()

func _refresh_leaderboard_rows() -> void:   # rebuild the submenu's rows — best run in gold, the rest in calm blue
	if leaderboard_rows == null:
		return
	for c in leaderboard_rows.get_children():
		c.queue_free()
	if leaderboard.is_empty():
		var e := Label.new()
		e.text = "no runs yet — press Play and set something on the board"
		e.add_theme_color_override("font_color", Color("#4c463b"))
		e.add_theme_font_size_override("font_size", 12)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		leaderboard_rows.add_child(e)
		return
	for i in leaderboard.size():
		var row := Label.new()
		row.text = "%d.   %s   ·   level %d   ·   %s" % [i + 1, str(leaderboard[i].score), leaderboard[i].level, leaderboard[i].when]
		row.add_theme_font_size_override("font_size", 14 if i == 0 else 12)
		row.add_theme_color_override("font_color", Color("#c9971f") if i == 0 else Color("#6f6757"))
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		leaderboard_rows.add_child(row)

func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 52)
	b.add_theme_font_size_override("font_size", 20)
	return b

func _big_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(400, 60)
	b.add_theme_font_size_override("font_size", 24)
	_style_button(b)
	return b

func _btn_sb(col: Color, shadow: int) -> StyleBoxFlat:   # one rounded, softly-shadowed button state
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.12)   # hairline highlight inside an ink chip
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(0, 2)
	return sb

func _style_button(b: Button, accent := false) -> void:   # the whole button family in one place: soft ink-navy (or action-blue) pills instead of the stock grey chips
	var base := Color("#2a5f8f") if accent else Color("#2b2620", 0.94)
	var hover := Color("#35709f") if accent else Color("#3b352c", 0.97)
	var press := Color("#214d77") if accent else Color("#1d1913", 0.98)
	var states := [["normal", base, 5], ["hover", hover, 9], ["pressed", press, 2], ["focus", base, 5], ["disabled", Color(0.55, 0.52, 0.45, 0.55), 0]]
	for s in states:
		var sb := _btn_sb(s[1], s[2])
		if s[0] == "focus":
			sb.border_color = Color("#c9971f", 0.75)   # a marigold spot-color ring, not the default white box
		b.add_theme_stylebox_override(s[0], sb)
	b.add_theme_color_override("font_color", Color("#f4ecdb", 0.94))
	b.add_theme_color_override("font_hover_color", Color("#faf4e6", 1))
	b.add_theme_color_override("font_pressed_color", Color("#e8dfc8", 0.88))
	b.add_theme_color_override("font_focus_color", Color("#faf4e6", 1))
	b.add_theme_color_override("font_disabled_color", Color("#f4ecdb", 0.45))
	b.focus_mode = Control.FOCUS_ALL   # keyboard reach survives the restyled ring

func _card_style() -> StyleBoxFlat:   # opaque, rounded, soft-shadowed paper card — readable whatever is behind it
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#f4ecdb", 0.97)
	sb.border_color = Color("#7a5c49", 0.38)
	sb.set_border_width_all(1)   # hairline border — the shadow does the separating, not the frame
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(26.0)
	sb.shadow_color = Color(0.18, 0.14, 0.09, 0.45)
	sb.shadow_size = 26
	sb.shadow_offset = Vector2(0, 10)
	return sb

func _center_menu_cards() -> void:   # anchor-centering only follows the root control, but expand-stretch worlds can hang off it — pin the cards to the real visible-world center instead
	if menu_panel == null or main_menu_panel == null: return
	_center_content()
	var wc := _world_rect().get_center()
	_place_card(menu_panel, wc, Vector2(480.0, 520.0) if menu_return == "game" else Vector2(440.0, 520.0))   # the paused sheet carries run info + hints + the quit row — taller than plain Settings
	_place_card(main_menu_panel, wc, Vector2(440.0, 520.0))
	if leaderboard_panel != null:
		_place_card(leaderboard_panel, wc, Vector2(480.0, 450.0))

func _center_content() -> void:   # 4.7.2 removed Window.content_scale_offset entirely (verified in scene/main/viewport.cpp: the stretch transform carries scale only, origin 0) — the public Viewport canvas transform stands in, translating the design space so it sits centered in the expanded world
	var vp := get_viewport()
	if vp == null: return
	vp.set_canvas_transform(Transform2D(0.0, _content_offset()))   # 4.7 has no Transform2D(Vector2) overload — identity rotation + origin

func _content_offset() -> Vector2:   # half of the world surplus in canvas units — an axis that matches the base aspect exactly gets a 0 margin there
	var wsz := get_viewport().get_visible_rect().size   # in 4.7 this is already the scaled world size (window px ÷ content scale)
	return (wsz - Vector2(W, H)) / 2.0

func _place_card(c: Control, wc: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)   # absolute canvas-space placement — the offsets below are world coordinates
	c.offset_left = wc.x - sz.x / 2.0
	c.offset_right = wc.x + sz.x / 2.0
	c.offset_top = wc.y - sz.y / 2.0
	c.offset_bottom = wc.y + sz.y / 2.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_center_menu_cards()

func _refresh_dim() -> void:   # the dark veil belongs to whichever modal card is up — the bare main menu stays bright behind its own scene
	if main_menu_dim != null:
		main_menu_dim.visible = menu_open or leaderboard_open

func play() -> void:   # the Play button — also how tests enter gameplay (Play from a finished game = new run)
	if state.over:
		restart()   # it announces the fresh level itself
	elif screen != "game":
		flash_message("LEVEL 1", 2.0, true)   # plain ink on the paper — no cream banner box around the level card
	state.paused = false
	menu_open = false
	menu_panel.visible = false
	screen = "game"
	main_menu_panel.visible = false
	main_menu_dim.visible = false
	grab_focus()

func _on_menu_settings_pressed() -> void:
	if not menu_open:
		toggle_menu()   # menu_return picks up screen == "menu", so Back/Esc land back here

func build_settings_menu() -> void:
	menu_panel = PanelContainer.new()
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # panel eats its own clicks; the handle_mouse_click guard covers the rest
	menu_panel.add_theme_stylebox_override("panel", _card_style())   # opaque navy card — readable over both the game and the title scene
	menu_panel.custom_minimum_size = Vector2(480, 500)
	add_child(menu_panel)   # centered by _center_menu_cards(), which pins to the true visible-world center, not the anchors
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	menu_panel.add_child(box)
	sheet_title = Label.new()
	sheet_title.text = "Settings"
	sheet_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet_title.add_theme_font_size_override("font_size", 24)
	sheet_title.add_theme_color_override("font_color", Color("#2b2620", 0.95))
	box.add_child(sheet_title)
	sheet_status = Label.new()
	sheet_status.text = "everything here saves itself"
	sheet_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet_status.add_theme_font_size_override("font_size", 12)
	sheet_status.add_theme_color_override("font_color", Color("#6f6757"))
	box.add_child(sheet_status)
	sheet_hints = Label.new()
	sheet_hints.text = "drag left to move · tap right to fire · papers rotate every level" if _is_touch_device() else "arrows / A · D move — click / Space launches · Z laser — papers rotate every level"
	sheet_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet_hints.add_theme_font_size_override("font_size", 12)
	sheet_hints.add_theme_color_override("font_color", Color("#5b5347"))
	sheet_hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # wrap inside the card, never widen it
	sheet_hints.custom_minimum_size = Vector2(400, 0)
	box.add_child(sheet_hints)
	var res_row := HBoxContainer.new()
	var res_lbl := Label.new()
	res_lbl.text = "Resolution"
	res_lbl.add_theme_color_override("font_color", Color("#4c463b"))
	res_row.add_child(res_lbl)
	res_option = OptionButton.new()
	for s in _res_items:
		res_option.add_item(s)
	res_option.select(maxi(0, _res_values.find(str(settings["size"]))))
	res_row.add_child(res_option)
	box.add_child(res_row)
	res_row.visible = not _is_mobile_os()   # a phone has exactly one resolution — its own screen; the OptionButton popup it opens is what wedged Android
	fs_check = CheckButton.new()
	fs_check.text = "Fullscreen"
	fs_check.add_theme_color_override("font_color", Color("#4c463b"))
	fs_check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # a full-width CheckButton parks its toggle box at the far edge of the card — keep it snug beside the label
	fs_check.set_pressed_no_signal(bool(settings.fullscreen))
	box.add_child(fs_check)
	fs_check.visible = not _is_mobile_os()   # phones run immersive-fullscreen only — nothing to toggle
	sfx_slider = _menu_slider(float(settings.sfx_vol))
	box.add_child(_menu_row("SFX volume", sfx_slider))
	music_slider = _menu_slider(float(settings.music_vol))
	box.add_child(_menu_row("Music volume", music_slider))
	var track_row := HBoxContainer.new()
	var track_lbl := Label.new()
	track_lbl.text = "Music track"
	track_lbl.add_theme_color_override("font_color", Color("#4c463b"))
	track_row.add_child(track_lbl)
	music_option = OptionButton.new()
	music_option.custom_minimum_size = Vector2(220, 0)
	track_row.add_child(music_option)
	if _is_mobile_os():   # same Android popup hazard as the Background picker — a plain button cycles instead
		music_option.visible = false
		music_cycle = Button.new()
		music_cycle.custom_minimum_size = Vector2(220, 0)
		music_cycle.add_theme_font_size_override("font_size", 15)
		music_cycle.pressed.connect(_cycle_music)
		track_row.add_child(music_cycle)
	box.add_child(track_row)
	refresh_music_option()   # item 0 = auto-shuffle; select() here never fires item_selected
	var bg_row := HBoxContainer.new()
	var bg_lbl := Label.new()
	bg_lbl.text = "Background"
	bg_lbl.add_theme_color_override("font_color", Color("#4c463b"))
	bg_row.add_child(bg_lbl)
	bg_option = OptionButton.new()
	bg_option.custom_minimum_size = Vector2(220, 0)
	bg_row.add_child(bg_option)
	if _is_mobile_os():   # the OptionButton popup is what wedges Android — a phone gets a plain tap-to-cycle button instead
		bg_option.visible = false
		bg_cycle = Button.new()
		bg_cycle.custom_minimum_size = Vector2(220, 0)
		bg_cycle.add_theme_font_size_override("font_size", 15)
		bg_cycle.pressed.connect(_cycle_bg)
		bg_row.add_child(bg_cycle)
	box.add_child(bg_row)
	refresh_bg_option()   # item 0 is always "(auto — rotates per level)" — select() here never fires item_selected
	var note := Label.new()
	note.text = "Music: drop .ogg/.mp3/.wav into music/ · Backgrounds: drop PNGs into backgrounds/"
	note.add_theme_color_override("font_color", Color("#5b5347"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # keep the panel at its intended width
	note.custom_minimum_size = Vector2(400, 0)   # stays inside the card's content width (460 - 2x24 margin)
	box.add_child(note)
	note.visible = not _is_mobile_os()   # both notes are desktop developer instructions — you can't drop files into the APK on a phone
	var note2 := Label.new()
	note2.text = "Copy files in, focus the editor once (Godot imports them), re-open this menu"
	note2.add_theme_color_override("font_color", Color("#5b5347"))
	note2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note2.custom_minimum_size = Vector2(400, 0)
	box.add_child(note2)
	note2.visible = not _is_mobile_os()
	pause_row = HBoxContainer.new()   # the paused face's way out — all three actions fit one compact row
	pause_row.add_theme_constant_override("separation", 10)
	pause_row.alignment = BoxContainer.ALIGNMENT_CENTER
	resume_button = _small_button("Resume")
	quit_menu_button = _small_button("Quit to menu")
	quit_game_button = _small_button("Quit game")
	for qb in [resume_button, quit_menu_button, quit_game_button]:
		_style_button(qb)
		qb.custom_minimum_size = Vector2(138, 42)
		qb.add_theme_font_size_override("font_size", 15)
	pause_row.add_child(resume_button)
	pause_row.add_child(quit_menu_button)
	pause_row.add_child(quit_game_button)
	box.add_child(pause_row)
	back_button = Button.new()
	back_button.text = "Back to menu"
	_style_button(back_button)
	box.add_child(back_button)
	res_option.item_selected.connect(_on_res_selected)
	fs_check.toggled.connect(_on_fs_toggled)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	music_slider.value_changed.connect(_on_music_changed)
	music_option.item_selected.connect(_on_track_selected)
	bg_option.item_selected.connect(_on_bg_selected)
	back_button.pressed.connect(toggle_menu)   # the same toggle the Esc key uses — menu_open decides the direction
	resume_button.pressed.connect(func() -> void:
		if menu_open: toggle_menu())   # Resume = close the sheet (and the pause with it)
	quit_menu_button.pressed.connect(quit_to_menu)
	quit_game_button.pressed.connect(quit_game)
	menu_panel.visible = false
	pause_row.visible = false

func _menu_row(text: String, slider: HSlider) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color("#4c463b"))
	row.add_child(lbl)
	row.add_child(slider)
	return row

func _menu_slider(linear: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.custom_minimum_size = Vector2(220, 0)
	s.set_value_no_signal(linear * 100.0)   # boot-time state must not fire signals
	if _is_mobile_os():
		s.custom_minimum_size = Vector2(220, 36)   # a row-height slider leaves a fingernail-sized grabber — give the finger something to land on
		s.gui_input.connect(_on_touch_slider.bind(s))   # Range only begins a drag when the press lands on the grabber, so steer the value off the finger instead
	return s

func _on_touch_slider(event: InputEvent, sl: HSlider) -> void:   # on a phone a tap or drag anywhere along the groove sets the volume
	var touch := event as InputEventScreenTouch
	var drag := event as InputEventScreenDrag
	var x: float = 0.0
	if touch != null:
		if not touch.pressed:
			return   # releasing shouldn't nudge the value
		x = touch.position.x
	elif drag != null:
		x = drag.position.x
	else:
		return
	var span: float = maxf(sl.size.x, 1.0)
	sl.value = sl.min_value + clampf(x / span, 0.0, 1.0) * (sl.max_value - sl.min_value)

func _on_res_selected(index: int) -> void:
	settings["size"] = _res_values[clampi(index, 0, _res_values.size() - 1)]   # the option text is a display label; the saved value is the bare WxH (kept even while fullscreen)
	if not bool(settings.fullscreen):
		_resize_window(str(settings["size"]))
	save_settings()

func _on_fs_toggled(on: bool) -> void:
	settings.fullscreen = on
	res_option.disabled = on   # size select disabled while fullscreen
	if on:
		get_window().mode = Window.MODE_FULLSCREEN
	else:
		get_window().mode = Window.MODE_WINDOWED
		_resize_window(str(settings["size"]))
	save_settings()

func _on_sfx_changed(v: float) -> void:
	set_setting("sfx_vol", v / 100.0)

func _on_music_changed(v: float) -> void:
	set_setting("music_vol", v / 100.0)

func refresh_bg_option() -> void:   # rebuild the picker from the (re-)scanned name list
	if bg_option == null: return
	bg_option.clear()
	bg_option.add_item("(auto — rotates per level)")
	for n in bg_names:
		bg_option.add_item(str(n))
	var current := 0   # item 0 = auto, 1..n = pinned sheets — select() must not fire item_selected
	if String(settings.get("bg", "auto")) != "auto":
		var i := bg_names.find(String(settings["bg"]))
		if i >= 0: current = i + 1
	if current >= bg_option.item_count: current = 0
	bg_option.select(current)
	_sync_bg_cycle()

func _cycle_bg() -> void:   # the phone's dropdown: one tap advances the pick, wrapping back to auto
	if bg_option == null: return
	var n: int = bg_option.item_count
	if n <= 0: return
	var next: int = (int(bg_option.selected) + 1) % n
	bg_option.select(next)   # select() never fires item_selected, so the pick has to be applied by hand
	_on_bg_selected(next)
	_sync_bg_cycle()

func _sync_bg_cycle() -> void:   # keep the mobile cycle button's caption on whatever the current pick is
	if bg_cycle == null or bg_option == null: return
	var i: int = int(bg_option.selected)
	if i < 0:
		bg_cycle.text = ""
		return
	bg_cycle.text = str(bg_option.get_item_text(i)) + "  ▸"

func _on_bg_selected(index: int) -> void:   # the picker is the only way to touch backgrounds now — B is retired, papers rotate by themselves
	if index <= 0:
		settings["bg"] = "auto"
		save_settings()
		auto_background()
	else:
		settings["bg"] = str(bg_names[index - 1])
		save_settings()
		set_background(index - 1)

func _track_label(name: String) -> String:   # ink_runner.wav -> "Ink Runner"
	var stem: String = name.get_basename()
	var words: PackedStringArray = stem.split("_")
	for i in range(words.size()): words[i] = words[i].capitalize()
	return " ".join(words)

func refresh_music_option() -> void:   # rebuild the picker from the (re-)scanned track list
	if music_option == null: return
	music_option.clear()
	music_option.add_item("(auto — shuffle)")
	for n in music_names: music_option.add_item(_track_label(str(n)))
	var current := 0
	var tr := String(settings.get("track", "auto"))
	if tr != "auto":
		var i := music_names.find(tr)
		if i >= 0: current = i + 1
	if current >= music_option.item_count: current = 0
	music_option.select(current)   # select() never fires item_selected
	_sync_music_cycle()

func _cycle_music() -> void:   # the phone's dropdown: one tap advances the pick, wrapping back to auto
	if music_option == null: return
	var n: int = music_option.item_count
	if n <= 0: return
	var next: int = (int(music_option.selected) + 1) % n
	music_option.select(next)
	_on_track_selected(next)
	_sync_music_cycle()

func _sync_music_cycle() -> void:
	if music_cycle == null or music_option == null: return
	var i: int = int(music_option.selected)
	if i < 0:
		music_cycle.text = ""
		return
	music_cycle.text = str(music_option.get_item_text(i)) + "  ▸"

func _on_track_selected(index: int) -> void:
	if index <= 0: settings["track"] = "auto"
	else: settings["track"] = str(music_names[index - 1])
	save_settings()
	music_adaptive = false   # a manual pick wins over FEVER's mood swing
	apply_track_setting()
	_sync_music_cycle()

# ---------------- Music (drop files in music/, manifest merges + dedups, shuffle via rr()) ----------------
var music_manifest := {"music": [], "shuffle": true, "loop": true}
var music_player: AudioStreamPlayer      # the canonical ACTIVE player — always holds the incoming stream
var music_player_b: AudioStreamPlayer    # outgoing stream during a crossfade
var music_playlist := []   # loaded AudioStream resources
var music_names := []      # parallel filenames, so the settings picker can pin a track by name
var music_order := []   # indices into music_playlist (shuffled at boot with rr() when the manifest says so)
var music_played := 0
var music_base_idx := 0    # the shuffled/pinned track to return to after an adaptive detour
var music_adaptive := false
var music_active_idx := 0
var music_current_name := ""   # drives the beat clock
var music_fade = null          # non-null while a crossfade is running
const MUSIC_FADE := 1.2
const MUSIC_BPM := {"paper_corridor.wav": 140.0, "starlight_patrol.wav": 128.0, "circuit_sunset.wav": 152.0,
                    "iron_press.wav": 132.0, "paper_moon.wav": 96.0, "ink_runner.wav": 164.0}
var beat_phase := 0.0
var beat_pulse := 0.0

func _import_dest(path: String) -> String:   # the importer's stored-artifact path from the <file>.import sidecar
	var f := FileAccess.open(path + ".import", FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		var l := f.get_line()
		if l.begins_with("path="):
			return l.substr(6, l.length() - 7)   # strip  path="  ...  "
	return ""

func scan_music_names() -> Array:   # real files OR .import sidecars (an exported PCK may pack only the sidecar + artifact)
	var found := {}
	var da := DirAccess.open("res://music")
	if da:
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			var stem := f.trim_suffix(".import") if f.get_extension().to_lower() == "import" else f
			if stem.get_extension().to_lower() in ["ogg", "mp3", "wav"]:
				found[stem] = true
			f = da.get_next()
		da.list_dir_end()
	var out := []
	for k in found:
		out.append(k)
	out.sort()
	return out

func init_music() -> void:
	var mtxt := FileAccess.get_file_as_string("res://music/manifest.json")
	var mf = JSON.parse_string(mtxt) if mtxt != "" else null   # get_file_as_string returns "" on a missing file; JSON.parse_string("") returns null
	if typeof(mf) == TYPE_DICTIONARY:
		if typeof(mf.get("music", null)) == TYPE_ARRAY:
			music_manifest.music = mf["music"]
		music_manifest.shuffle = bool(mf.get("shuffle", true))
		music_manifest.loop = bool(mf.get("loop", true))
		for k in mf:   # unknown keys: tolerated now, and loudly logged if they ever bite again
			if not k in ["music", "shuffle", "loop"]:
				push_warning("music/manifest.json: ignoring unknown key '" + str(k) + "'")
	load_music_playlist()
	apply_track_setting()   # "auto" shuffles; a pinned track starts there — either way the picker and the stream agree

func load_music_playlist() -> void:
	var names := scan_music_names()
	for n in music_manifest.music:   # merge manifest names with dedup against the folder scan
		if typeof(n) == TYPE_STRING and not names.has(n):
			names.append(n)
	music_playlist.clear()
	music_names.clear()
	for n in names:
		var p := "res://music/" + str(n)
		var aud = load(p)
		if aud == null:   # export packs can ship the import artifact without the res:// remap — read the .import sidecar
			var dest := _import_dest(p)
			if dest != "" and ResourceLoader.exists(dest):
				aud = load(dest)
				print("music fallback: ", str(n), " -> ", dest)
		if aud:
			music_playlist.append(aud)
			music_names.append(str(n))
	print("music: ", music_playlist.size(), " track(s) loaded — ", ", ".join(names))

func _gain_db(g: float) -> float:
	return linear_to_db(maxf(g, 0.0001))   # linear_to_db(0) is -inf; clamp for a well-behaved fade

func play_music_index(idx: int, crossfade: bool = false) -> void:
	if music_playlist.is_empty() or music_player == null: return
	idx = ((idx % music_playlist.size()) + music_playlist.size()) % music_playlist.size()
	music_active_idx = idx
	music_current_name = String(music_names[idx]) if idx < music_names.size() else ""
	var incoming = music_playlist[idx]
	if crossfade and music_player.playing and music_player_b != null:
		var pos: float = music_player.get_playback_position()
		music_player_b.stream = music_player.stream
		music_player_b.volume_db = 0.0
		music_player_b.play()
		music_player_b.seek(pos)   # the outgoing theme keeps its place while it fades
		music_player.stream = incoming
		music_player.volume_db = _gain_db(0.0)
		music_player.play()
		music_fade = {"t": 0.0}
	else:
		music_fade = null
		if music_player_b != null: music_player_b.stop()
		music_player.volume_db = 0.0
		music_player.stream = incoming
		music_player.play()
	print("music: now playing ", music_current_name, " (fade=", crossfade, ")")

func _update_music_fade(dt: float) -> void:
	if music_fade == null: return
	music_fade["t"] = float(music_fade["t"]) + dt
	var k: float = clampf(float(music_fade["t"]) / MUSIC_FADE, 0.0, 1.0)
	var e: float = k * k * (3.0 - 2.0 * k)   # smoothstep — no audible corners
	music_player.volume_db = _gain_db(e)
	music_player_b.volume_db = _gain_db(1.0 - e)
	if k >= 1.0:
		music_player_b.stop()
		music_fade = null

func start_music() -> void:
	if music_playlist.is_empty():
		return   # silent boot, no crash — an empty playlist is the normal case until files are dropped + imported
	music_order = range(music_playlist.size())
	if bool(music_manifest.shuffle):
		for i in range(music_order.size() - 1, 0, -1):   # Fisher-Yates using the game's own rr()
			var j := int(floor(rr() * (i + 1)))
			var tmp = music_order[i]
			music_order[i] = music_order[j]
			music_order[j] = tmp
	music_played = 0
	music_base_idx = music_order[0]
	play_music_index(music_base_idx, false)

func _energy_track_idx() -> int:   # the highest-BPM shipped track — FEVER and gold rush borrow its momentum
	var best := 0
	var best_bpm := -1.0
	for i in range(music_playlist.size()):
		var nm: String = String(music_names[i]) if i < music_names.size() else ""
		var bpm: float = float(MUSIC_BPM.get(nm, 120.0))
		if bpm > best_bpm:
			best_bpm = bpm
			best = i
	return best

func apply_track_setting() -> void:   # resolve settings["track"] ("auto" | filename) onto a live stream
	var tr := String(settings.get("track", "auto"))
	if tr == "auto" or music_playlist.is_empty():
		start_music()
	else:
		var i := music_names.find(tr)
		if i < 0:
			settings["track"] = "auto"   # a saved track that fell off the disk can't strand the player on silence
			start_music()
		else:
			music_adaptive = false
			music_base_idx = i
			play_music_index(i, false)
	refresh_music_option()

func rescan_music() -> void:   # settings overlay re-open path: pick up files dropped + imported since boot
	load_music_playlist()
	refresh_music_option()
	if music_player == null or not music_player.playing:
		apply_track_setting()   # only restart when nothing is playing — never cut a live theme just to rescan

func _on_music_finished() -> void:
	if music_fade != null: return   # the fading-out player must never pick the next track
	if music_playlist.is_empty() or music_order.is_empty(): return
	if String(settings.get("track", "auto")) != "auto" or music_adaptive:
		play_music_index(music_active_idx, false)   # pinned or high-energy: loop this one
		return
	if not bool(music_manifest.loop) and music_played + 1 >= music_order.size():
		return   # one pass, then silence
	music_played += 1
	var slot := music_played % music_order.size()
	music_base_idx = music_order[slot]
	play_music_index(music_base_idx, true)

# ---------------- Particles ----------------
func spark(x: float, y: float, color_hex: String) -> void:
	for _i in 10:
		var a: float = rr() * TAU
		var s: float = 40.0 + rr() * 140.0
		state.particles.append({"x": x, "y": y, "vx": cos(a) * s, "vy": sin(a) * s, "life": 0.4, "color": color_hex})

func puff(x: float, y: float, base_angle: float) -> void:   # deterministic 3-particle fan for wall/shield bounces — never touches the rr() stream
	for k in 3:
		var a: float = base_angle + (float(k) - 1.0) * 0.45
		var s: float = 100.0 + float(k) * 35.0
		state.particles.append({"x": x, "y": y, "vx": cos(a) * s, "vy": sin(a) * s, "life": 0.25, "color": "#e3f2fd"})

# ---------------- Input ----------------
func handle_key(name: String) -> void:   # JS keydown handler, lowercased key names
	name = name.to_lower()
	keys[name] = true
	if name == "f": toggle_fullscreen()
	if name == "escape":   # THE menu key — pauses behind the sheet in game, opens Settings from the menu, dismisses the leaderboard first if it holds the floor
		if leaderboard_open: close_leaderboard()
		else: toggle_menu()
		return
	if screen != "game": return   # at the main menu the game keys are inert; Play/Settings/Leaderboards/Quit are GUI buttons
	if name == " ": fire_laser()
	if name == "r" and state.over: restart()

func handle_key_up(name: String) -> void: keys[name.to_lower()] = false

func handle_mouse_motion(x: float) -> void: mouse_x = x   # canvas mousemove, scaled coords

func handle_mouse_click() -> void:   # canvas mousedown
	if menu_open or screen == "menu": return   # menus are a full freeze — no gameplay actions while one is up
	if state.paused: return   # the pause sheet owns the screen now — its buttons decide, not the laser
	if state.over: restart()
	else: fire_laser()

func toggle_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_WINDOWED)

func restart() -> void:
	state.over = false
	state.paused = false
	state.score = 0
	state.level = 1
	state.lives = 3
	state.paddleW = PADDLE_BASE_W
	state.message = ""
	state.msgTimer = 0.0
	build_level()
	flash_message("LEVEL " + str(state.level), 2.0, true)   # the brief level title card — plain ink, no ugly box
	touch_hint_timer = 4.0   # show mobile touch instructions for 4 seconds
	touch_hint_visible = true

# ---------------- Update ----------------
func update(dt: float) -> void:
	bg_time += dt   # the visual clock also ticks behind the menu/pause screens, so those scenes stay alive
	# music beat clock + crossfade ramp — both keep running behind menus (the music never freezes)
	var bpm: float = float(MUSIC_BPM.get(music_current_name, 120.0))
	beat_phase = fmod(beat_phase + dt * bpm / 60.0, 1.0)
	beat_pulse = pow(1.0 - beat_phase, 4.0)   # 1 on the beat, decaying to 0 before the next
	_update_music_fade(dt)
	# real-time tone queue ticks even while paused (JS setTimeout equivalence)
	var due := []
	for t in pending_tones:
		t.at -= dt
		if t.at <= 0.0: due.append(t)
	for t in due:
		pending_tones.erase(t)
		play_tone(t.freq, t.dur, t.type, t.vol)
	if state.paused or menu_open or screen == "menu": return   # full freeze: paddle, balls, timers, drops — all of it (the pause menu and any open modal count as paused)
	# paddle — keyboard only now: the mouse no longer steers it (accidental bumps teleported the paddle;
	# the mouse still launches / fires / clicks the menu). Speed raised for keyboard-only comfort.
	var speed := 820.0
	if keys.get("arrowleft", false) or keys.get("a", false):
		paddle.x -= speed * dt
	if keys.get("arrowright", false) or keys.get("d", false):
		paddle.x += speed * dt
	# expand-stretch can make the visible world much wider than the 960 design space —
	# the paddle and the side walls play off the REAL visible edges, so nothing hides in the margins
	var field := _world_rect()
	paddle.x = clampf(paddle.x, field.position.x, field.end.x - state.paddleW)

	if state.over: return

	# timers — collect-then-apply: GDScript must not mutate a Dictionary during iteration
	var to_erase := []
	var expired := []
	for k in state.active.keys():
		state.active[k] -= dt
		if state.active[k] <= 0.0: expired.append(k)
	for k in expired:
		to_erase.append(k)
		if k == "EXPAND" or k == "SHRINK": state.paddleW = PADDLE_BASE_W
	for k in to_erase: state.active.erase(k)
	if to_erase.size() > 0: normalize_speeds()
	if state.msgTimer > 0.0:
		state.msgTimer -= dt
		if state.msgTimer <= 0.0: state.message = ""
	# Mobile touch hint timer — fades out the instruction overlay
	if touch_hint_timer > 0.0:
		touch_hint_timer -= dt
		if touch_hint_timer <= 0.0:
			touch_hint_timer = 0.0
			touch_hint_visible = false
	if state.shake > 0.0: state.shake -= dt * 20.0

	# The Press — the whole field drops a row every 25 s, warned five seconds out
	state.pressTimer = float(state.pressTimer) - dt
	if float(state.pressTimer) <= PRESS_WARN and not bool(state.pressWarned):
		state.pressWarned = true
		flash_message("THE PRESS IS COMING!", 1.1, true)
		state.shake = maxf(float(state.shake), 3.0)
	if float(state.pressTimer) <= 0.0:
		press_descend()

	# Gold rush — every third level pays ×3 while fresh blocks keep printing
	if bool(state.rush):
		state.rushTimer = float(state.rushTimer) - dt
		state.rushWaveTimer = float(state.rushWaveTimer) - dt
		if float(state.rushWaveTimer) <= 0.0 and int(state.rushWavesLeft) > 0:
			state.rushWavesLeft = int(state.rushWavesLeft) - 1
			state.rushWaveTimer = RUSH_TIME / float(RUSH_WAVES)
			rush_spawn_wave()
		if float(state.rushTimer) <= 0.0:
			state.rush = false
			var rbonus := 300
			state.score += int(rbonus * fever_mult())
			popup(paddle.x + state.paddleW / 2.0, paddle.y - 60.0, "GOLD RUSH +" + str(rbonus), Color("#c9971f"))
			boom(paddle.x + state.paddleW / 2.0, paddle.y - 30.0, 2, Color("#c9971f"))
			sync_music_energy()

	# FEVER mode clock — expires with a parting bonus & ring
	if float(state.fever) > 0.0:
		state.fever = float(state.fever) - dt
		if float(state.fever) <= 0.0:
			state.fever = 0.0
			state.score += FEVER_BONUS
			popup(paddle.x + state.paddleW / 2.0, paddle.y - 46.0, "FEVER OUT +" + str(FEVER_BONUS), Color("#ff9800"))
			boom(paddle.x + state.paddleW / 2.0, paddle.y - 18.0, 1, Color("#ff9800"))
			play_tone(392.0, 0.1, "square", 0.05)
			schedule_tone(0.13, 294.0, 0.2, "square", 0.05)
			sync_music_energy()   # the fever theme steps aside when the heat dies

	# shockwave rings age out (pure visuals)
	for bm in state.booms:
		bm.t += dt
	var live_booms := []
	for bm in state.booms:
		if float(bm.t) < float(bm.ttl): live_booms.append(bm)
	state.booms = live_booms

	# TNT fuses — a lit domino bomb pops on its beat; the chain visibly ROLLS across the field
	var popping := []
	for blk in blocks_data:
		if blk.get("fuse") != null:
			var fz: float = float(blk["fuse"]) - dt
			blk["fuse"] = fz
			if fz <= 0.0: popping.append(blk)
	for blk in popping:
		if blocks_data.has(blk):
			state.score += int(BLOCK_TYPES[blk.t].score * score_mult())   # the domino pays its base score too
			do_explode(blk, int(blk.get("fuse_depth", 1)))
			destroy_block(blk, blocks_data.find(blk))
	check_clear()   # a domino wave landing the final blow clears the level too (the old code missed this case)

	# particles
	for p in state.particles:
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.vy += 300.0 * dt
		p.life -= dt
	var new_particles := []
	for p in state.particles:
		if p.life > 0.0: new_particles.append(p)
	state.particles = new_particles

	# ball trails, floating popups, pickup flash, paddle squash
	for tr in state.trail:
		tr.life -= dt
	var new_trail := []
	for tr in state.trail:
		if tr.life > 0.0: new_trail.append(tr)
	state.trail = new_trail
	for pp in state.popups:
		pp.y -= 34.0 * dt
		pp.ttl -= dt
	var new_popups := []
	for pp in state.popups:
		if pp.ttl > 0.0: new_popups.append(pp)
	state.popups = new_popups
	state.flash = maxf(0.0, float(state.flash) - dt * 1.8)
	paddle["squash"] = maxf(0.0, float(paddle["squash"]) - dt * 5.0)

	# drops
	for d in state.drops:
		d.y += d.vy * dt
		if d.y + 10.0 >= paddle.y and d.y <= paddle.y + PADDLE_H + 6.0 and d.x >= paddle.x - 6.0 and d.x <= paddle.x + state.paddleW + 6.0:
			d.dead = true
			apply_powerup(d.key)
		if d.y > H: d.dead = true
	var new_drops := []
	for d in state.drops:
		if not d.get("dead", false): new_drops.append(d)
	state.drops = new_drops

	# lasers
	for l in state.lasers:
		l.y -= 900.0 * dt
		l.ttl -= dt
		for blk in blocks_data.duplicate():   # JS iterated a copy
			if l.x >= blk.x and l.x <= blk.x + bw(blk) and l.y <= blk.y + bh(blk) and l.y >= blk.y:
				l.dead = true
				if not BLOCK_TYPES[blk.t].indestructible:
					hit_block(blk, false)
				else:
					# lasers melt steel — metal blocks get very annoying in later stages, so one bolt vaporizes them
					state.score += int(BLOCK_TYPES[blk.t].score * score_mult())
					spark(l.x, l.y, blk.color)
					destroy_block(blk, -1)
				break
		if l.y < FIELD_TOP - 20.0 or l.ttl <= 0.0: l.dead = true
	var new_lasers := []
	for l in state.lasers:
		if not l.get("dead", false): new_lasers.append(l)
	state.lasers = new_lasers

	# balls
	var molten_ball: bool = state.active.get("LAVA", 0.0) > 0.0
	var fevered_ball: bool = float(state.fever) > 0.0
	for b in state.balls:
		if b.stuck:
			b.x = paddle.x + state.paddleW / 2.0
			b.y = paddle.y - BALL_R
			if state.active.get("STICKY", 0.0) > 0.0: sticky_ball = b
			continue
		b.x += b.vx * dt
		b.y += b.vy * dt
		if b.x < field.position.x + BALL_R:
			b.x = field.position.x + BALL_R
			b.vx = absf(b.vx)
			play_tone(440, 0.04, "square", 0.05)
			puff(field.position.x + BALL_R, b.y, 0.0)
			if brick_near(b.x, b.y): near_miss(b.x, b.y, "CLOSE!")
		if b.x > field.end.x - BALL_R:
			b.x = field.end.x - BALL_R
			b.vx = -absf(b.vx)
			play_tone(440, 0.04, "square", 0.05)
			puff(field.end.x - BALL_R, b.y, PI)
			if brick_near(b.x, b.y): near_miss(b.x, b.y, "CLOSE!")
		if b.y < FIELD_TOP - 30.0 + BALL_R - 30.0:
			b.y = FIELD_TOP - 30.0 + BALL_R - 30.0
			b.vy = absf(b.vy)
			play_tone(440, 0.04, "square", 0.05)
			puff(b.x, FIELD_TOP - 30.0 + BALL_R - 30.0, PI / 2.0)
		if b.y > H + BALL_R:
			if state.active.get("SHIELD", 0.0) > 0.0:
				b.y = H + BALL_R   # the floor barrier catches it — bounce instead of losing the ball
				b.vy = -absf(b.vy)
				play_tone(150, 0.08, "sine", 0.07)
				puff(b.x, H + BALL_R, -PI / 2.0)
				near_miss(b.x, H + BALL_R, "SAVED!")
			else:
				b.dead = true
				continue

		# paddle collision
		if b.vy > 0.0 and b.y + BALL_R >= paddle.y and b.y <= paddle.y + PADDLE_H + 4.0 and b.x >= paddle.x - BALL_R and b.x <= paddle.x + state.paddleW + BALL_R:
			var hit: float = clampf((b.x - (paddle.x + state.paddleW / 2.0)) / (state.paddleW / 2.0), -1.0, 1.0)
			var angle: float = (-90.0 + hit * 60.0) * PI / 180.0
			var tier: int = mini(int(maxf(0.0, float(state.combo)) / COMBO_STEP), 5)
			var s: float = min(sqrt(b.vx * b.vx + b.vy * b.vy) + BALL_SPEED_STEP + COMBO_SPEED_STEP * float(tier), BALL_MAX_SPEED)
			b.vx = cos(angle) * s
			b.vy = sin(angle) * s
			b.y = paddle.y - BALL_R
			paddle["squash"] = 1.0
			if absf(hit) > 0.86: near_miss(b.x, paddle.y - 14.0, "CLUTCH!")
			state.combo = 0   # a combo only survives between paddle touches — landing resets the chain
			if state.active.get("STICKY", 0.0) > 0.0:
				b.stuck = true
				sticky_ball = b
			else:
				play_tone(330, 0.05, "square", 0.05)

		# block collision (circle vs cell rect)
		for blk in blocks_data.duplicate():
			var nx: float = clampf(b.x, blk.x, blk.x + bw(blk))
			var ny: float = clampf(b.y, blk.y, blk.y + bh(blk))
			var dx: float = b.x - nx
			var dy: float = b.y - ny
			if dx * dx + dy * dy <= BALL_R * BALL_R:
				if state.active.get("LAVA", 0.0) > 0.0:
					lava_break(blk)   # molten ball: one-shots every block type, steel included — and BURNS THROUGH, no bounce, it keeps its course
				else:
					# reflect on the axis of contact
					if absf(dx) > absf(dy):
						b.vx = absf(b.vx) if dx > 0.0 else -absf(b.vx)
					else:
						b.vy = absf(b.vy) if dy > 0.0 else -absf(b.vy)
					hit_block(blk)
				break
		if not b.get("dead", false):   # every live, flying ball leaves a fading ghost (lava ghosts glow orange)
			if state.trail.size() >= MAX_TRAIL:
				state.trail.append(state.trail.pop_front())
			else:
				state.trail.append({})
			var tr2 = state.trail[-1]
			tr2.x = b.x
			tr2.y = b.y
			tr2.life = TRAIL_LIFE
			tr2.hot = molten_ball or fevered_ball   # lava ghosts AND fever ghosts tint warm
	var new_balls := []
	for b in state.balls:
		if not b.get("dead", false): new_balls.append(b)
	state.balls = new_balls
	if state.balls.size() == 0 and not state.over: lose_ball()

# ---------------- Render ----------------
func _process(delta: float) -> void:
	update(min(delta, 0.033))
	queue_redraw()

func _input(event: InputEvent) -> void:
	# keyboard + mouse route through the same handlers the tests drive
	if event is InputEventKey and event.pressed and not event.echo:
		var name := key_name(event)
		if name != "": handle_key(name)
	elif event is InputEventKey and not event.pressed:
		var name := key_name(event)
		if name != "": handle_key_up(name)
	elif event is InputEventMouseButton and event.pressed:
		handle_mouse_click()
	elif event is InputEventMouseMotion:
		# canvas mousemove in game coords — get_global_mouse_position undoes the content-scale/letterbox transform, correct at every window size
		handle_mouse_motion(get_global_mouse_position().x)
	
	# ---------------- Mobile touch handling ----------------
	elif event is InputEventScreenTouch:
		_touch_seen = true   # first real finger: reveal the touch HUD even on a desktop touchscreen
		handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		handle_screen_drag(event)

func key_name(ev: InputEventKey) -> String:
	var c := ev.keycode
	if c >= Key.KEY_A and c <= Key.KEY_Z: return char(c).to_lower()
	match c:
		Key.KEY_SPACE: return " "
		Key.KEY_ESCAPE: return "escape"
		Key.KEY_LEFT: return "arrowleft"
		Key.KEY_RIGHT: return "arrowright"
	return ""

func _is_mobile_os() -> bool:   # hard platform test — window resizing, fullscreen toggles and editor-import notes only mean something on a desktop
	var osn := OS.get_name().to_lower()
	return osn == "android" or osn == "ios" or osn == "web"

func _is_touch_device() -> bool:   # phones/tablets get the touch HUD and tap-worded prompts; desktop mouse+keyboard machines don't
	return _is_mobile_os() or _touch_seen

func handle_screen_touch(event: InputEventScreenTouch) -> void:
	if menu_open or screen == "menu": return
	if state.paused: return
	if state.over:
		restart()
		return
	
	# Transform touch position from screen pixels to canvas coordinates
	var touch_x: float = event.position.x
	var touch_y: float = event.position.y
	var touch_id: int = event.index
	
	# If this is a touch release, clear tracking
	if not event.pressed:
		if touch_id == touch_id_left:
			touch_id_left = -1
			joystick_active = false
			joystick_stick = Vector2.ZERO
			keys["arrowleft"] = false
			keys["arrowright"] = false
		elif touch_id == touch_id_right:
			touch_id_right = -1
		return
	
	# Transform to canvas coordinates using the inverse canvas transform
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var canvas_pos: Vector2 = inv * Vector2(touch_x, touch_y)
	var canvas_x: float = canvas_pos.x
	var canvas_y: float = canvas_pos.y
	
	# Check pause button tap first (top-left corner, under score)
	if pause_button_rect.has_point(Vector2(canvas_x, canvas_y)):
		toggle_menu()
		return
	
	# Determine if this is a left-side (joystick) or right-side (action) touch
	var mid_x: float = W / 2.0
	var is_left: bool = canvas_x < mid_x
	var is_right: bool = canvas_x >= mid_x
	
	# If already tracking a touch on the same side, don't override
	if is_left and touch_id_left >= 0: return
	if is_right and touch_id_right >= 0: return
	
	if is_left:
		# Start left-side joystick tracking
		touch_id_left = touch_id
		joystick_active = true
		joystick_origin = Vector2(canvas_x, canvas_y)  # touch position = joystick origin
		joystick_stick = Vector2.ZERO
	elif is_right:
		# Right side = tap to launch/laser
		handle_mouse_click()

func handle_screen_drag(event: InputEventScreenDrag) -> void:
	# Transform drag position from screen pixels to canvas coordinates
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var drag_pos: Vector2 = inv * event.position
	var drag_x: float = drag_pos.x
	var drag_y: float = drag_pos.y
	var drag_id: int = event.index
	
	# Track left-side drag for joystick
	if drag_id == touch_id_left and joystick_active:
		var delta: Vector2 = Vector2(drag_x, drag_y) - joystick_origin
		# Clamp to joystick radius for stick displacement
		if delta.length() > joystick_radius:
			delta = delta.normalized() * joystick_radius
		joystick_stick = delta
		# Map stick displacement to paddle movement
		# Negative X stick = move left, positive X stick = move right
		if delta.x < -10.0:
			keys["arrowleft"] = true
			keys["arrowright"] = false
		elif delta.x > 10.0:
			keys["arrowright"] = true
			keys["arrowleft"] = false
		else:
			keys["arrowleft"] = false
			keys["arrowright"] = false
		return

func _draw_touch_ui(font: Font) -> void:
	# Draw a subtle vertical divider line down the center (left = move, right = shoot)
	var divider: Color = Color(0.85, 0.83, 0.78, 0.08)
	draw_line(Vector2(W / 2.0, FIELD_TOP + 10.0), Vector2(W / 2.0, H - 30.0), divider, 1.0)
	
	# Left side: virtual joystick
	if joystick_active:
		# Joystick base circle
		rrect_path(joystick_origin.x - joystick_radius, joystick_origin.y - joystick_radius, joystick_radius * 2.0, joystick_radius * 2.0, joystick_radius, Color(0.85, 0.83, 0.78, 0.15))
		# Joystick stick (follows finger, clamped to radius)
		var stick_x: float = joystick_origin.x + joystick_stick.x
		var stick_y: float = joystick_origin.y + joystick_stick.y
		rrect_path(stick_x - 18.0, stick_y - 18.0, 36.0, 36.0, 18.0, Color(0.85, 0.83, 0.78, 0.30))
	else:
		# Show a subtle hint circle at the default joystick position
		rrect_path(joystick_origin.x - joystick_radius, joystick_origin.y - joystick_radius, joystick_radius * 2.0, joystick_radius * 2.0, joystick_radius, Color(0.85, 0.83, 0.78, 0.06))
	
	# Pause button (top-left under score) - more visible, pulsing glow
	var pause_alpha: float = 0.55 + 0.15 * sin(bg_time * 2.5)
	# Glow effect
	rrect_path(pause_button_rect.position.x - 2.0, pause_button_rect.position.y - 2.0, pause_button_rect.size.x + 4.0, pause_button_rect.size.y + 4.0, 12.0, Color(0.30, 0.38, 0.50, 0.12))
	# Main button
	rrect_path(pause_button_rect.position.x, pause_button_rect.position.y, pause_button_rect.size.x, pause_button_rect.size.y, 10.0, Color(0.25, 0.35, 0.48, pause_alpha))
	# Pause icon (II bars)
	var bar_width: float = 4.0
	var bar_height: float = pause_button_rect.size.y - 8.0
	var bar_x1: float = pause_button_rect.position.x + (pause_button_rect.size.x * 0.25)
	var bar_x2: float = pause_button_rect.position.x + (pause_button_rect.size.x * 0.65)
	var bar_y: float = pause_button_rect.position.y + (pause_button_rect.size.y - bar_height) / 2.0
	draw_rect(Rect2(bar_x1, bar_y, bar_width, bar_height), Color(0.90, 0.88, 0.82, pause_alpha))
	draw_rect(Rect2(bar_x2, bar_y, bar_width, bar_height), Color(0.90, 0.88, 0.82, pause_alpha))
	
	# Touch hint overlay (shows briefly when game starts, then fades)
	if touch_hint_timer > 0.0 and touch_hint_visible:
		var hint_alpha: float = clampf(touch_hint_timer / 4.0, 0.0, 1.0) * 0.45
		# Left hint: "Move" text
		draw_string(font, Vector2(W / 4.0, H - 60.0), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 14, Color(0.40, 0.38, 0.33, hint_alpha))
		# Right hint: "Shoot" text
		draw_string(font, Vector2(W * 3.0 / 4.0, H - 60.0), "SHOOT", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 14, Color(0.40, 0.38, 0.33, hint_alpha))
	
	# Bottom instruction hint (persistent faint text)
	var bottom_hint_alpha: float = 0.08 + 0.03 * sin(bg_time * 1.5)
	draw_string(font, Vector2(W / 2.0, H - 16.0), "Tap left to move · Tap right to shoot · Pause button top-left", HORIZONTAL_ALIGNMENT_CENTER, float(W) - 30.0, 11, Color(0.40, 0.38, 0.33, bottom_hint_alpha))

func _draw_menu_scene() -> void:   # the title screen: the game's own sky + deterministic stars + a decorative brick wall + idle paddle & ball, all scaled with the window
	const MENU_PALETTE := ["#c8402e", "#c96f2a", "#c9a227", "#4c8a54", "#2a5f8f", "#7b5e8c"]
	var wr := _world_rect()
	var top := COLOR_SLOTS["grad_top"]
	var bot := COLOR_SLOTS["grad_bottom"]
	draw_polygon(PackedVector2Array([wr.position, Vector2(wr.end.x, wr.position.y), wr.end, Vector2(wr.position.x, wr.end.y)]), PackedColorArray([top, top, bot, bot]))
	for i in 70:   # starfield — pure index arithmetic + the visual clock, so it never consumes a tick from the shared rr() stream the gameplay relies on
		var sx: float = wr.position.x + fposmod(float(i * 173 + 37), wr.size.x)
		var sy: float = wr.position.y + fposmod(float(i * 97 + 11) + bg_time * (2.0 + fposmod(float(i), 5.0)), wr.size.y * 0.72)
		var wsz: float = 1.0 + fposmod(float(i * 7), 1.6)
		var sa: float = 0.10 + fposmod(float(i * 13), 18) / 100.0 + 0.08 * sin(bg_time * 1.6 + float(i))
		draw_rect(Rect2(sx, sy, wsz, wsz), Color(0.20, 0.18, 0.15, maxf(sa, 0.05)))
	var pitch := CELL_W + 3.0
	var x0: float = (W - 12.0 * pitch + 3.0) / 2.0
	for row in 3:
		for col in 12:
			if (col + row * 5) % 7 == 2:   # a few gaps give the wall some rhythm
				continue
			var hex: String = MENU_PALETTE[(col * 3 + row * 5) % MENU_PALETTE.size()]
			var mx: float = x0 + col * pitch
			var my: float = FIELD_TOP + 26.0 + row * (CELL_H + 6.0)
			rrect_path(mx, my, CELL_W, CELL_H, 4.0, Color(hex, 0.85))
	rrect_path(W / 2.0 - 60.0, H - 44.0, 120.0, 16.0, 8.0, COLOR_SLOTS["white"])
	# an idle ball bouncing over the paddle — analytic ghost trail, zero per-frame bookkeeping
	var btx: float = W / 2.0 + sin(bg_time * 0.7) * 170.0
	var bty: float = H - 56.0 - absf(sin(bg_time * 1.9)) * 92.0
	for tk in range(6, 0, -1):
		var tt: float = bg_time - float(tk) * 0.05
		var tcol: Color = COLOR_SLOTS["white"]
		tcol.a = 0.03 + 0.045 * (6.0 - float(tk))
		draw_circle(Vector2(W / 2.0 + sin(tt * 0.7) * 170.0, H - 56.0 - absf(sin(tt * 1.9)) * 92.0), 3.0 + float(6 - tk) * 1.0, tcol)
	draw_circle(Vector2(btx, bty), 10.0, COLOR_SLOTS["white"])
	_draw_vignette(wr)

func _draw() -> void:
	if screen == "menu":
		_draw_menu_scene()   # the title scene fully replaces the frozen gameplay underneath
		return
	var font: Font = ThemeDB.fallback_font
	var shake_x: float = (rr() - 0.5) * state.shake if state.shake > 0.0 else 0.0
	var shake_y: float = (rr() - 0.5) * state.shake if state.shake > 0.0 else 0.0
	draw_set_transform(Vector2(shake_x, shake_y), 0.0, Vector2(1, 1))

	# background: cover-scaled PNG, or the default linear gradient — drawn across the WHOLE visible world, so expand-stretch windows (any aspect) never show dead space
	var wr := _world_rect()
	if bg_index >= 0:
		var tex = bg_images.values()[bg_index]
		var iw: float = tex.get_size().x
		var ih: float = tex.get_size().y
		var sc: float = max(wr.size.x / iw, wr.size.y / ih)
		var dw: float = iw * sc
		var dh: float = ih * sc
		draw_texture_rect(tex, Rect2(wr.position + (wr.size - Vector2(dw, dh)) / 2.0, Vector2(dw, dh)), false)
		draw_rect(wr, COLOR_SLOTS["dim_overlay"])
	else:
		var top := COLOR_SLOTS["grad_top"]
		var bot := COLOR_SLOTS["grad_bottom"]
		draw_polygon(PackedVector2Array([wr.position, Vector2(wr.end.x, wr.position.y), wr.end, Vector2(wr.position.x, wr.end.y)]), PackedColorArray([top, top, bot, bot]))
		for i in 24:   # drifting, twinkling starfield — gradient sky only; PNG backgrounds are busy enough already
			var sgx: float = wr.position.x + fposmod(float(i * 211 + 61), wr.size.x)
			var sgy: float = wr.position.y + fposmod(float(i * 149 + 17) + bg_time * (5.0 + fposmod(float(i * 31), 13.0)) * 0.45, wr.size.y * 0.86)
			var sgs: float = 1.0 + fposmod(float(i * 7), 2.4)
			var sga: float = 0.08 + 0.18 * (0.5 + 0.5 * sin(bg_time * 1.9 + float(i)))
			draw_rect(Rect2(sgx, sgy, sgs, sgs), Color(0.20, 0.18, 0.15, sga))

	# ball trails — fading ghosts kept under the bricks so gameplay stays readable (lava ghosts tint warm)
	for tr in state.trail:
		var fr: float = float(tr.life) / TRAIL_LIFE
		var tcol: Color = Color("#b8541c") if tr.hot else COLOR_SLOTS["white"]
		tcol.a = 0.16 * fr
		draw_circle(Vector2(tr.x, tr.y), 2.0 + (BALL_R - 2.0) * fr, tcol)

	# blocks
	for b in blocks_data:
		var t = BLOCK_TYPES[b.t]
		var col: Color = Color(b.color, 1.0)
		var bwv: float = bw(b)
		var bhv: float = bh(b)
		col.a = 0.85 if t.indestructible else 0.6 + 0.4 * (float(b.hp) / max(float(t.hp), 1.0))
		rrect_path(b.x, b.y, bwv, bhv, 4.0, col)   # flat ink field — the glassy top band is gone: one unified surface across every brick hue
		if t.stroke_alpha > 0.0:   # stroke-color alpha mirrors the globalAlpha lift before the canvas stroke
			var stroke_col: Color = t.stroke
			stroke_col.a = t.stroke_alpha
			rrect_path(b.x + 1, b.y + 1, bwv - 2, bhv - 2, 4.0, stroke_col, 2.0)
		if t.label != "" and not (["boss", "explode", "gold"].has(String(b.t))):
			draw_string(font, Vector2(b.x + bwv / 2.0 - 20.0, b.y + bhv / 2.0 + 7.0), t.label, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 18, COLOR_SLOTS["brown_label"])
		if t.indestructible:
			rrect_path(b.x + 3, b.y + 3, bwv - 6, 5.0, 2.0, COLOR_SLOTS["dark_white"])
		if String(b.t) == "explode":   # a red TNT stick, not a text asterisk
			draw_pixel_icon(b.x + bwv / 2.0, b.y + bhv / 2.0 - 1.0, TNT_ICON, Color("#c8402e"), 2.4)
		if String(b.t) == "gold":   # a glinting star + a travelling coin glint — this brick drops loot
			var gxp: float = b.x + 6.0 + fposmod(bg_time * 26.0 + b.c * 31.0 + b.r * 47.0, bwv - 12.0)
			draw_rect(Rect2(gxp, b.y + bhv * 0.58, 3.0, 3.0), Color(1.0, 1.0, 0.85, 0.55 + 0.35 * sin(bg_time * 9.0 + b.c)))
			draw_pixel_icon(b.x + bwv / 2.0, b.y + bhv / 2.0 - 1.0, GOLD_ICON, Color(0.98, 0.95, 0.84, 1.0), 2.4)   # cream star on gold — readable loot marker
		if String(b.t) == "boss":   # two rows tall, a big bone-white skull and a gold HP bar — deal with me now
			draw_pixel_icon(b.x + bwv / 2.0, b.y + bhv * 0.42, BOSS_ICON, Color("#d8c24a"), 3.0)
			var frac: float = clampf(float(b.hp) / maxf(float(t.hp), 1.0), 0.0, 1.0)
			var barw: float = bwv - 10.0
			rrect_path(b.x + 5.0, b.y + bhv - 9.0, barw, 4.0, 2.0, Color(0.12, 0.10, 0.08, 0.55))
			if frac > 0.0:
				rrect_path(b.x + 5.0, b.y + bhv - 9.0, barw * frac, 4.0, 2.0, Color("#d8c24a"))

	# lasers
	for l in state.lasers:
		draw_rect(Rect2(l.x - 2.0, l.y - 14.0, 4.0, 14.0), COLOR_SLOTS["glow_red"])

	# drops — bobbing pixel-art power-up sprites over a softly pulsing halo (same halo language as the balls)
	for d in state.drops:
		var p = POWERUPS[d.key]
		var bob: float = sin(bg_time * 3.0 + float(d.x) * 0.05) * 1.6
		var dyc: float = d.y + bob
		var halo: Color = p.color
		halo.a = 0.26 + 0.12 * sin(bg_time * 5.0 + float(d.x))
		draw_circle(Vector2(d.x, dyc), 16.0, halo)
		draw_pixel_icon(d.x, dyc, p.icon, p.color)

	# particles
	for p in state.particles:
		var pc: Color = Color(p.color, 1.0)
		pc.a = max(p.life / 0.4, 0.0)
		draw_rect(Rect2(p.x - 2.0, p.y - 2.0, 4.0, 4.0), pc)

	# shockwave rings — blasts and celebrations announce themselves with an expanding circle
	for bm in state.booms:
		var bp: float = clampf(float(bm.t) / float(bm.ttl), 0.0, 1.0)
		var bcol: Color = bm.color
		bcol.a = (1.0 - bp) * 0.85
		draw_arc(Vector2(bm.x, bm.y), float(bm.r0) + bp * 48.0, 0.0, TAU, 44, bcol, 1.0 + 3.2 * (1.0 - bp))

	# shield band (SHIELD active): a glowing floor line across the whole visible world
	if state.active.get("SHIELD", 0.0) > 0.0:
		var shy: float = H   # the design-space floor — expand-stretch keeps it flush with the screen bottom on widescreen windows
		var glow_sh: Color = Color(0.10, 0.32, 0.50, 0.22 + 0.10 * sin(bg_time * 6.0))
		draw_rect(Rect2(wr.position.x, shy - 12.0, wr.size.x, 16.0), glow_sh)
		draw_rect(Rect2(wr.position.x, shy - 3.0, wr.size.x, 3.0), Color(0.09, 0.28, 0.44, 0.92))

	# paddle (glow approximated with a halo — canvas shadows have no direct Godot equivalent)
	var glow_name: String = "glow_teal"
	if state.active.has("STICKY"): glow_name = "glow_teal"
	elif state.active.has("LASER"): glow_name = "glow_red"
	elif state.active.has("LAVA"): glow_name = "glow_lava"
	else: glow_name = "glow_blue"
	var glow_col: Color = COLOR_SLOTS[glow_name]
	glow_col.a = 0.35
	var sq: float = float(paddle.get("squash", 0.0))
	var pw: float = state.paddleW * (1.0 + sq * 0.10)
	var ph: float = PADDLE_H * (1.0 - sq * 0.25)
	var px: float = float(paddle.x) - (pw - state.paddleW) / 2.0
	var py: float = float(paddle.y) + (PADDLE_H - ph)
	rrect_path(px - 4.0, py - 4.0, pw + 8.0, ph + 8.0, 10.0, glow_col)
	rrect_path(px, py, pw, ph, 6.0, COLOR_SLOTS["white"])
	if ph > 8.0:
		rrect_path(px + 5.0, py + ph - 5.0, pw - 10.0, 4.0, 2.0, Color(0.28, 0.30, 0.28, 0.75))   # cool steel bottom edge

	# balls — squash & stretch along the flight vector: the faster it tears through the air, the more it elongates
	var molten: bool = state.active.get("LAVA", 0.0) > 0.0
	var fevered: bool = float(state.fever) > 0.0
	for b in state.balls:
		var sp: float = sqrt(b.vx * b.vx + b.vy * b.vy)
		var st: float = 0.0 if bool(b.stuck) else clampf((sp - BALL_BASE_SPEED) / maxf(BALL_MAX_SPEED - BALL_BASE_SPEED, 1.0), 0.0, 1.0) * 0.26
		var bang: float = 0.0 if bool(b.stuck) else atan2(b.vy, b.vx)
		draw_set_transform(Vector2(shake_x + b.x, shake_y + b.y), bang, Vector2(1.0 + st, 1.0 - st))
		if molten:   # the lava ball: glowing orange core with a hot ember highlight
			var lh: Color = Color("#b8541c")
			lh.a = 0.45
			draw_circle(Vector2.ZERO, 14.0, lh)
			draw_circle(Vector2.ZERO, BALL_R, Color("#a83c15"))
			draw_circle(Vector2(-3.0, -3.0), 3.5, Color("#c9971f"))
		else:
			var halo: Color = Color(0.72, 0.50, 0.15, 1.0) if fevered else COLOR_SLOTS["white"]
			halo.a = 0.4
			draw_circle(Vector2.ZERO, 13.0, halo)
			draw_circle(Vector2.ZERO, BALL_R, Color(0.23, 0.20, 0.16, 1.0) if fevered else COLOR_SLOTS["white"])
	draw_set_transform(Vector2(shake_x, shake_y), 0.0, Vector2(1, 1))

	# floating popups — rise & fade, over the field but under the HUD so text stays crisp
	for pp in state.popups:
		var pcol: Color = pp.color
		pcol.a = clampf(float(pp.ttl) / POPUP_LIFE, 0.0, 1.0)
		draw_string(font, Vector2(float(pp.x) - 80.0, float(pp.y)), String(pp.text), HORIZONTAL_ALIGNMENT_CENTER, 160.0, 15, pcol)

	# a barely-there paper-bright breath on every beat — the field taps along with the theme
	if beat_pulse > 0.0:
		draw_rect(wr, Color(0.98, 0.94, 0.82, 0.018 * beat_pulse))

	_draw_vignette(wr)

	if float(state.fever) > 0.0:   # FEVER heat — the whole field glows amber and breathes, and the tint dies away with the last second
		var fpha: float = 0.05 + 0.045 * sin(bg_time * 7.0)
		draw_rect(wr, Color(0.87, 0.47, 0.10, fpha * minf(1.0, float(state.fever) / 1.2)))

	# HUD — flat on the sheet: the score card and the lives pill are gone (they read as shadow boxes over paper); combo/fever keep their pills, LEVEL stays announced-not-printed
	var low_life: bool = int(state.lives) == 1   # last life: the lives text itself beats like a red panic heart
	var life_beat: float = 0.5 + 0.5 * sin(bg_time * 6.0)
	var lives_txt_col: Color = Color(0.62, 0.26, 0.22, 0.72 + 0.28 * life_beat) if low_life else COLOR_SLOTS["white"]

	# HUD — big score, small hi: a two-step hierarchy instead of two equal-weight lines
	draw_string(font, Vector2(16, 28), "SCORE " + str(state.score), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, COLOR_SLOTS["white"])
	draw_string(font, Vector2(16, 48), "HI " + str(state.high), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COLOR_SLOTS["dim_white"])
	draw_string(font, Vector2(200.0, 26), "LIVES " + "●".repeat(maxi(state.lives, 0)), HORIZONTAL_ALIGNMENT_RIGHT, 744.0, 16, lives_txt_col)
	if state.combo >= 3:   # combo pill — pulses on the music's beat, not a free-running sine
		var cpsz: int = 12 + int(3.0 * beat_pulse)
		rrect_path(W / 2.0 - 80.0, 4.0, 160.0, 22.0, 11.0, Color(0.97, 0.94, 0.88, 0.88))
		draw_string(font, Vector2(W / 2.0 - 76.0, 20.0), "COMBO ×" + str(state.combo), HORIZONTAL_ALIGNMENT_CENTER, 152.0, cpsz, Color("#8f5f1f"))
	if float(state.fever) > 0.0:   # FEVER pill — its border flares on the beat
		var fpulse: float = beat_pulse
		rrect_path(16.0, 54.0, 158.0, 22.0, 11.0, Color(0.35, 0.12, 0.0, 0.45))
		rrect_path(17.0, 55.0, 156.0, 20.0, 10.0, Color(1.0, 0.62, 0.15, 0.30 + 0.40 * fpulse), 1.5)
		draw_string(font, Vector2(20.0, 70.0), "FEVER ×2  " + str(int(ceil(state.fever))) + "s", HORIZONTAL_ALIGNMENT_CENTER, 150.0, 12, Color("#8a5a1d"))
	if bool(state.rush):   # gold rush pill — bottom-right: the top-left belongs to FEVER and the mobile pause button
		var rpulse: float = 0.5 + 0.5 * sin(bg_time * 10.0)
		var rby: float = H - 44.0
		rrect_path(W - 174.0, rby, 158.0, 22.0, 11.0, Color(0.35, 0.26, 0.0, 0.55))
		rrect_path(W - 173.0, rby + 1.0, 156.0, 20.0, 10.0, Color(0.95, 0.72, 0.10, 0.45 + 0.40 * rpulse), 1.5)
		draw_string(font, Vector2(W - 170.0, rby + 16.0), "GOLD RUSH ×3  " + str(int(ceil(state.rushTimer))) + "s", HORIZONTAL_ALIGNMENT_CENTER, 150.0, 12, Color(0.97, 0.93, 0.84, 1.0))
	if float(state.pressTimer) <= PRESS_WARN:   # the press is coming — a red countdown above the field
		var ppulse: float = 0.5 + 0.5 * sin(bg_time * 12.0)
		draw_string(font, Vector2(W / 2.0 - 90.0, 40.0), "PRESS IN " + str(maxi(0, int(ceil(state.pressTimer)))) + "s", HORIZONTAL_ALIGNMENT_CENTER, 180.0, 16, Color(0.62, 0.26, 0.22, 0.6 + 0.4 * ppulse))
	var ty: float = H - 14.0
	for k in state.active.keys():
		var p = POWERUPS[k]
		var c: Color = COLOR_SLOTS["hud_green"] if p.good else COLOR_SLOTS["hud_red"]
		draw_string(font, Vector2(16, ty), p.name + "  " + str(int(ceil(state.active[k]))) + "s", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, c)
		ty -= 14.0

	if state.flash > 0.0:
		draw_rect(wr, Color(0.20, 0.18, 0.15, 0.055 * float(state.flash)))   # pickup flash — the whole screen blinks
	# the paused field needs no drawn overlay: the pause MENU (a Control card with its own dim) sits right on top of it now
	if state.message != "":
		if state.msgPlain:   # powerup shout — no banner box, just black ink on the paper
			draw_string(font, Vector2(0.0, H / 2.0 + 12.0), state.message, HORIZONTAL_ALIGNMENT_CENTER, float(W), 34, COLOR_SLOTS["black"])
		else:
			banner(font, state.message)
	# the background's file name used to be printed top-right; players never asked for it, so it's gone — and papers rotate on their own now

	# ---------------- Mobile touch UI overlay ----------------
	if screen == "game" and not state.paused and _is_touch_device():
		_draw_touch_ui(font)
	
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1, 1))

func _draw_vignette(wr: Rect2) -> void:   # soft darkened frame that pulls the eye into the design field — half strength: on wide windows the sides used to go muddy, and players noticed
	var d := Color(0, 0, 0, 0.16)
	var z := Color(0, 0, 0, 0.0)
	var s: float = minf(130.0, wr.size.x * 0.10)
	var b: float = minf(90.0, wr.size.y * 0.12)
	var x0: float = wr.position.x
	var y0: float = wr.position.y
	var x1: float = wr.end.x
	var y1: float = wr.end.y
	draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x0 + s, y0), Vector2(x0 + s, y1), Vector2(x0, y1)]), PackedColorArray([d, z, z, d]))
	draw_polygon(PackedVector2Array([Vector2(x1 - s, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x1 - s, y1)]), PackedColorArray([z, d, d, z]))
	draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y0 + b), Vector2(x0, y0 + b)]), PackedColorArray([d, d, z, z]))
	draw_polygon(PackedVector2Array([Vector2(x0, y1 - b), Vector2(x1, y1 - b), Vector2(x1, y1), Vector2(x0, y1)]), PackedColorArray([z, z, d, d]))

func banner(font: Font, text: String) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 34).x + 48.0
	w = min(w, W)   # clamp so the rounded-rect arc centers stay inside the pill
	var col := COLOR_SLOTS["banner_overlay"]
	rrect_path(W / 2.0 - w / 2.0, H / 2.0 - 46.0, w, 72.0, 14.0, col)
	draw_string(font, Vector2(W / 2.0 - w / 2.0 + 24.0, H / 2.0 + 12.0), text, HORIZONTAL_ALIGNMENT_CENTER, w - 48.0, 34, COLOR_SLOTS["white"])

# rounded-rect fill/stroke — Path2D arcs approximate canvas arcTo
func rrect_path(x: float, y: float, w: float, h: float, r: float, col: Color, stroke_w: float = -1.0) -> void:
	var pts := PackedVector2Array()
	var centers: Array[Vector2] = [Vector2(x + w - r, y + r), Vector2(x + w - r, y + h - r), Vector2(x + r, y + h - r), Vector2(x + r, y + r)]
	var starts: Array[float] = [-PI / 2, 0.0, PI / 2, PI]
	for i in 4:
		for s in 7:   # sample each 90-degree corner arc; last arc closes back on the first point
			var a: float = starts[i] + PI / 2 * float(s) / 6.0
			pts.append(centers[i] + Vector2(cos(a), sin(a)) * r)
	if stroke_w > 0.0:
		draw_polyline(pts, col, stroke_w)
	else:
		draw_colored_polygon(pts, col)

# pixel-art power-up sprite stamped centered on (cx, cy): each char of the 13x9 grid is a PU_PIXEL square
# "." transparent · F fill · D dark edge · L light edge (light from top-left) · K ink · W paper-white glint
func draw_pixel_icon(cx: float, cy: float, rows: Array, col: Color, scale: float = PU_PIXEL) -> void:
	var dark: Color = col.darkened(0.45)
	var light: Color = col.lightened(0.35)
	var ink: Color = COLOR_SLOTS["white"]
	var glint := Color(1.0, 1.0, 0.85, 1.0)
	var y0: float = cy - rows.size() * scale / 2.0
	for r in rows.size():
		var row: String = rows[r]
		var x0: float = cx - row.length() * scale / 2.0
		for c in row.length():
			var px: Color
			match row[c]:
				"F": px = col
				"D": px = dark
				"L": px = light
				"K": px = ink
				"W": px = glint
				_: continue
			draw_rect(Rect2(x0 + c * scale, y0 + r * scale, scale, scale), px)

# ---------------- Boot ----------------
func _ready() -> void:
	for _i in 6:   # audio pool: enough simultaneous players for typical overlap, matches browser polyphony limits
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		audio_pool.append(pl)
	AudioServer.add_bus()   # appended after Master — add_bus() returns void in Godot 4, resolve the index via the bus count
	AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "Music")
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, "SFX")   # so buses land at indices 1/2 — always resolved via get_bus_index, never hardcoded
	for pl in audio_pool:
		pl.bus = "SFX"
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)
	music_player.finished.connect(_on_music_finished)
	music_player_b = AudioStreamPlayer.new()
	music_player_b.bus = "Music"
	add_child(music_player_b)
	music_player_b.finished.connect(_on_music_finished)
	load_settings()   # load + apply before the menu build so controls show the saved values
	apply_settings_at_boot()
	apply_display_stretch()   # scale the 960x640 design canvas into whatever window size the settings picked — a resolution change now scales the game itself
	get_window().close_requested.connect(_on_window_close)   # X / Alt-F4 mid-run still books the score — a closed app must never silently eat a run
	build_settings_menu()
	build_main_menu()
	build_leaderboard_panel()
	init_music()
	if bg_count() == 0: load_backgrounds()
	state.high = load_high()
	load_leaderboard()
	save_high()   # boot bank: every launch stamps both save files — user:// is guaranteed writable (4.7 data_paths docs), so "the save vanished" and "the save never ran" are now distinguishable by looking
	save_settings()
	apply_bg_setting()   # resolve auto-vs-pinned paper before the first level builds
	print("board: " + str(leaderboard.size()) + " run(s)  ·  high " + str(state.high) + "  ·  data " + OS.get_user_data_dir())   # boot line: proves where saves live and what was found there
	build_level()
	flash_message("Tap to launch" if _is_touch_device() else "Click / space to launch", 3.5)
	mouse_filter = MOUSE_FILTER_STOP   # keyboard reaches _input when this control is focused
	focus_mode = FOCUS_ALL
	if screen != "menu": grab_focus()   # at boot the main menu owns focus — Play is the focused button
	_center_menu_cards()
	call_deferred("_center_menu_cards")   # once the tree has laid out, re-pin against the final visible-world rect
