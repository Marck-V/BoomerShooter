"""Adds the sky course to level_02.map by editing the map text in place (TrenchBroom edits elsewhere are kept).

Run from the project root:  python tools/levelgen/sky_course.py

At the end of the exit hallway the floor has a hatch. A tube drops 24 m onto a landing platform, then four floating
platforms lead east to a building; between them the only way across is the shield grapple (F to throw).
Everything below ground level (any worldspawn brush entirely under z = -0.5 m) and everything it spawns is
regenerated on every run, so re-running replaces the course. Hand edits to those parts in TrenchBroom are lost.
All positions in meters, x east, y north, z up (the hallway floor is z = 0).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from editmap import MapFile, brush_bounds
from mapgen import MapBuilder, m

MAP = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "trenchbroom", "maps", "level_02.map"))

FLOOR = "world/texture_15"
WALL = "world/texture_14"
SHAFT = "world/texture_04"
PLATFORM = "world/texture_04"
TRIM = "world/texture_01"

HATCH = (28.0, 32.0, 96.0, 100.0)    # x0, x1, y0, y1 of the hole: the last hallway cell
SHAFT_BOTTOM = -24.0                 # top of the landing platform
GAP = 16.0                           # open air between platforms
SIZE = 9.0                           # platform width and depth
CENTER_Y = 98.0
GRAPPLE_RISE = 5.0                   # grapple point height above the platform it leads to
GRAPPLE_INSET = 4.5                  # and how far in from the platform's near edge

# (name, x0, top z). Heights vary a little so the course is not flat.
PLATFORMS = [("P1", 60.0, -22.0), ("P2", 85.0, -26.0), ("P3", 110.0, -22.0), ("P4", 135.0, -25.0)]
LANDING = (27.0, 44.0, 94.0, 102.0, SHAFT_BOTTOM)   # x0, x1, y0, y1, top z

BUILDING = dict(x0=160.0, x1=184.0, y0=88.0, y1=108.0, floor=-25.0, height=8.0, door_y=(95.0, 101.0), door_h=5.0)

WALL_T = 0.5
b = MapBuilder()
mf = MapFile(MAP)

# --- 1. Remove everything the course made before (all of it sits below z = -0.5 m)
below = lambda bounds: bounds[2][1] <= m(-0.5)
removed = mf.remove_world_brushes(below)
mf.remove(lambda e: e.classname == "grapple_point" and (e.origin() or (0, 0, 0))[0] > m(34.0))
mf.remove(lambda e: e.classname == "pickup" and (e.origin() or (0, 0, 0))[2] < 0)
mf.remove(lambda e: e.classname == "pickup" and e.origin() == (960.0, 3136.0, 26.0))   # reward that stood over the hatch

# --- 2. Cut the hatch: the hallway floor row ends where the hatch starts
hx0, hx1, hy0, hy1 = (m(v) for v in HATCH)
floor_text = None
for match, bounds in mf.world_brushes():
    (bx0, bx1), (by0, by1), (bz0, bz1) = bounds
    if by0 <= hy0 and by1 >= hy1 and bz0 == -16 and bz1 == 0 and bx1 >= hx1 and bx0 < hx0:
        floor_text = match
        floor_bounds = bounds
        break
if floor_text is not None:
    texture = re.search(r"\) (\S+) \[", floor_text.group(1)).group(1)
    mf.remove_world_brushes(lambda bounds: bounds == floor_bounds)
    (bx0, bx1), (by0, by1), (bz0, bz1) = floor_bounds
    mf.add_world_brush(b._box_text(bx0, hx0, by0, by1, bz0, bz1, texture, "hallway floor"))
    if bx1 > hx1:
        mf.add_world_brush(b._box_text(hx1, bx1, by0, by1, bz0, bz1, texture, "hallway floor"))
    print("cut the hatch out of the hallway floor")
else:
    hole_present = any(bz1 == 0 and bx1 == hx0 and by0 <= hy0 and by1 >= hy1
                       for _, ((_, bx1), (by0, by1), (_, bz1)) in mf.world_brushes())
    print("hallway floor already has the hatch" if hole_present else "WARNING: hallway floor brush not found; hatch not cut")

# --- 3. The tube: four walls from just under the floor down to the landing platform, east side open at the bottom
t = WALL_T
x0, x1, y0, y1 = HATCH
bottom = SHAFT_BOTTOM
top = -0.5
b.box(m(x0 - t), m(x0), m(y0 - t), m(y1 + t), m(bottom), m(top), SHAFT, "tube west")
b.box(m(x0), m(x1), m(y0 - t), m(y0), m(bottom), m(top), SHAFT, "tube south")
b.box(m(x0), m(x1), m(y1), m(y1 + t), m(bottom), m(top), SHAFT, "tube north")
b.box(m(x1), m(x1 + t), m(y0 - t), m(y1 + t), m(bottom + 5.5), m(top), SHAFT, "tube east")   # leaves a 5.5 m opening at the bottom

# --- 4. Landing platform and the four floating platforms
lx0, lx1, ly0, ly1, ltop = LANDING
b.box(m(lx0), m(lx1), m(ly0), m(ly1), m(ltop - 1.2), m(ltop), FLOOR, "landing platform")
for name, px0, ptop in PLATFORMS:
    b.box(m(px0), m(px0 + SIZE), m(CENTER_Y - SIZE / 2), m(CENTER_Y + SIZE / 2), m(ptop - 1.2), m(ptop), PLATFORM, name)
    b.box(m(px0 + 0.4), m(px0 + SIZE - 0.4), m(CENTER_Y - SIZE / 2 + 0.4), m(CENTER_Y + SIZE / 2 - 0.4), m(ptop), m(ptop + 0.12), TRIM, name + " trim")

# --- 5. The building at the end: roof, walls, and a doorway in the west wall
B = BUILDING
fy0, fy1 = B["y0"], B["y1"]
floor, ceiling = B["floor"], B["floor"] + B["height"]
b.box(m(B["x0"]), m(B["x1"]), m(fy0), m(fy1), m(floor - 1.2), m(floor), FLOOR, "building floor")
b.box(m(B["x0"]), m(B["x1"]), m(fy0), m(fy1), m(ceiling), m(ceiling + 0.5), TRIM, "building roof")
b.box(m(B["x0"]), m(B["x1"]), m(fy0 - t), m(fy0), m(floor - 1.2), m(ceiling + 0.5), WALL, "building south wall")
b.box(m(B["x0"]), m(B["x1"]), m(fy1), m(fy1 + t), m(floor - 1.2), m(ceiling + 0.5), WALL, "building north wall")
b.box(m(B["x1"]), m(B["x1"] + t), m(fy0 - t), m(fy1 + t), m(floor - 1.2), m(ceiling + 0.5), WALL, "building east wall")
dy0, dy1 = B["door_y"]
b.box(m(B["x0"] - t), m(B["x0"]), m(fy0 - t), m(dy0), m(floor - 1.2), m(ceiling + 0.5), WALL, "building west wall (south part)")
b.box(m(B["x0"] - t), m(B["x0"]), m(dy1), m(fy1 + t), m(floor - 1.2), m(ceiling + 0.5), WALL, "building west wall (north part)")
b.box(m(B["x0"] - t), m(B["x0"]), m(dy0), m(dy1), m(floor + B["door_h"]), m(ceiling + 0.5), WALL, "building doorway lintel")

for text in b.brushes:
    mf.add_world_brush(text)

# --- 6. Grapple points above the near end of each platform, and one just inside the doorway
e = MapBuilder()
for name, px0, ptop in PLATFORMS:
    e.entity("grapple_point", m(px0 + GRAPPLE_INSET), m(CENTER_Y), m(ptop + GRAPPLE_RISE))
e.entity("grapple_point", m(B["x0"] + 4.0), m(CENTER_Y), m(floor + 3.0))

# Pickups: health on the landing platform, ammo mid-course, health and a points bar in the building
e.entity("pickup", m(34.0), m(CENTER_Y), m(ltop + 0.8), type="Health")
e.entity("pickup", m(PLATFORMS[1][1] + SIZE / 2), m(CENTER_Y), m(PLATFORMS[1][2] + 0.8), type="Ammo", weapon_id="shotgun")
e.entity("pickup", m(PLATFORMS[3][1] + SIZE / 2), m(CENTER_Y), m(PLATFORMS[3][2] + 0.8), type="Ammo", weapon_id="lightning")
e.entity("pickup", m(B["x0"] + 10.0), m(CENTER_Y - 4.0), m(floor + 0.8), type="Health")
e.entity("pickup", m(B["x0"] + 14.0), m(CENTER_Y + 4.0), m(floor + 0.8), type="Points")
for text in e.entities:
    mf.add(text)

mf.save()
print("removed", removed, "old course brushes; added", len(b.brushes), "brushes and", len(e.entities), "entities ->", MAP)
