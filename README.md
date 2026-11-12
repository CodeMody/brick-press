# Breakout — Godot 4 port

Faithful port of the browser version of this game — **the browser original is retired**; the layout anchor constants in `tools/test_port.gd` are now the standalone source of truth (keep them byte-identical). Same physics, same constants, same seeded levels — both layout anchors verified by the headless harness.

## Run

Open `project.godot` in **Godot 4.7+** (tested on 4.7.2 stable) and press F5, or:

```
Godot_v4.7.2-stable_win64.exe --path .
```

Boots into the **main menu** (a full-screen title scene — the game's gradient sky, a drifting starfield, a decorative brick wall and an opaque card with Play / Settings / Leaderboards / Quit, with an idle ball bouncing over the paddle); default window 1280×720 (windowed). The game canvas is a fixed 960×640 design space that Godot scales to fill any window size (`window/stretch/mode="canvas_items"`, `aspect="expand"` — the visible world grows past 960×640 on windows wider than 3:2 instead of showing letterbox bands, and the game draws its background across the whole visible world). 4.7.2 removed the old `content_scale_offset`, so centering of the design space is done in `apply_display_stretch()`/`_center_content()` via the public `Viewport.canvas_transform`. Everything renders through `_draw()` on the root Control; no scene-tree game objects.

## Controls

**Main menu** — click **Play** / **Settings** / **Quit** (or **Tab** to move focus, **Space**/**Enter** to activate). The game behind the menu is fully frozen. **S**/**Esc** also opens the settings overlay directly from the main menu.

**In game:**

| Input | Action |
|---|---|
| A/D or ← / → | paddle movement — **keyboard-only by design** (~820 px/s; the mouse used to steer it but accidental bumps were worse) |
| Mouse click | launch ball · fire laser (when LASER active) · menu buttons work as usual |
| Space | launch ball (also activates focused menu buttons) |
| **Esc** | **the only menu key** — in game it opens *the* menu (a full freeze: nothing moves, no lives drain) which doubles as settings + quit sheet; from the main menu it opens Settings; it also dismisses the Leaderboards card |
| R | restart (after game over) |
| F | toggle fullscreen |
| B | cycle background |

The field stays clean — no permanent hint bar, no level plate, no background filename in the corner. **Esc**'s sheet carries it all: `PAUSED` title, a run line (`LEVEL 3 · SCORE 1250 · LIVES ●●●`), one control line, the settings controls, and a way out with one click: **Resume · Quit to menu · Quit game** (all three book an unrecorded run before leaving).

## Gameplay

- Blocks: normal (10 pts), tough ×2 (25), tough ×3 (40), **TNT (30, a real domino chain — see below)**, **gold (★, 50 pts, always drops a capsule — positional veins from level 2 on; a coin glint sweeps across them)**, steel (indestructible by ball — dies to laser/explosions/lava only, 5 pts).
- **TNT domino waves**: a bomb hit doesn't just clear a 3×3 patch in one tick anymore — it detonates with a **shockwave ring**, screen shake and a `BOOM! +N` popup; neighbour blocks in the blast radius are chain-killed instantly (**steel included**), neighbouring *bombs* get a lit **fuse (~0.13 s)** and pop on their own beat with their own blast, so a stored line of TNT topples like dominoes. Each deeper wave pays a growing **wave bonus** (`+10 × depth`). If the chain kills the *last* block, the level still clears — the clear check runs on every destruction and every frame, closing the old gap where a wave could empty the field unnoticed.
- **FEVER mode**: a **10-combo** (10 consecutive kills without touching the paddle) ignites **FEVER** — 8 seconds of **×2 scoring** on everything: the field glows with a breathing amber tint, the ball's trail runs warm, and a pulsing `FEVER ×2 Ns` pill counts the clock down under the score plate. Any kill while burning **re-lights the clock to full**; when it finally dies you collect a **+100 parting bonus** with a popup and a last flare. Losing the ball (or the level) snuffs it out.
- **Level clear fanfare**: clearing a level now fires a three-note fanfare with a bright top note, a white flash, a heavier shake, a paddle squash and a white shockwave ring under the paddle, and `LEVEL CLEAR +100` floats up — the moment feels as big as it is.
- **12 level layouts** drawn by seed: rows, checker, pyramid, diamond, columns, clusters, zigzag, arch (converging portal walls), castle (battlement + corner towers), pillars (colonnade + lintel), crossfire (giant X), sieve (punched field).
- 10 powerups, 12 % drop chance: MULTI, EXPAND, SHRINK(bad), SLOW, FAST(bad), LIFE, LASER, STICKY, LAVA, SHIELD — the bad pool only appears from level 2 on.
- **LAVA (L, 10 s)**: the ball turns molten — it **burns straight through** every block, *steel included* (no bounce — it keeps its course, melting a tunnel), and laser bolts also vaporize steel, so the annoying metal rows in later levels finally clear.
- **SHIELD (G, 8 s)**: an energy floor glows across the whole bottom — falling balls bounce off it instead of eating a life (a pulsing cyan band + soft hum while active).
- **Combos**: every consecutive block killed *without touching the paddle* climbs a `COMBO ×N` chain (pulsing pill top-center, in the slot the level plate used to own); every 4-chain step pays a rising bonus (`+50 × tier`, tier capped at ×5) with a floating popup + jingle. Landing on the paddle resets the chain.
- **Wide-field play**: with expand-stretch the visible world is wider than the 960 design space on any window wider than 3:2 — the **side walls and paddle track the real visible edges**, so the paddle reaches both screen corners and no ball ever hides in a margin.
- **Juice**: fading ball trails (warm-tinted while molten or in FEVER), floating score popups, pickup screen flash, paddle squash + steel-shine bottom edge, **ball squash-&-stretch — the ball elongates along its flight vector the faster it flies**, glassy brick highlight bands, a slow drifting/twinkling starfield behind the gradient sky, bobbing capsules with pulsing halos, a soft vignette over the whole field, and a **heartbeat pulse on the lives pill when it's your last life**. The title scene lives too: drifting stars and an idle ball bouncing over the paddle with a ghost trail.
- **Music**: the pack ships three generated chiptune loops — **Neon Corridor** (`neon_corridor.wav`, 41 s, 140 BPM, E minor), **Starlight Patrol** (`starlight_patrol.wav`, 45 s, 128 BPM, G minor, hymn-like) and **Circuit Sunset** (`circuit_sunset.wav`, 38 s, 152 BPM, A minor, thin buzzy lead) — one shared NES stack (square lead + arpeggio + triangle bass + noise drums) composed by `tools/compose_music.py`, which regenerates all three byte-deterministically. They play in seeded-shuffle order (the manifest's `"shuffle"`), so the theme never repeats back-to-back. The playlist autoplays at boot through the **Music** bus, so the Settings music slider controls it live; drop more `.ogg/.mp3/.wav` files into `music/` and the playlist grows. Two belt-and-braces details for **exported builds**: a Godot 4.7 PCK does not list the source audio file by name — only its import artifact + `.import` sidecar — so the folder scan recognizes sidecars too, and `load()` falls back to the sidecar's stored artifact when the plain path misses. The game prints a one-line music/bg load report to stdout at boot (visible when launched from a console) — handy when a build sounds mysteriously silent; `tools/pack_probe.gd` is a standalone inspector for the same mystery.
- **Local leaderboard**: every finished run lands on the board — game over, Quit to menu / Quit game, **even closing the window mid-run** (the X/Alt-F4 books the pending score before the app dies, so scores can't silently vanish anymore). The best **8** live in the same `user://breakout_high.cfg` (`[default] high` + a `[board]` section, rewritten whole so the two can never drift apart). The main menu's **Leaderboards** button opens a submenu card — the same modal pattern as Settings — listing all saved runs (score · level · date, best in gold), dismissed by Esc or Close. Levels announce themselves too: each new level shows a brief **LEVEL N** title card over the field, and the number then lives quietly in the pause sheet (no permanent HUD plate).
- Levels are generated from the seed `level*7919+13` with an exact mulberry32 emulation — layouts match the JS game exactly (level 2+ paints positional gold veins onto normal blocks afterwards — the rule never consumes the seeded rng, so the anchors stay valid).
- High score persists to `user://breakout_high.cfg`.

## Backgrounds (PNG slots)

Drop PNGs into `backgrounds/` (named or listed in `backgrounds/manifest.json`). The folder is scanned alphabetically at boot and the manifest merges extra names; **B** cycles through them (first press shows `bg1.png`), and the Settings panel has a **Background** picker (item 0 = the default gradient). To add a background while the game runs: copy the PNG into `backgrounds/`, focus the Godot editor once so it imports the file, then re-open the Settings menu — the picker rescans every time it opens.

The shipped set (`bg1`–`bg5`: starfield, *Amethyst Cathedral* — deep purple night with soft light shafts, replacing the player-rejected "Dusk Horizon" sunset, aurora, nebula, moonlit sea) was generated procedurally — `tools/paint_bgs.py` (bundled-Python, numpy+Pillow) repaints `bg2`–`bg5` in one go; `bg1` is hand-kept.

Documented deviations from the JS original (accepted):
1. Font is the theme default (DejaVu-ish), not browser monospace — GDScript has no font-family switch; banner width uses `get_string_size`.
2. `shadowBlur` glow is approximated with halo layers.
3. High-score storage is `ConfigFile` under `user://` (browser localStorage equivalent).

## Main menu, Settings, Music

**Main menu** — boots to **Play / Settings / Leaderboards / Quit** (Play wears the accent blue; the rest are ink-navy pills). The whole game is frozen behind the menu (the same full-freeze rules as pause); the HUD hint timer only starts on Play. **Play** starts a run (from a finished game, Play = new run). **Settings** opens the settings sheet on top of the menu — **Back to menu** lands back on the menu. **Leaderboards** opens the saved-runs card (Esc/Close dismisses; the two submenus never stack). **Quit** closes the app.

**Settings — same sheet, two faces**: opened in game it's the pause menu (Paused + run info + control line + Resume / Quit to menu / Quit game); opened from the menu it's plain Settings (Back to menu). **Esc** toggles whichever face fits the moment. — Resolution: **1280×720 (720p) / 1920×1080 (1080p) / 2560×1440 (1440p)** — the fixed 960×640 game canvas scales + letterboxes into the window at any size; Fullscreen; **SFX volume** and **Music volume** sliders (0–100, applied live to their audio buses); Background picker. The game stays fully frozen while the sheet is open. Older saved sizes (960×640, 1280×800, …) migrate to 1280×720 on load.

**Music** — the pack ships three generated chiptune loops (see the Gameplay section); add your own alongside them. Drop `.ogg` / `.mp3` / `.wav` files into `music/`, focus the editor once (or `--import`) so Godot imports them, and re-open the Settings menu — playback rescans and starts picking up new files. `music/manifest.json` controls the playlist: `"music"` names merge with the folder scan (deduped), `"shuffle"` orders playback with the game's seeded RNG, `"loop"` decides whether playback continues past the last track. An empty folder means a silent boot (no crash).

**What persists** (`user://` on Windows = `%APPDATA%\Godot\app_userdata\Breakout Godot\`) — `user://breakout_settings.cfg` (section `[settings]`): `sfx_vol`, `music_vol` (linear 0–1), `fullscreen`, `size`. The windowed `size` stays saved even while fullscreen is on (the size selector is disabled meanwhile). Audio runs on three buses: Master + `Music` + `SFX` — the SFX tone pool routes to SFX, the music player to Music; volumes map linear 0–1 → bus dB and 0 = muted. Defaults: SFX 1.0, Music 0.5.

## Headless test harness

Mirrors the JS harness (order-for-order, incl. the main-menu flow, the content-scaling settings, the keyboard-only paddle, the shipped music set and the expansion-pass checks for gold/shield/combo/trail/burn-through) plus the two cross-engine **layout parity anchors** (hard gates), and closes with the **Excitement pass** (FEVER ignition at combo 10, clock re-light, ×2 payouts proved via a steel clink so nothing muddies the delta, expiry bonus + popup, and the full TNT domino choreography: bomb detonates, neighbour stands with a lit fuse, the 3×3 chain-kills steel, shockwave ring + shake spawn, payouts land, the fuse pops on its beat and its wave takes the next block, and an emptied field auto-clears even when the wave lands the final blow) followed by the **menu pass**: three-track music set, leaderboard ranking / trimming / scoreless skip / cfg round-trip, the unified Esc sheet's two faces (Paused with the quit row vs Settings with Back to menu), the leaderboard submenu's open/dismiss/modal-exclusivity rules, the brief LEVEL title card, and the close-requested hook that books a pending run before the app dies. Run from the parent folder:

```
"C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path breakout-game-godot --import
"C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path breakout-game-godot -s res://tools/test_port.gd
```

Expected verdict: `ALL CHECKS PASSED` (exit 0). Notes:

- Frame pumping is real-time, so time-sensitive checks are qualitative (mirroring the JS harness); only the anchors and state machines are exact. The harness wipes `user://breakout_high.cfg` at start for a deterministic storage state.
- **Godot 4.7 has no `--user-data-dir` CLI flag** — it parses but does nothing (probed against `--help` and a write-and-see run). So `test_port.gd` and `shot_on_boot.gd` flip `application/config/use_custom_user_dir` themselves at the top of `_initialize`: dev-run `user://` lands in `%APPDATA%\Breakout Godot\` instead of the game's own `%APPDATA%\Godot\app_userdata\Breakout Godot\`. Before that, every harness wipe silently deleted the *player's* board — the dev tool IS the save data's landlord here, and it used to squat.
- The two `ObjectDB instances leaked at exit` warnings are cosmetic (audio pool alive when the harness calls `quit()`).
- `tools/shot_on_boot.gd` is a dev-only tool: it boots the game in a real window, snaps the rendered viewport at eleven UI states (menu / leaderboard submenu / gameplay / lava / combo+shield "juice" shot / background showcase / the replaced bg2 / FEVER mode / live TNT blast / the unified Paused sheet / Settings face) into `.shots/`, and exits — used to verify visuals without guessing. Each snap calls `RenderingServer.force_draw()` first: a background window throttles to ~1 fps on some drivers and the swapchain image would otherwise lag behind the scripted state. (`tools/` is excluded from exports.)

Last full run: **90/90 ALL CHECKS PASSED** (2026-11-12).

## Export — Windows exe

`build/Breakout.exe` — one self-contained file (engine template + game scripts + backgrounds + manifests + icon all embedded via `embed_pck`; x86_64). Re-export from the parent folder:

```
"C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" --headless --path breakout-game-godot --export-release "Windows Desktop" "$PWD\breakout-game-godot\build\Breakout.exe"
```

The preset lives in `export_presets.cfg` (preset **Windows Desktop**): `tools/`, `.test_userdata/` and `.dev_userdata/` are excluded from the pack, the app/window icon is `icon.png`, and the template paths are pinned via `custom_template/*` (below).

**Export templates location** — the Windows templates of Godot **4.7.2.stable** (downloaded from the official GitHub release, sha256-verified) are installed beside the editor binary in **`C:\Program Files\Godot\export_templates\4.7.2.stable\`**. Godot's automatic lookup only checks the user-data dir, so `%APPDATA%\Godot\export_templates\4.7.2.stable` is a **junction** pointing at that folder — exports from the editor GUI work without any setup, and there is a single copy on disk.

Note: the drop-in `music/` + `backgrounds/` workflow is an editor-side feature — an exported exe ships whatever those folders contained at export time. To put different music/backgrounds into the build, add the files in the editor and re-export.
