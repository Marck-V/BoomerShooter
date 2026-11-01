"""Fixes the big arena's gallery ramps and adds melee dodgers, pistol ammo and flamethrower ammo, editing level_02.map in place.

Run from the project root:  python tools/levelgen/active/arena_tweaks.py

Enemies can only walk onto a ramp from its foot: its open side soon gets too tall for them to climb, though the
navigation mesh still routes them there, and they jam against it. So each ramp gets a wall along its inner side, and
starts further from the south wall to leave room at the foot.

Safe to run again.
Positions in meters, x east, y north, z up.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from editmap import MapFile
from mapgen import MapBuilder, m

MAP = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "trenchbroom", "maps", "level_02.map"))
RAMP = "world/texture_10_stairs"
WALL = "world/texture_04"
GALLERY_H = 5.0
RAIL_TOP = GALLERY_H + 1.2
RAMP_Y0, RAMP_Y1 = 52.0, 60.0
WEST_LIMIT = m(184.0)       # the key wing, east of here, places its own ammo

# (ramp x0, ramp x1, wall x0)
RAMPS = [(-8.0, 0.0, -0.5), (16.0, 24.0, 16.0)]
DODGERS_TO_MELEE = [(77.0, 1792.0), (456.0, 1821.0), (164.0, 2135.0)]   # map units, of the six arena dodgers
HORDE_TO_BOMBER = [(100.0, 1932.0), (405.0, 2002.0), (222.0, 2496.0)]   # map units, of the arena's horde
HORDE_TO_BRUTE = [(179.0, 2314.0)]
PISTOL_AMMO = [(4.0, 30.0, 0.0), (12.0, 54.0, 0.0), (-4.0, 75.0, GALLERY_H), (38.0, 98.0, -24.0), (114.5, 98.0, -22.0),
               (170.0, 102.0, -25.0)]

FLAMETHROWER_AMMO = [(4.0, 56.0, 0.0), (12.0, 84.0, 0.0), (20.0, 75.0, GALLERY_H), (178.0, 94.0, -25.0)]

b = MapBuilder()
mf = MapFile(MAP)

# Ramps: replace the old wedges (y 50 or 52 to 60, flush with the gallery) and any wall from an earlier run
ramp_ranges = {(m(x0), m(x1)) for x0, x1, _ in RAMPS}
wall_ranges = {(m(wall), m(wall + 0.5)) for _, _, wall in RAMPS}
removed = mf.remove_world_brushes(lambda bounds: bounds[1][1] == m(RAMP_Y1) and bounds[1][0] >= m(50.0) and bounds[2][0] == 0
                                  and (bounds[0] in ramp_ranges or bounds[0] in wall_ranges))
for x0, x1, wall in RAMPS:
    b.ramp(m(x0), m(x1), m(RAMP_Y0), m(RAMP_Y1), 0, m(GALLERY_H), "+y", RAMP, "gallery ramp")
    b.box(m(wall), m(wall + 0.5), m(RAMP_Y0), m(RAMP_Y1), 0, m(RAIL_TOP), WALL, "gallery ramp wall")
for text in b.brushes:
    mf.add_world_brush(text)

# Half of the arena's dodgers become melee dodgers
swapped = 0
for entity in mf.entities:
    origin = entity.origin()
    if entity.classname == "enemy_dodger" and origin and (origin[0], origin[1]) in DODGERS_TO_MELEE:
        entity.text = entity.text.replace('"enemy_dodger"', '"enemy_melee_dodger"')
        entity.classname = "enemy_melee_dodger"
        swapped += 1

# Some of the horde become bombers and a brute
for entity in mf.entities:
    origin = entity.origin()
    if entity.classname == "enemy_horde" and origin:
        for points, classname in ((HORDE_TO_BOMBER, "enemy_bomber"), (HORDE_TO_BRUTE, "enemy_brute")):
            if (origin[0], origin[1]) in points:
                entity.text = entity.text.replace('"enemy_horde"', '"%s"' % classname)
                entity.classname = classname

# Pistol ammo
mf.remove(lambda e: e.classname == "pickup" and e.props.get("weapon_id") in ("pistol", "flamethrower") and e.origin()[0] <= WEST_LIMIT)
ammo = MapBuilder()
for x, y, floor in PISTOL_AMMO:
    ammo.entity("pickup", m(x), m(y), m(floor + 0.8), type="Ammo", weapon_id="pistol")
for x, y, floor in FLAMETHROWER_AMMO:
    ammo.entity("pickup", m(x), m(y), m(floor + 0.8), type="Ammo", weapon_id="flamethrower")
for text in ammo.entities:
    mf.add(text)

mf.save()
print("replaced", removed, "ramp brushes, swapped", swapped, "dodgers, placed", len(ammo.entities), "ammo pickups ->", MAP)
