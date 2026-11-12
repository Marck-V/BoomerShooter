# Level 1 redesign brief

Goal: make `level_01_new` more fun to play and more distinct from room to room, without changing what level 1 is for.

## Fixed constraints (do not redesign these)

- Level 1 is the introduction. The player has **only the pistol** for the first half.
- The **shield is picked up about halfway** (`shield_pickup` at map origin 1408 7424 180). The grapple is taught right after it.
- The **shotgun is given after the boss** (`boss_reward`), so the player never uses it in this level.
- Enemy roster is horde enemies, ranged enemies and the `godot_boss`. No brute and no shielded enemies here, and no lightning gun or rifle, so do not tune encounters for them.
- Pistol upgrades (dead eye, piercing, lifesteal) exist, but the player may not have them yet. Design for the base pistol.

## Where the level lives

- Scene: `scenes/levels/level_01_new.tscn`, a `FuncGodotMap` with about 180 entities.
- The source is most likely `trenchbroom/maps/level_01.map` (a TrenchBroom map). Check that the scene's FuncGodotMap actually points at it before editing anything.
- `level_01_new.tscn` has **uncommitted edits from before this brief**. Do not commit that file unless the user says to.
- Any level-generation scripts go in `tools/levelgen/active/` and get deleted when a section is done.
- For testing enemies, use `scenes/test_scenes/test_room.tscn` and its `spawn()` / `spawn_horde()` / `clear_enemies()` helpers.
- The godot-ai MCP tools can open scenes, take editor screenshots, run the game and evaluate GDScript in the running game.

## Current layout (from the map's entities)

Rough order, by map coordinates (y increases along the path):

| # | Area | Contents |
|---|---|---|
| 1 | Start (192, 160) | player start |
| 2 | Arena 1 (y~960-1900) | 1 horde, then 3 horde behind a wave trigger, 2 pickups |
| 3 | Arena 2 (y~3000-3450) | 5 horde, 3 explosive barrels, 1 plain barrel, 4+ pickups, checkpoint |
| 4 | Arena 3 (y~4700) | 2 ranged, 1 horde, pickups |
| 5 | Arena 4 (y~6000-6300) | 4 ranged (2 on high ground, z97), 3 horde, barriers, pickups, checkpoint |
| 6 | Shield pickup (1408, 7424) | checkpoint, then an ambush of 3 ranged at y7680 |
| 7 | Grapple corridor (x2944-3712) | 3 grapple points at z352, hint trigger, 3 ranged at the end, checkpoints |
| 8 | Hub (x4224-4992, y6912-7808) | pickups, checkpoints, two key branches |
| 9a | North branch (y8576-9536) | 4 ranged, 4 horde, `level_key` |
| 9b | South branch (y5376-6144) | grapple climb to z896, `level_key` at (4800, 5440, 775), 4 ranged |
| 10 | Key door, boss (6528, 7296) | `godot_boss`, `boss_reward`, pickups |

Top-down it reads as boxy rooms joined by thin corridors, with a four-way hub near the end.

## What is good (keep)

- Arena 1 is a small, gentle start. Arena 2 introduces explosive barrels.
- The shield and grapple arrive mid-level with a hint trigger, not at the start.
- The south branch (vertical grapple climb, ranged enemies on ledges) is the best part.
- The hub lets the player pick the key order. Checkpoints are generous.

## Problems to solve (most important first)

1. **Repetition before the shield.** Arenas 1 to 4 all follow the same pattern: enter, wave trigger, locked doors, kill everything, doors open. With one weapon, encounter structure is the only variety. Vary how fights start and end (ambush from behind, trickle spawns, an objective other than kill-all, a fight that opens into a second space).
2. **Barrels are used once.** The pistol's strongest tool is the explosive barrel, and only arena 2 uses it. Use them again in at least one other pre-shield arena.
3. **Corridors are dead space.** Use them for pacing: a view into the next arena, a pickup, a quiet beat.
4. **Unverified:** shield-lesson quality. The 3-ranged ambush after the pickup is meant to teach blocking and parrying. Check the room has the cover and sightlines for that to work.
5. **Unverified:** the boss arena has to work with only the pistol and shield (4 pickups in the room). Check ammo flow and cover.

## Not yet known (confirm with the user first)

The user said level design is the thing bothering them most but has not said what specifically. Before changing anything, ask:

- Is the problem how the levels look, how they play, or how long they take to build?
- Is it level 1 specifically, or all levels?
- Which rooms feel worst when playing?

## Plan

**Phase 0: ground-level review (read-only).** Walk each room at player height with editor or game screenshots. Report scale against player speed, cover, sightlines, and which arenas feel like copies of each other. Confirm or correct problems 4 and 5 above. Deliverable: a short written review with screenshots, no map changes.

**Phase 1: encounter pass (smallest changes first).** Without changing room geometry, vary the arena 1 to 4 encounters: spawn timing and direction, one non-kill-all objective, barrels in a second arena, a pacing beat in the corridors. Deliverable: edited entities in `level_01.map`, re-imported, each arena playtested.

**Phase 2: layout changes (only if Phase 0 shows geometry is the issue).** Break the beads-on-a-string shape in the first half: an overlook onto a later arena, a loop back to an earlier area, or a shortcut that opens after a key fight. Keep the shield and grapple placement and the boss approach intact.

**Phase 3: shield lesson and boss check.** Tune the post-shield ambush and the boss arena for the pistol and shield.

## Done when

- Each pre-shield arena plays differently from the others.
- Barrels matter in at least two arenas.
- A fresh player gets the shield and grapple without a wall of text.
- Everything has been run in the game with screenshots, and nothing from the pre-existing `level_01_new.tscn` edits has been committed or lost.

## Out of scope

Weapon, upgrade and enemy changes; level 2 and the hand boss; the hover shield mode.
