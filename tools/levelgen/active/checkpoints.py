"""Adds checkpoints to level_02.map by editing the map text in place.

Run from the project root:  python tools/levelgen/active/checkpoints.py

Each one fills a corridor the player has to walk down, wall to wall and floor to ceiling, so it can't be missed:
  arena exit   the corridor just past the big arena's exit door
  hub          the hall from the sky course's building to the hub door, before the hub's wave
  vault        the hall between the blue key door and the vault door, before the final arena
  boss         the hall from the vault's reward room to the hand boss's arena

Safe to run again: it replaces every checkpoint in the map. Hand-placed checkpoints are lost.
Positions in map units (the corridors' wall faces), x east, y north, z up.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from editmap import MapFile
from mapgen import MapBuilder

MAP = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "trenchbroom", "maps", "level_02.map"))
CLIP = "special/clip"

# (x0, x1, y0, y1, z0, z1): floor to ceiling, wall to wall
CHECKPOINTS = [
    (256, 384, 2880, 2992, 0, 128),         # arena exit
    (5920, 6048, 3008, 3264, -800, -624),   # hub
    (7424, 7568, 3008, 3264, -800, -624),   # vault
    (9472, 9536, 3008, 3264, -800, -640),   # boss: the hall into the hand's arena
]

b = MapBuilder()
for x0, x1, y0, y1, z0, z1 in CHECKPOINTS:
    b.brush_entity("checkpoint", [(x0, x1, y0, y1, z0, z1, CLIP)])

mf = MapFile(MAP)
removed = mf.remove(lambda e: e.classname == "checkpoint")
for text in b.entities:
    mf.add(text)
mf.save()
print("replaced", removed, "checkpoints with", len(b.entities), "->", MAP)
