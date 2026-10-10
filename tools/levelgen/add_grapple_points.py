"""Adds the grapple points to level_02.map by editing the map text in place (hand edits are left alone).

Run from the project root:  python tools/levelgen/add_grapple_points.py
Safe to run again: it removes the grapple points it placed before and puts them back.
Positions are in meters (x, y, height above the floor). The big room spans x 0..16, y 48..88.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from editmap import MapFile
from mapgen import MapBuilder, m

MAP = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "trenchbroom", "maps", "level_02.map"))

POINTS = [
    (8.0, 58.0, 5.5),     # over the middle of the entrance end of the room
    (8.0, 72.0, 8.5),     # high above the center, past the pillars
    (-3.0, 62.0, 8.5),    # over the left gallery, its entrance end
    (19.0, 62.0, 8.5),    # over the right gallery
    (8.0, 84.0, 7.0),     # near the exit wall
]

mf = MapFile(MAP)
removed = mf.remove(lambda e: e.classname == "grapple_point")
b = MapBuilder()
for x, y, z in POINTS:
    b.entity("grapple_point", m(x), m(y), m(z))
for text in b.entities:
    mf.add(text)
mf.save()
print("removed", removed, "old grapple points, added", len(POINTS), "->", MAP)
