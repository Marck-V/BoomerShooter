"""Rebuilds the big room's enemy wave in level_02.map by editing the map text in place.

Run from the project root:  python tools/levelgen/arena_wave.py

Leaves everything else in the map (including hand edits made in TrenchBroom) alone. Removes every enemy
in the big room, then adds a large wave (they spawn in when the player walks into the wave_trigger) and a
second door that shuts the entrance behind the player. Safe to run again: it replaces its own work.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from editmap import MapFile
from mapgen import MapBuilder, m

MAP = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "trenchbroom", "maps", "level_02.map"))
WAVE = "arena"
MELEE_COUNT = 24
GALLERY_H = 5.0
ROOM_Y0 = 48.0        # south wall of the big room (m)

# Cover on the lower floor (x0, x1, y0, y1 in meters), so enemies don't spawn inside it
COVER = [(5.0, 11.0, 64.0, 65.0), (5.0, 11.0, 74.0, 75.0), (2.0, 4.0, 69.0, 71.0), (12.0, 14.0, 69.0, 71.0)]

mf = MapFile(MAP)

# 1. Remove every enemy in the big room and any previous wave door at the entrance
def in_big_room(e):
    origin = e.origin()
    return origin is not None and origin[1] >= m(ROOM_Y0)

removed = mf.remove(lambda e: e.classname in ("enemy_horde", "enemy_ranged") and (in_big_room(e) or e.props.get("wave") == WAVE))
removed_doors = mf.remove(lambda e: e.classname == "locked_door" and e.props.get("starts_open") == "1")
print("removed", removed, "enemies and", removed_doors, "entrance doors")

b = MapBuilder()

# 2. Melee enemies spread over the lower floor (jittered, avoiding cover and each other)
rng = random.Random(7)
placed = []
tries = 0
while len(placed) < MELEE_COUNT and tries < 5000:
    tries += 1
    x, y = rng.uniform(1.5, 14.5), rng.uniform(53.0, 86.0)
    if any(x0 - 1.2 < x < x1 + 1.2 and y0 - 1.2 < y < y1 + 1.2 for x0, x1, y0, y1 in COVER):
        continue
    if any((x - px) ** 2 + (y - py) ** 2 < 2.2 ** 2 for px, py in placed):
        continue
    placed.append((x, y))
for x, y in placed:
    b.entity("enemy_horde", m(x), m(y), 1, wave=WAVE)

# 3. Ranged enemies on both galleries
for gx in (-4.0, 20.0):
    for y in (66.0, 74.0, 82.0):
        b.entity("enemy_ranged", m(gx), m(y), m(GALLERY_H) + 1, wave=WAVE)

# 4. Entrance door: open at the start, shuts behind the player when the wave begins
b.brush_entity("locked_door", [(m(8.0), m(12.0), m(ROOM_Y0) - m(0.25), m(ROOM_Y0) + m(0.25), 0, m(4.0), "world/texture_11_door")],
               wave=WAVE, starts_open=1)

for text in b.entities:
    mf.add(text)
mf.save()
print("added", len(placed), "melee,", 6, "ranged, 1 entrance door ->", MAP)
