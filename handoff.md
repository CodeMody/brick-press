# Handoff — Breakout Godot Port (fresh-session start)

> **STATUS 2026-11-10: DONE.** Every step below was executed; headless harness = **31/31 ALL CHECKS PASSED** (exit 0), including both layout parity anchors. See README.md for how to run/test. What follows is the original handoff plan kept as a record (its file-status table below is now stale).

Working root: `C:\Users\CodeMody Laptop\Downloads\projects`
- `breakout-game/` — the original canvas game, **COMPLETE** (29/29 harness checks, both user-reported bugs fixed & verified: full pause freeze, level clears when the last block dies).
- `breakout-game-godot/` — the Godot 4 port, **IN PROGRESS**. This is the work remaining.

## Files status

| File | Status |
|---|---|
| `breakout-game-godot/project.godot` | ✅ on disk — 960×640 window, main scene `res://main.tscn` |
| `breakout-game-godot/main.gd` | ✅ on disk — full faithful port of `game.js` (746 lines) |
| `breakout-game-godot/tools/test_port.gd` | ✅ on disk — headless parity harness, 27 checks, layout anchors embedded |
| `breakout-game-godot/main.tscn` | ❌ MISSING — recreate (root Control, anchors full-rect 960×640, script = main.gd) |
| `breakout-game-godot/backgrounds/` | ❌ not copied — copy `bg1.png`–`bg5.png` + `manifest.json` from `breakout-game/backgrounds/` |
| `breakout-game-godot/README.md` | ❌ not written |

## Next steps, in order

1. **Write `main.tscn`** — root `Control` node with anchors preset full-rect (0,0,1,1), offsets 0/0/960/640, `script` = `res://main.gd`. No other children needed (audio pool is created in `_ready`).
2. **Cross-check the harness ↔ `main.gd` API** — the harness was written before the main.gd rewrite; fix whichever side is easier for these known suspects (read both files first):
   - harness calls `game.bg_label()` as a method, but main.gd has `var bg_label` + `func bg_label_text()` — harness expects a method named `bg_label()`; main.gd must add `func bg_label()` (and the var renamed, e.g. `bg_label_str`).
   - harness calls `game.bg_count()` — main.gd must have `func bg_count()` (currently planned; confirm).
   - harness calls `game.destroy_block(b, -1, false)` with 3 args vs main.gd's 2-param `destroy_block(b, fromExplosion)` — add a third `top_level: bool = true` param to main.gd, or drop the third arg in the harness.
   - harness uses `game.blockTypes` (lowercase) vs main.gd's `const BLOCK_TYPES` — rename one to match.
   - harness calls `game.blocks()`, `game.apply_powerup()`, `game.handle_mouse_click()`, `game.handle_key()`, `game.mouse_x`, `game.paddle`, `game.keys`, `game.state`, `game.bg_images`, `game.bg_index`, `game.override_rand` — confirm all exist on main.gd (they were part of the design; `has_method` asserts cover blocks/destroy_block/apply_powerup).
   - harness checks `state.message == null`-style semantics vs GDScript empty-string handling in main.gd — confirm `flash_message`/banner checks agree (JS `null` ↔ GDScript `""`).
   - `maxi` in harness → GDScript has `maxi` ✓ fine; `max` in main.gd returns Variant for Dictionary values ✓.
   - GDScript lambdas (`pick_type`/`in_shape`) + `match pattern:` must be real `func`/`match` syntax, not JS pseudo — verify syntax check passes.
   - Dictionary literals: GDScript wants `{ "c": c, "r": r, "t": t }`, not `{c = c, ...}`.
3. **Copy background assets** — `bg1–bg5.png` + `manifest.json` from `breakout-game/backgrounds/` into `breakout-game-godot/backgrounds/`.
4. **Run import once** (creates PNG import artifacts; harness `load()` calls need them):
   ```
   & 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe' --headless --path breakout-game-godot --import
   ```
   (Godot 4.7.2 stable is installed there, plus `_console.exe` variant. Godot needs full-access permission for this sandbox: `sandbox_permissions: "danger-full-access"`.)
5. **Run the harness** — expected verdict `ALL CHECKS PASSED` (27 checks):
   ```
   & 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe' --headless --path breakout-game-godot --user-data-dir breakout-game-godot/.test_userdata -s res://tools/test_port.gd
   ```
   `--user-data-dir` keeps `user://breakout_high.cfg` inside the workspace (sandbox-writable). The two layout anchor checks are hard parity gates against the JS game (below).
6. **Write README.md** — how to open in Godot, background slots (drop PNGs in `backgrounds/`; manifest merge works when run over HTTP, folder scan works everywhere including headless), controls table, headless test commands, known deviations.
7. **Present files** (`main.gd`, `main.tscn`, `project.godot`, `tools/test_port.gd`, README) and report to user. Manual check for the user afterwards: open the project in Godot and F5.

## Layout parity anchors (hard gates in the harness)

Both captured from the JS game (stable across runs — pure seeded generator, no Math.random influence):
- **LEVEL 1:** `.....nn.....;..n3nnn3nn..;tnntnn3nnnnt;..nnnnn3nn..`
- **LEVEL 2:** `.....nn.....;...tnnnnn...;..nnn3nnn3..;.nettnnnnnn.;enntnnnenn3n`
(`n`=normal `t`=tough `3`=tough3 `e`=explode `s`=steel `.`=empty; `;` between rows. Already embedded as consts in `tools/test_port.gd`.)

If an anchor check fails, suspect the mulberry32 emulation (32-bit wrap semantics on GDScript's 64-bit ints: `u32`/`s32`/`ushift` helpers, `s32(a*b)` for `Math.imul`) or the exact generator formulas in main.gd vs `breakout-game/game.js` (read it — it's the reference, keep it as-is).

## Port architecture (main.gd, as designed)

- Root `Control`, everything renders via `_draw()`; `_process` → `update(min(delta, 0.033))` + `queue_redraw()`.
- Constants verbatim from JS: PADDLE_BASE_W 120, PADDLE_H 16, BALL_R 8, BALL_BASE_SPEED 340, BALL_SPEED_STEP 6, BALL_MAX_SPEED 560, GRID_COLS 12, CELL_W 72, CELL_H 26, GAP 3, FIELD_TOP 70, DROP_CHANCE 0.12, DROP_SPEED 140; paddle speed 720; level seed `n*7919+13`; rows `min(4+n/2,9)`; hardChance `min(0.10+n*0.045,0.4)`; steelChance `n>=3 ? min(0.04+n*0.015,0.12) : 0`; explodeChance `n>=2 ? 0.06 : 0`; patterns list `rows/checker/pyramid/diamond/columns/clusters`.
- `update()` early-returns on `state.paused` (the JS bug-fix #1 ported); `destroy_block` gates drop-roll + level-clear on `fromExplosion < 0` top-level only (bug-fix #2 ported).
- Audio: on-demand WAV tones (square/saw/sine, exp env decay vol→0.001, 44100 Hz), pool of 6 `AudioStreamPlayer`s created in `_ready`; `pending_tones` real-time queue ticked BEFORE the pause-return in `update()` (JS `setTimeout` equivalence — fires even while paused, e.g. the level-clear chime's second tone at 120 ms).
- `localStorage` → `ConfigFile` `user://breakout_high.cfg` (section `default`, key `high`).
- Input: `_input` maps real events to the handlers; handlers `handle_key(name)` (lowercased; space→fire_laser, b→cycle bg, p→pause toggle when !over, r→restart when over, f→fullscreen), `handle_mouse_motion(x)` (sets `mouse_x`), `handle_mouse_click()` (over→restart else fireLaser). Tests drive handlers directly, mirroring the JS harness.
- Mouse: `mouse_x` stays null until an actual mouse-move event arrives (matches JS "only after first mousemove over canvas").
- `override_rand` test hook: `rr()` returns it when ≥ 0, else global `randf()`. Harness seeds global RNG with `seed(12345)` at start for determinism, sets `override_rand = 0.05` at the same position the JS harness forces `Math.random` (after launch/first-move checks, before MULTI section) — deterministic section is then fully reproducible.
- Blocks/paddle/HUD drawing uses `COLOR_SLOTS` Dictionary of `Color(r,g,b,alpha)` (GDScript cannot mutate canvas globalAlpha, so alpha is baked per-slot; stroke-color alpha lifted to full before stroke per JS behavior).
- Rounded rects via Path2D: 4 quarter arcs (`add_arc`), `point_count = 60` for smoothness; `draw_collected_path` for fill, `draw_path` for stroke.

## Documented deviations from the JS original (accepted, mention in README)

1. Font: Godot theme font (DejaVu-like), NOT canvas monospace — GDScript has no font family switch. Banner/measure approximates `measureText` via `get_string_size`.
2. Glow/shadowBlur approximated with halo layers (canvas shadows have no direct equivalent).
3. Boot selects `bg1` when textures are present, so the label reads `background: bg1.png` — GDScript cannot draw a null texture the way JS draws `undefined` on canvas (the default dark gradient remains as `bgIndex = -1` when no PNGs are found).
4. Manifest merge adds names already in the scan list as duplicates in JS (no dedup there); the port merges with dedup — count check expects 5 total.

## Original JS game reference (for feature parity)

Features in `breakout-game/game.js` (single file, read it when needed): mouse+A/D/arrows paddle, click/space launch, angle-based paddle bounce ±60°, speed ramp +6/paddle-hit (base 340/cap 560, +20/level), 3 lives, localStorage high score, P pause, R restart, F fullscreen, B next background, WebAudio beeps, shake+particles. Block types: normal hp1/10pts cycling palette, tough hp2/25, tough3 hp3/40, explode hp1/30 chain-kills 3×3 incl. steel, steel indestructible/5pts (laser+explosions only). 8 powerups: MULTI +2 balls, EXPAND 15s, SHRINK bad 10s, SLOW 0.65× 12s, FAST bad 1.5× 10s, LIFE, LASER 12s fire-on-click, STICKY 15s; drop chance 12%, bad pool only after level 1. Seeded levels `mulberry32(n*7919+13)` → generator-only (no global RNG), hence stable anchors.

Bundled runtimes for the original's tools (if ever re-run): node `C:\Users\CodeMody Laptop\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe` runs `tools/test_harness.js` (19→29 checks, ALL PASSED) and `tools/gen_backgrounds.py` runs with `C:\Users\CodeMody Laptop\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe` (Pillow 12.3.0), both from the `breakout-game/` dir.

## Session-mechanics notes

- Godot CLI needs `danger-full-access` sandbox permission in this environment (approval prompt asks once; subsequent calls in-session are covered).
- If the harness reports parse errors, GDScript is strict about: inner-class member access, lambda syntax, `match`, Dictionary literal keys, typed var inference for Variant (`var t = BLOCK_TYPES[...]` fine).
- Headless frame pumping in the harness uses `await process_frame`; total runtime ≈ 10–15 s (~750 frames).
- Do NOT reformat `breakout-game/game.js` — it is the parity reference.
