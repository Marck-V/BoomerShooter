"""Builds trenchbroom/maps/level_01.map: the true level 1, act 1 (pistol only), and a stub for what follows.

Run from the project root:  python tools/levelgen/active/level_01_act1.py

This script owns the whole map for now, so running it again overwrites everything (including hand edits made in
TrenchBroom). When act 1 is done, commit the map and delete this script (see tools/levelgen/README.md).

The walk, all on one floor (z = 0) except the platform in the barrel hall. All positions in meters, x east, y north:
  Spawn      12 x 12 m room. The player faces north up the corridor.
  Corridor   24 m long. One lone grunt walks down it at the player: the first fight is one against one.
  Yard       28 x 28 m with four pillars for cover. Walking in shuts the door behind you (wave "yard"): 3 grunts.
  Passage    20 m corridor with the yard's exit door at its south end.
  Barrel hall  36 x 28 m with a raised platform in the north-west and a cluster of explosive barrels. Walking in shuts
             the door behind you (wave "hall"): 5 grunts. The platform holds ammo and points; the barrels teach that
             shooting one near the grunts is the better plan.
  Exit       corridor with a checkpoint, then a placeholder room where act 2 will go.
"""
TEXTURES = "Kenney prototype textures (Dark set, texture_01 to 09) until real ones are chosen"
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from mapgen import MapBuilder, TileGrid, m

MAP = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "trenchbroom", "maps", "level_01.map"))

FLOOR = "world/texture_08"
WALL_A = "world/texture_01"
WALL_B = "world/texture_02"
WALL_C = "world/texture_06"
CEILING = "world/texture_09"
PILLAR = "world/texture_04"
RAMP = "world/texture_05"
DOOR = "world/texture_07"
CLIP = "special/clip"

CELL = 4.0
CORRIDOR_HEIGHT = 4.0   # doors slide down 4.2 m, so a corridor door is as tall as the corridor
ROOM_HEIGHT = 8.0
PLATFORM = 2.0          # height of the platform in the barrel hall

b = MapBuilder()
g = TileGrid(b, cell=CELL)

# --- Rooms and corridors (cell coordinates; one cell is 4 m) ---
g.add(0, 0, 2, 2, ceiling=6.0, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)                 # spawn
g.add(1, 3, 1, 8, ceiling=CORRIDOR_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)     # corridor
g.add(-2, 9, 4, 15, ceiling=ROOM_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_B, ceiling_tex=CEILING)      # yard
g.add(1, 16, 1, 20, ceiling=CORRIDOR_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)  # passage
g.add(-3, 21, 5, 27, ceiling=ROOM_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_C, ceiling_tex=CEILING)     # barrel hall
g.add(-3, 24, -1, 27, floor=PLATFORM, ceiling=ROOM_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_C, ceiling_tex=CEILING)  # platform
g.add(1, 28, 1, 31, ceiling=CORRIDOR_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)  # exit corridor
g.add(-1, 32, 3, 35, ceiling=6.0, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)             # placeholder for act 2
g.build()


def box(x0, x1, y0, y1, z0, z1, tex, comment=""):
    b.box(m(x0), m(x1), m(y0), m(y1), m(z0), m(z1), tex, comment)


def entity(classname, x, y, z=0.0, **properties):
    b.entity(classname, m(x), m(y), m(z) + 1, **properties)


def door(x0, x1, y, wave, starts_open):
    """A door across a corridor, 0.5 m thick, from y to y + 0.5."""
    b.brush_entity("locked_door", [(m(x0), m(x1), m(y), m(y + 0.5), m(0), m(CORRIDOR_HEIGHT), DOOR)],
                   wave=wave, starts_open=starts_open)


def trigger(x0, x1, y0, y1, wave, z1=4.0):
    b.brush_entity("wave_trigger", [(m(x0), m(x1), m(y0), m(y1), m(0), m(z1), CLIP)], wave=wave)


# --- Ramp up to the platform (south face of it, rising north) ---
b.ramp(m(-12), m(-8), m(88), m(96), m(0), m(PLATFORM), "+y", RAMP, "platform ramp")

# --- Pillars in the yard ---
for px, py in ((0.0, 46.0), (12.0, 46.0), (0.0, 54.0), (12.0, 54.0)):
    box(px - 1.0, px + 1.0, py - 1.0, py + 1.0, 0.0, ROOM_HEIGHT, PILLAR, "pillar")

# --- Player ---
b.entity("info_player_start", m(6.0), m(5.0), m(0) + 1, angle=90)

# --- The first fight: one grunt in the corridor, awake from the start ---
entity("enemy_horde", 6.0, 30.0)

# --- Yard ---
door(4.0, 8.0, 35.5, "yard", 1)       # entrance: shuts behind the player when the wave starts
door(4.0, 8.0, 64.0, "yard", 0)       # exit: opens when the wave is dead
trigger(0.0, 12.0, 38.0, 40.0, "yard")
for ex, ey in ((-4.0, 58.0), (8.0, 60.0), (17.0, 58.0)):
    entity("enemy_horde", ex, ey, wave="yard")
entity("pickup", -6.0, 42.0, 0.8, type="Ammo", weapon_id="pistol")
entity("pickup", 18.0, 40.0, 0.8, type="Health")

# --- Barrel hall ---
door(4.0, 8.0, 83.5, "hall", 1)
door(4.0, 8.0, 112.0, "hall", 0)
trigger(0.0, 12.0, 86.0, 88.0, "hall")
for ex, ey in ((-4.0, 100.0), (6.0, 106.0), (14.0, 104.0), (18.0, 96.0), (10.0, 108.0)):
    entity("enemy_horde", ex, ey, wave="hall")
for bx, by in ((12.0, 98.0), (14.0, 98.0), (13.0, 100.5)):
    entity("explosive_barrel", bx, by)
entity("barrel", 20.0, 92.0)
entity("pickup", -8.0, 108.0, PLATFORM + 0.8, type="Ammo", weapon_id="pistol")
entity("pickup", -4.0, 108.0, PLATFORM + 0.8, type="Points")
entity("pickup", -8.0, 104.0, PLATFORM + 0.8, type="Points")
entity("pickup", 20.0, 88.0, 0.8, type="Health")

# --- Exit: a checkpoint in the corridor, then the placeholder room ---
b.brush_entity("checkpoint", [(m(4.0), m(8.0), m(120.0), m(121.0), m(0), m(CORRIDOR_HEIGHT), CLIP)])

b.write(MAP)
print("wrote", MAP, "-", b.brush_count, "brushes,", len(b.entities), "entities")
