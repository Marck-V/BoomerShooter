# BoomerShooter

A fast first-person shooter in Godot 4.7 (Forward Plus) with levels built in TrenchBroom through the FuncGodot plugin. The
README describes the game. This file is what to know before changing it: workflows, gotchas and standing decisions.

## Working with the user

- They edit the TrenchBroom maps and the level scenes by hand while you work. Never regenerate or overwrite a map or a
  level scene wholesale. Make surgical text edits (`tools/levelgen/editmap.py`), and re-read a file before editing it.
- If TrenchBroom has the map open it can save its stale copy back over your edit (this happened with a hint text). After
  editing a `.map`, tell them to reload it in TrenchBroom.
- Commit and push only when asked. When they say "commit and push everything", split it into small commits by topic.
- Commit messages start with `feat:`, `fix:`, `refactor:` or `chore:`.
- Test in the game before claiming something works (see Testing). Report what was and wasn't verified.

## Levels and TrenchBroom

- The `.map` in `trenchbroom/maps/` is the level. `scenes/levels/level_01_new.tscn` is the current level 1 (`level_01.tscn`
  is the old one), `level_02.tscn` is level 2.
- Coordinates: 32 map units = 1 m. Map x is Godot z, map y is Godot x, map z is up. A map point (20, -40, 0) is Godot
  (-40, 0, 20).
- Entity definitions live in `trenchbroom/entities/*.tres`, listed in `resources/trenchbroom/my_fgd.tres`. **TrenchBroom
  does not read the project's `trenchbroom/BoomerShooter_entities.fgd`.** It reads its own copy at
  `%APPDATA%\TrenchBroom\games\BoomerShooter\BoomerShooter.fgd`. When you add an entity or a property, update the `.tres`,
  `my_fgd.tres` and the project FGD, and merge the new definition into the `%APPDATA%` copy (keep its base classes such as
  `worldspawn`). Keep a backup of it first.
- Level scripts (`level_01_new.gd`, `level_02.gd`) rebuild the map from the `.map` when the level starts
  (`rebuild_at_runtime`) and bake the navigation mesh. The user prefers also pressing Build in the editor to see the level
  and place non-TrenchBroom things (the upgrade station, the teleporter), so the scenes contain baked map output and are
  large (about 900 KB). That is intended. A Build rewrites the generated resource names, so its diff is huge.
- Waves: an enemy with a `wave` property is taken out of the scene tree until its `wave_trigger` fires. Doors that are
  shut at level start leave a hole in the navigation mesh, so enemies never walk through them even once open: spawn them
  on the side they need to be on.
- Generator scripts in `tools/levelgen/active/` are temporary scaffolding. Delete a script once its section is done or the
  user starts hand-editing there. Re-running one overwrites hand edits. See `tools/levelgen/README.md`.

## Checkpoints and saves

- Saved runs identify map entities by class and position (`enemy_horde@36.0,0.0,66.1`), not by entity number, so editing the
  map doesn't break them. Moving an entity makes it look new. See `scripts/utilities/checkpoints.gd`.
- Waves that were cleared or started before a checkpoint are not brought back when the level reloads.
- Only the story profile writes `user://checkpoint.res`. Run tests on the dev profile (`GlobalVariables.set_profile(DEV)`)
  so you don't overwrite the user's real save.

## Testing

- The Godot editor is driven through the godot-ai MCP tools: `project_run`, `editor_manage` with `game_eval`,
  `editor_screenshot` and `logs_read`.
- Test enemies, bosses, weapons and effects in `scenes/test_scenes/test_room.tscn` (god mode, empty room). Don't make
  throwaway test scenes. Drive it from `game_eval` through the scene root: `spawn(scene, distance, angle, shielded)`,
  `spawn_horde()`, `clear_enemies()`, `set_frozen()`, and `damage_log`.
- `game_eval` quirks:
  - It times out after about 8 s, so split long tests.
  - A runtime error in an eval leaves the game stopped at a debugger break. Stop and relaunch.
  - `Input.action_press` from an eval is missed by `is_action_just_pressed`. Send an `InputEventAction` with
    `Input.parse_input_event`, or use the `input_sequence` op.
  - Read a node that may be freed only after `is_instance_valid`.
- To look at the level, add a `Camera3D` through `game_eval` and take a screenshot.

## Code conventions

- GDScript with tabs, typed where it is cheap, and comments that explain why.
- Working-tree files are CRLF (`.gitattributes` normalises). When editing programmatically, keep each file's existing line
  endings.
- Enemies extend `EnemyBase` (`scripts/enemies/enemy_base.gd`). Once an enemy has gone after the player it stays in the fight
  within `AGGRO_RANGE` and wakes allies it can see. Don't reintroduce going idle when the player leaves its vision.
- Mouse look is applied every rendered frame in `player.gd` (`_process` / `_update_view`) with the head detached from physics
  interpolation, not in the physics tick. Mouse input uses `screen_relative` scaled by `MOUSE_SCALE`.
- Key pictures for UI come from `assets/images/Input_Prompts` via `ControlsHint.key_icon(action)`, resolved from the input map.

## Design decisions to keep

- Level 1 is the introduction: the pistol only for the first half, the shield picked up about halfway (then the grapple), and
  the shotgun given after the Godot Man boss. Enemy roster there: grunts (`enemy_horde`), ranged enemies and the boss.
- The level 2 final boss is the giant hand. It has no grab and never summons enemies.
- In-game windows use the Windows 95 theme (`resources/themes/Windows95.tres`). The controls window at the start of level 1
  doesn't pause the game. The shield pickup's explanation window does.
