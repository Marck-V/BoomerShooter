"""Generates trenchbroom/maps/level_02.map: a small test arena.

Run from the project root:  python tools/levelgen/make_level_02.py
Player numbers this is sized for: single jump ~1.6 m, double jump ~3.2 m, dash ~5 m.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mapgen import MapBuilder, m

FLOOR = "world/texture_15"
WALL = "world/texture_14"
BLOCK = "world/texture_04"
PILLAR = "world/texture_01"

SIZE = m(32)          # arena is 32 x 32 m, floor top at z = 0
WALL_H = m(6)
WALL_T = m(0.5)

b = MapBuilder()

# Floor and perimeter walls
b.box(0, SIZE, 0, SIZE, -m(0.5), 0, FLOOR, "floor")
b.box(-WALL_T, 0, -WALL_T, SIZE + WALL_T, -m(0.5), WALL_H, WALL, "west wall")
b.box(SIZE, SIZE + WALL_T, -WALL_T, SIZE + WALL_T, -m(0.5), WALL_H, WALL, "east wall")
b.box(0, SIZE, -WALL_T, 0, -m(0.5), WALL_H, WALL, "south wall")
b.box(0, SIZE, SIZE, SIZE + WALL_T, -m(0.5), WALL_H, WALL, "north wall")

# Central raised platform (1.5 m, one jump) with two steps up from the south side
c = SIZE // 2
b.box(c - m(4), c + m(4), c - m(4), c + m(4), 0, m(1.5), BLOCK, "center platform")
b.box(c - m(2), c + m(2), c - m(8), c - m(6), 0, m(0.5), BLOCK, "step 1")
b.box(c - m(2), c + m(2), c - m(6), c - m(4), 0, m(1.0), BLOCK, "step 2")

# Corner pillars (cover)
for px, py in ((m(5), m(5)), (SIZE - m(7), m(5)), (m(5), SIZE - m(7)), (SIZE - m(7), SIZE - m(7))):
    b.box(px, px + m(2), py, py + m(2), 0, m(4), PILLAR, "pillar")

# Stepping block + high ledge along the north wall (block is a 1.5 m hop, ledge is 3 m)
b.box(c - m(1), c + m(1), SIZE - m(7), SIZE - m(5), 0, m(1.5), BLOCK, "ledge step block")
b.box(m(6), SIZE - m(6), SIZE - m(3), SIZE, 0, m(3), BLOCK, "north ledge")

# Entities (z is the feet height for characters)
b.entity("info_player_start", c, m(3), 1, angle=90)
b.entity("enemy_horde", m(8), c, 1)
b.entity("enemy_horde", SIZE - m(8), c, 1)
b.entity("enemy_ranged", c, SIZE - m(1.5), m(3) + 1)
b.entity("pickup", m(3), m(3), m(1), type="Health")
b.entity("pickup", SIZE - m(3), m(3), m(1), type="Ammo", weapon_id="shotgun")
b.entity("pickup", c, c, m(1.5) + m(1), type="Points")

out = os.path.join(os.path.dirname(__file__), "..", "..", "trenchbroom", "maps", "level_02.map")
b.write(os.path.normpath(out))
print("wrote", os.path.normpath(out), "-", len(b.brushes), "brushes,", len(b.entities), "entities")
