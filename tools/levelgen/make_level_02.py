"""Generates trenchbroom/maps/level_02.map.

Run from the project root:  python tools/levelgen/make_level_02.py

Flow: quiet start room -> winding hallway with melee enemies -> big open room. The big room has a
lower floor with melee enemies and a gallery on each side, reached by a long ramp, where ranged enemies wait.
Those enemies are a wave: they spawn in when the player steps through the trigger just inside the room, and the
exit door on the far wall stays shut until all of them are dead. It leads into a second hallway.

Layout is on a 4 m grid (cell coordinates), north is +Y. Sized for the player: single jump ~1.6 m,
double jump ~3.2 m, dash ~5 m. Hallways are 4 m wide because enemies path with a 1 m radius.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mapgen import MapBuilder, TileGrid, m

FLOOR = "world/texture_15"
WALL = "world/texture_14"
HALL_WALL = "world/texture_04"
RAMP = "world/texture_10_stairs"
COVER = "world/texture_04"
PILLAR = "world/texture_01"

b = MapBuilder()
grid = TileGrid(b)
cell = grid.cell

GALLERY_H = 5.0     # height of the side galleries (above a double jump, so they need the ramps)
ROOM_WALL_H = 12.0

# --- Start room: 12 x 12 m, enclosed, no enemies
grid.add(0, 0, 2, 2, floor=0.0, ceiling=5.0, wall_tex=WALL)

# --- Winding hallway (4 m wide, 4 m high)
HALL = [(1, 3), (1, 5), (5, 5), (5, 8), (2, 8), (2, 11)]
grid.path(HALL, floor=0.0, ceiling=4.0, wall_tex=HALL_WALL)

# --- Big open room: x cells -2..5 (32 m), y cells 12..21 (40 m), open to the sky
ROOM_X0, ROOM_X1, ROOM_Y0, ROOM_Y1 = -2, 5, 12, 21
GALLERY_Y0 = 15                                     # galleries start here; the ramps run before it
grid.add(ROOM_X0, ROOM_Y0, ROOM_X1, ROOM_Y1, floor=0.0, wall_height=ROOM_WALL_H, wall_tex=WALL)
for gx0, gx1 in ((-2, -1), (4, 5)):
    grid.add(gx0, GALLERY_Y0, gx1, ROOM_Y1, floor=GALLERY_H, wall_height=ROOM_WALL_H, wall_tex=WALL, floor_tex=FLOOR)
# --- Exit hallway beyond the north wall (starts at the exit door)
EXIT_HALL = [(2, 22), (2, 24), (7, 24)]
grid.path(EXIT_HALL, floor=0.0, ceiling=4.0, wall_tex=HALL_WALL)
grid.build()

# Ramps up to each gallery, along the outer walls (rise 5 m over 12 m, about 23 degrees)
ry0, ry1 = m(ROOM_Y0 * cell), m(GALLERY_Y0 * cell)
for x0, x1 in ((-2 * cell, 0.0), (4 * cell, 6 * cell)):
    b.ramp(m(x0), m(x1), ry0, ry1, 0, m(GALLERY_H), "+y", RAMP, "gallery ramp")

# Low rails along the inner edge of each gallery
rail_y0, rail_y1 = m(GALLERY_Y0 * cell), m((ROOM_Y1 + 1) * cell)
b.box(m(-0.5), 0, rail_y0, rail_y1, m(GALLERY_H), m(GALLERY_H + 1.2), COVER, "left rail")
b.box(m(16.0), m(16.5), rail_y0, rail_y1, m(GALLERY_H), m(GALLERY_H + 1.2), COVER, "right rail")

# Cover on the lower floor: two low walls and two pillars
b.box(m(5.0), m(11.0), m(64.0), m(65.0), 0, m(1.2), COVER, "low wall")
b.box(m(5.0), m(11.0), m(74.0), m(75.0), 0, m(1.2), COVER, "low wall")
b.box(m(2.0), m(4.0), m(69.0), m(71.0), 0, m(4.0), PILLAR, "pillar")
b.box(m(12.0), m(14.0), m(69.0), m(71.0), 0, m(4.0), PILLAR, "pillar")

WAVE = "arena"   # name that ties the room's enemies, trigger and exit door together

# --- Entities (z is feet height; +1 unit keeps them off the floor)
FEET = 1


def at(cx, cy):
    return grid.center(cx, cy)


sx, sy = at(1, 0)
b.entity("info_player_start", m(sx), m(sy) + m(1), FEET, angle=90)

# Hallway melee enemies, one per straight section and corner
for cx, cy in ((3, 5), (5, 6), (4, 8), (3, 8), (2, 10)):
    x, y = at(cx, cy)
    b.entity("enemy_horde", m(x), m(y), FEET)

# Lower floor melee enemies
for x, y in ((6.0, 56.0), (10.0, 56.0), (8.0, 69.0), (5.0, 80.0), (11.0, 80.0)):
    b.entity("enemy_horde", m(x), m(y), FEET, wave=WAVE)

# Ranged enemies on the galleries
for x, y in ((-4.0, 70.0), (-4.0, 80.0), (20.0, 70.0), (20.0, 80.0)):
    b.entity("enemy_ranged", m(x), m(y), m(GALLERY_H) + FEET, wave=WAVE)

# Pickups
hx, hy = at(5, 7)
b.entity("pickup", m(hx), m(hy), m(0.8), type="Health")
sx2, sy2 = at(2, 9)
b.entity("pickup", m(sx2), m(sy2), m(0.8), type="Ammo", weapon_id="shotgun")
b.entity("pickup", m(8.0), m(85.0), m(0.8), type="Ammo", weapon_id="rifle")
b.entity("pickup", m(-4.0), m(85.0), m(GALLERY_H + 0.8), type="Health")
b.entity("pickup", m(20.0), m(85.0), m(GALLERY_H + 0.8), type="Points")
b.entity("pickup", m(8.0), m(58.0), m(0.8), type="Points")

# Trigger just inside the big room's entrance, and the exit door in the north wall
b.brush_entity("wave_trigger", [(m(4.0), m(16.0), m(49.0), m(55.0), 0, m(5.0), "special/clip")], wave=WAVE)
door_y = m((ROOM_Y1 + 1) * cell)
b.brush_entity("locked_door", [(m(8.0), m(12.0), door_y - m(0.25), door_y + m(0.25), 0, m(4.0), "world/texture_11_door")], wave=WAVE)

# Reward at the end of the exit hallway
ex, ey = at(7, 24)
b.entity("pickup", m(ex), m(ey), m(0.8), type="Health")

out = os.path.join(os.path.dirname(__file__), "..", "..", "trenchbroom", "maps", "level_02.map")
b.write(os.path.normpath(out))
print("wrote", os.path.normpath(out), "-", len(b.brushes), "brushes,", len(b.entities), "entities")
