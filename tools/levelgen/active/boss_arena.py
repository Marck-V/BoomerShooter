"""Adds the hand boss's arena after the vault to level_02.map by editing the map text in place.

Run from the project root:  python tools/levelgen/active/boss_arena.py

The vault's reward room has a door in its east wall (key_wing.py makes it). Past it:
  Hall     8 m wide, with the boss checkpoint in it (checkpoints.py places that). A door at its west end shuts
           behind the player once they walk into the arena.
  Arena    a round, open-topped arena 52 m across with a water floor, so the sky (and the portal the hand comes
           out of) is overhead. The floor is clear for sweeps and slams. Four low platforms stand at the
           diagonals, each with a grapple point above it, plus a ring of high grapple points around the wall:
           the ways out from under the hand's crush.
The boss is a hand_boss entity in the middle, in wave "boss" (scripts/enemies/hand_boss.gd).

Safe to run again: it replaces everything east of x = 292.25 m. Hand edits there are lost.
All positions in meters, x east, y north, z up.
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from editmap import MapFile, brush_bounds
from mapgen import MapBuilder, m

MAP = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "trenchbroom", "maps", "level_02.map"))

FLOOR = "world/texture_15"
WATER = "world/water"
ARENA_WALL = "world/texture_17"
HALL = "world/texture_04"
TRIM = "world/texture_01"
PILLAR = "world/texture_04"
DOOR = "world/texture_11_door"
CLIP = "special/clip"

F = -25.0            # the same floor height as the vault
T = 0.5
SLAB = 1.2
DOOR_H = 4.0
WAVE = "boss"

HALL_X = (292.5, 301.0)
HALL_Y = (94.0, 102.0)
R = 26.0                         # inner radius of the arena wall
SEGMENTS = 24                    # the wall is a ring of this many straight pieces
WALL_TOP = F + 14.0
CX = HALL_X[1] + R * math.cos(math.radians(180.0 / SEGMENTS))   # the hall meets the wall where its gap is
CY = 98.0
ARENA_CENTRE = (CX, CY, F)

b = MapBuilder()


def box(x0, x1, y0, y1, z0, z1, tex=TRIM, comment=""):
    b.box(m(x0), m(x1), m(y0), m(y1), m(z0), m(z1), tex, comment)


def ring_piece(a0, a1, r0, r1, z0, z1, tex, comment):
    """A straight piece of a ring between angles a0 and a1 (degrees, 0 = east), radii r0 to r1."""
    def corner(a, r, z):
        return (m(CX + r * math.cos(math.radians(a))), m(CY + r * math.sin(math.radians(a))), m(z))

    bottom = [corner(a0, r0, z0), corner(a1, r0, z0), corner(a1, r1, z0), corner(a0, r1, z0)]
    top = [corner(a0, r0, z1), corner(a1, r0, z1), corner(a1, r1, z1), corner(a0, r1, z1)]
    faces = [
        bottom,
        top,
        [bottom[0], bottom[1], top[1], top[0]],     # inner face
        [bottom[3], bottom[2], top[2], top[3]],     # outer face
        [bottom[0], bottom[3], top[3], top[0]],     # side at a0
        [bottom[1], bottom[2], top[2], top[1]],     # side at a1
    ]
    b.convex(faces, tex, comment)


def at(angle, radius):
    return CX + radius * math.cos(math.radians(angle)), CY + radius * math.sin(math.radians(angle))


# --- Hall from the reward room's east door
box(HALL_X[0], HALL_X[1], HALL_Y[0], HALL_Y[1], F - SLAB, F, FLOOR, "boss hall floor")
box(HALL_X[0], HALL_X[1], HALL_Y[0], HALL_Y[1], F + 5.0, F + 5.0 + T, TRIM, "boss hall ceiling")
# Its walls run on into the arena a little, to close the seams where they meet the round wall
box(HALL_X[0], CX - R + 2.0, HALL_Y[0] - T, HALL_Y[0], F - SLAB, F + 5.0 + T, HALL, "boss hall wall")
box(HALL_X[0], CX - R + 2.0, HALL_Y[1], HALL_Y[1] + T, F - SLAB, F + 5.0 + T, HALL, "boss hall wall")
box(HALL_X[1] - 0.5, CX - R + 2.0, HALL_Y[0], HALL_Y[1], F + 5.0, WALL_TOP, ARENA_WALL, "arena entrance lintel")
# Shuts behind the player when they walk into the arena (starts open). The hall is wider than the door.
box(293.0, 293.5, HALL_Y[0], 95.0, F, F + 5.0, HALL, "boss door jamb")
box(293.0, 293.5, 101.0, HALL_Y[1], F, F + 5.0, HALL, "boss door jamb")
box(293.0, 293.5, 95.0, 101.0, F + DOOR_H, F + 5.0, HALL, "boss door lintel")
b.brush_entity("locked_door", [(m(293.0), m(293.5), m(95.0), m(101.0), m(F), m(F + DOOR_H), DOOR)],
               wave=WAVE, starts_open=1)

# --- Arena: water floor, round wall with a gap facing the hall
box(CX - R - 1.0, CX + R + 1.0, CY - R - 1.0, CY + R + 1.0, F - SLAB, F, WATER, "arena floor")
step = 360.0 / SEGMENTS
for i in range(SEGMENTS):
    a0 = 180.0 + step / 2 + i * step
    if i == SEGMENTS - 1:
        continue                                      # the gap the hall comes through, centred on west
    ring_piece(a0, a0 + step, R, R + 1.0, F - SLAB, WALL_TOP, ARENA_WALL, "arena wall")
    ring_piece(a0, a0 + step, R - 0.6, R, F, F + 1.0, TRIM, "arena wall skirting")

# Low platforms at the diagonals, each with a grapple point above it
for angle in (45.0, 135.0, 225.0, 315.0):
    px, py = at(angle, R - 5.0)
    box(px - 2.5, px + 2.5, py - 2.5, py + 2.5, F, F + 4.0, PILLAR, "arena platform")
    b.entity("grapple_point", m(px), m(py), m(F + 10.0))
# High grapple points around the wall, between the platforms
for angle in (0.0, 90.0, 270.0):
    gx, gy = at(angle, R - 3.0)
    b.entity("grapple_point", m(gx), m(gy), m(F + 11.0))

b.entity("hand_boss", m(CX), m(CY), m(F) + 1, wave=WAVE)   # comes down through a portal above this spot
b.brush_entity("wave_trigger", [(m(CX - R + 3.0), m(CX - R + 7.0), m(HALL_Y[0]), m(HALL_Y[1]), m(F), m(F + 5.0), CLIP)],
               wave=WAVE)

# Supplies on the platforms
for angle, kind, weapon in ((45.0, "Health", None), (135.0, "Ammo", "shotgun"), (225.0, "Health", None),
                            (315.0, "Ammo", "rifle")):
    px, py = at(angle, R - 5.0)
    props = {"type": kind}
    if weapon:
        props["weapon_id"] = weapon
    b.entity("pickup", m(px), m(py), m(F + 4.8), **props)
for angle in (0.0, 90.0, 270.0):
    px, py = at(angle, R - 4.0)
    b.entity("pickup", m(px), m(py), m(F + 0.8), type="Ammo", weapon_id="pistol")

# --- Write it: drop the arena's previous version, then add the new one
LIMIT = m(292.25)
mf = MapFile(MAP)
removed_brushes = mf.remove_world_brushes(lambda bounds: bounds[0][0] >= LIMIT)


def in_arena(e):
    if e.classname in ("worldspawn", "checkpoint"):
        return False                                   # checkpoints.py owns every checkpoint
    origin = e.origin()
    if origin is not None:
        return origin[0] >= LIMIT
    faces = e.text[e.text.index("{"):]
    return bool(faces.count("(")) and brush_bounds(faces)[0][0] >= LIMIT


removed_entities = mf.remove(in_arena)
for text in b.brushes:
    mf.add_world_brush(text)
for text in b.entities:
    mf.add(text)
mf.save()
print("arena centre", tuple(round(v, 2) for v in ARENA_CENTRE), "m")
print("replaced", removed_brushes, "brushes and", removed_entities, "entities with", len(b.brushes), "and",
      len(b.entities), "->", MAP)
