"""Builds trenchbroom/maps/level_01.map: level 1 as a climb around an open courtyard, then out over the rooftops.

Run from the project root:  python tools/levelgen/active/level_01_redesign.py

This script owns the whole map, so running it again overwrites everything (including hand edits made in TrenchBroom).
When the layout is settled, commit the map and delete this script (see tools/levelgen/README.md).

All positions in meters, x east, y north, z up. "OUT" is under the open sky, "IN" has a roof.

First half: the pistol only. The route circles the courtyard and climbs, so each space looks onto the others.
  Pad, bridge  OUT  A floating pad and a railed bridge to the complex. One grunt walks down it: one against one.
  Lobby        IN   Three grunts come in one at a time (a trickle); the way back to the bridge stays open.
  Courtyard    OUT  The heart of the level. Walking to the middle springs the fight: five grunts run in past clusters
                    of explosive barrels. A walkway crosses overhead and the gallery's windows look down on it.
  Warehouse    IN   The first ranged enemies, up on a mezzanine with a barrel between them. Fight up the ramp.
  Rooftops     OUT  Out of the warehouse's upper door, along the walkway over the courtyard and across the roofs.
                    Three ranged enemies fire from towers across a gap, each beside a barrel. Nothing is locked: get
                    across (or drop back into the courtyard).
  Gallery      IN   Entered on its balcony: for once the player has the high ground. Clearing it opens the vault under
                    the far balcony. Taking the loot there springs an ambush behind the player, between them and the
                    door, beside a row of barrels. That opens a shortcut back to the courtyard and the way on.
  Shrine       IN   A tall glass hall. The shield floats on the upper tier; taking it starts the parry lesson.

Second half: the shield and the grapple.
  Crossing     OUT  A canal between two roofs, crossed by grappling from pillar to pillar. Fall in and a ramp leads out.
  Plaza        OUT  The hub, with the upgrade station. Bridges lead north (red key) and south (blue key).
  Red hall     IN   The parry gauntlet: ranged enemies on side platforms, grunts below.
  Spire        OUT  The grapple climb, in the open air: three pillars, ranged enemies on two watchtowers.
  Coliseum     OUT  Godot Man, behind the red and blue doors, in an open-topped arena. He drops out of the sky.

A fall_trigger under the whole level puts a player who falls off back on the last solid ground they stood on.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from mapgen import MapBuilder, m

MAP = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "trenchbroom", "maps", "level_01.map"))

IN_FLOOR = "world/texture_08"
OUT_FLOOR = "world/texture_15"
BODY = "world/texture_14"       # the outside of buildings, bridges and towers
WALL_A = "world/texture_01"
WALL_B = "world/texture_02"
WALL_C = "world/texture_06"
CEILING = "world/texture_09"
PILLAR = "world/texture_04"
RAMP = "world/texture_05"
DOOR = "world/texture_07"
CLIP = "special/clip"
GLASS = "world/texture_12_window"

T = 0.5            # wall thickness
BASE = -10.0       # how far down buildings and towers reach (they float over the neon grid)
DOOR_H = 4.0       # doors slide 4.2 m down into the floor, so no door is taller than this
RAIL_H = 1.0
UP = 5.0           # the upper level of the first half: mezzanine, walkway, roofs, gallery balcony
TIER = 4.0         # the level of the second half
PIT = -2.0         # the canal floor
LEDGE = 8.0        # the red hall's side platforms
WINDOW_HEALTH = 20  # one pistol shot (25) breaks a pane

b = MapBuilder()
SOLIDS = []        # (box, texture, comment, cuttable)
HOLES = []         # boxes cut out of every cuttable solid (walls, ceilings, parapets)
WEDGES = []        # (x0, x1, y0, y1): footprints of ramps, for the floor check at the end
POINTS = []        # (classname, x, y, z): point entities, for the floor check at the end


# --- Geometry helpers --------------------------------------------------------------------------------------------
def solid(x0, x1, y0, y1, z0, z1, tex, comment="", cut=False):
    SOLIDS.append(((x0, x1, y0, y1, z0, z1), tex, comment, cut))


def hole(x0, x1, y0, y1, z0, z1):
    HOLES.append((x0, x1, y0, y1, z0, z1))


def floor(x0, x1, y0, y1, top, tex=IN_FLOOR, depth=None, comment="floor"):
    """A floor: a solid block from BASE (or `depth` below the top) up to `top`."""
    solid(x0, x1, y0, y1, BASE if depth is None else top - depth, top, tex, comment)


def wall_x(x, y0, y1, top, tex, bottom=BASE, comment="wall"):
    """A wall running along y, T thick, from x to x + T."""
    solid(x, x + T, y0, y1, bottom, top, tex, comment, cut=True)


def wall_y(y, x0, x1, top, tex, bottom=BASE, comment="wall"):
    """A wall running along x, T thick, from y to y + T."""
    solid(x0, x1, y, y + T, bottom, top, tex, comment, cut=True)


def room_walls(x0, x1, y0, y1, top, tex, sides="nsew"):
    """Walls just outside the interior x0..x1, y0..y1, from BASE up to `top`. East and west cover the corners."""
    if "w" in sides:
        wall_x(x0 - T, y0 - T, y1 + T, top, tex)
    if "e" in sides:
        wall_x(x1, y0 - T, y1 + T, top, tex)
    if "s" in sides:
        wall_y(y0 - T, x0, x1, top, tex)
    if "n" in sides:
        wall_y(y1, x0, x1, top, tex)


def ceiling(x0, x1, y0, y1, z, tex=CEILING):
    """A ceiling over the interior x0..x1, y0..y1 (it rests on the walls)."""
    solid(x0, x1, y0, y1, z, z + T, tex, "ceiling", cut=True)


def rail(x0, x1, y0, y1, z, height=RAIL_H, tex=BODY):
    solid(x0, x1, y0, y1, z, z + height, tex, "rail", cut=True)


def pillar(x0, x1, y0, y1, z0, z1, tex=PILLAR, comment="pillar"):
    solid(x0, x1, y0, y1, z0, z1, tex, comment)


def door_hole_x(x, y0, y1, z0, height=DOOR_H):
    """An opening through a wall that runs along y and stands at x..x + T."""
    hole(x - 0.1, x + T + 0.1, y0, y1, z0, z0 + height)


def door_hole_y(y, x0, x1, z0, height=DOOR_H):
    hole(x0, x1, y - 0.1, y + T + 0.1, z0, z0 + height)


def window_x(x, y0, y1, z0, z1):
    """A glass pane in a wall that runs along y and stands at x..x + T."""
    hole(x - 0.1, x + T + 0.1, y0, y1, z0, z1)
    brush("window", [(x + 0.1875, x + 0.3125, y0, y1, z0, z1, GLASS)], health=WINDOW_HEALTH)


def window_y(y, x0, x1, z0, z1):
    hole(x0, x1, y - 0.1, y + T + 0.1, z0, z1)
    brush("window", [(x0, x1, y + 0.1875, y + 0.3125, z0, z1, GLASS)], health=WINDOW_HEALTH)


def skylight(x0, x1, y0, y1, z):
    """A glass pane in a ceiling at height z."""
    hole(x0, x1, y0, y1, z - 0.1, z + T + 0.1)
    brush("window", [(x0, x1, y0, y1, z + 0.1875, z + 0.3125, GLASS)], health=WINDOW_HEALTH)


def _cut_box(box, cut):
    x0, x1, y0, y1, z0, z1 = box
    hx0, hx1, hy0, hy1, hz0, hz1 = cut
    if hx0 >= x1 or hx1 <= x0 or hy0 >= y1 or hy1 <= y0 or hz0 >= z1 or hz1 <= z0:
        return [box]
    pieces = []
    cx0, cx1 = max(x0, hx0), min(x1, hx1)
    cy0, cy1 = max(y0, hy0), min(y1, hy1)
    if x0 < cx0:
        pieces.append((x0, cx0, y0, y1, z0, z1))
    if cx1 < x1:
        pieces.append((cx1, x1, y0, y1, z0, z1))
    if y0 < cy0:
        pieces.append((cx0, cx1, y0, cy0, z0, z1))
    if cy1 < y1:
        pieces.append((cx0, cx1, cy1, y1, z0, z1))
    if z0 < hz0:
        pieces.append((cx0, cx1, cy0, cy1, z0, hz0))
    if hz1 < z1:
        pieces.append((cx0, cx1, cy0, cy1, hz1, z1))
    return pieces


# --- Entity helpers ----------------------------------------------------------------------------------------------
def brush(classname, boxes, **properties):
    """A brush entity from boxes in meters: (x0, x1, y0, y1, z0, z1, texture)."""
    b.brush_entity(classname, [tuple(m(v) for v in box[:6]) + (box[6],) for box in boxes], **properties)


def entity(classname, x, y, z=0.0, **properties):
    b.entity(classname, m(x), m(y), m(z) + 1, **properties)
    POINTS.append((classname, x, y, z))


def enemies(classname, wave, spots, z=0.0):
    for spot in spots:
        if wave:
            entity(classname, spot[0], spot[1], spot[2] if len(spot) > 2 else z, wave=wave)
        else:
            entity(classname, spot[0], spot[1], spot[2] if len(spot) > 2 else z)


def pickup(kind, x, y, z=0.0):
    if kind == "Ammo":
        entity("pickup", x, y, z + 0.8, type="Ammo", weapon_id="pistol")
    else:
        entity("pickup", x, y, z + 0.8, type=kind)


def barrels(spots, z=0.0, classname="explosive_barrel"):
    for x, y in spots:
        entity(classname, x, y, z)


def trigger(x0, x1, y0, y1, z0, z1, wave, **properties):
    brush("wave_trigger", [(x0, x1, y0, y1, z0, z1, CLIP)], wave=wave, **properties)


def door(x0, x1, y0, y1, z0, wave, starts_open, height=DOOR_H):
    brush("locked_door", [(x0, x1, y0, y1, z0, z0 + height, DOOR)], wave=wave, starts_open=starts_open)


def barrier(x0, x1, y0, y1, z0, z1, wave):
    brush("barrier", [(x0, x1, y0, y1, z0, z1, DOOR)], wave=wave)


def checkpoint(x0, x1, y0, y1, z0, height=DOOR_H):
    brush("checkpoint", [(x0, x1, y0, y1, z0, z0 + height, CLIP)])


# --- Ramps (a wedge with a rail down each open side: without rails enemies cut across the low edge and jam) ---------
RAIL = 0.25


def _wedge(x0, x1, y0, y1, zb, z_lo_top, z_hi_top, rises, tex, comment):
    """A solid with a flat bottom at zb whose top slopes from z_lo_top at the low end to z_hi_top at the high end."""
    a, bb, c, d = (x0, y0, zb), (x1, y0, zb), (x1, y1, zb), (x0, y1, zb)
    lo, hi = z_lo_top, z_hi_top
    tops = {"+y": (lo, lo, hi, hi), "-y": (hi, hi, lo, lo), "+x": (lo, hi, hi, lo), "-x": (hi, lo, lo, hi)}[rises]
    e, f, g, h = (x0, y0, tops[0]), (x1, y0, tops[1]), (x1, y1, tops[2]), (x0, y1, tops[3])
    if lo == zb:   # a true wedge: the low edge has no height, so the top meets the bottom there
        faces = {"+y": [[a, bb, c, d], [a, bb, g, h], [a, d, h], [bb, c, g], [d, c, g, h]],
                 "-y": [[a, bb, c, d], [d, c, f, e], [a, d, e], [bb, c, f], [a, bb, f, e]],
                 "+x": [[a, bb, c, d], [a, d, g, f], [a, bb, f], [d, c, g], [bb, c, g, f]],
                 "-x": [[a, bb, c, d], [bb, c, h, e], [a, bb, e], [d, c, h], [a, d, h, e]]}[rises]
    else:
        faces = [[a, bb, c, d], [e, f, g, h], [a, bb, f, e], [d, c, g, h], [a, d, h, e], [bb, c, g, f]]
    b.convex([[tuple(m(v) for v in pt) for pt in face] for face in faces], tex, comment)


def ramp(x0, x1, y0, y1, z_base, z_top, rises, rails="both"):
    """A ramp rising along y (+y/-y) or x (+x/-x). rails: "both", "low" (the side with the smaller x or y), "high" or
    "none": leave out the rail on a side that runs along a wall."""
    _wedge(x0, x1, y0, y1, z_base, z_base, z_top, rises, RAMP, "ramp")
    WEDGES.append((x0, x1, y0, y1))
    lo, hi = z_base + RAIL_H, z_top + RAIL_H
    if rises in ("+y", "-y"):
        if rails in ("both", "low"):
            _wedge(x0 - RAIL, x0, y0, y1, z_base, lo, hi, rises, RAMP, "ramp rail")
        if rails in ("both", "high"):
            _wedge(x1, x1 + RAIL, y0, y1, z_base, lo, hi, rises, RAMP, "ramp rail")
    else:
        if rails in ("both", "low"):
            _wedge(x0, x1, y0 - RAIL, y0, z_base, lo, hi, rises, RAMP, "ramp rail")
        if rails in ("both", "high"):
            _wedge(x0, x1, y1, y1 + RAIL, z_base, lo, hi, rises, RAMP, "ramp rail")


def bridge(x0, x1, y0, y1, top, along):
    """A railed open-air bridge: a 1 m thick deck with a rail down each long side. along: "x" or "y"."""
    solid(x0, x1, y0, y1, top - 1.0, top, OUT_FLOOR, "bridge")
    if along == "y":
        rail(x0 - RAIL, x0, y0, y1, top - 1.0, RAIL_H + 1.0)
        rail(x1, x1 + RAIL, y0, y1, top - 1.0, RAIL_H + 1.0)
    else:
        rail(x0, x1, y0 - RAIL, y0, top - 1.0, RAIL_H + 1.0)
        rail(x0, x1, y1, y1 + RAIL, top - 1.0, RAIL_H + 1.0)


# ====================================================================================================================
# 1. Pad and bridge (OUT): the first thing the player sees is the sky and the complex ahead
# ====================================================================================================================
floor(12, 28, -46, -30, 0, OUT_FLOOR, depth=3.0, comment="pad")
for px, py in ((12, -46), (27, -46), (12, -31), (27, -31)):
    pillar(px, px + 1, py, py + 1, 0, 2.5, comment="pad pylon")
bridge(17, 23, -30, 3.5, 0, "y")
b.entity("info_player_start", m(20.0), m(-40.0), m(0) + 1, angle=90)
entity("enemy_horde", 20.0, -6.0)          # awake from the start: the first fight is one against one

# ====================================================================================================================
# 2. Lobby (IN): x 8..32, y 4..27.5. A trickle of three grunts; the bridge behind stays open.
# ====================================================================================================================
floor(8, 32, 4, 27.5, 0)
room_walls(8, 32, 4, 27.5, 6.5, WALL_A)
ceiling(8, 32, 4, 27.5, 6.0)
door_hole_y(3.5, 17, 23, 0)
door_hole_y(27.5, 17, 23, 0)
door(17, 23, 27.5, 28, 0, "lobby", 0)                 # opens onto the courtyard when the lobby is clear
for x0, x1 in ((9.5, 15.5), (24.5, 30.5)):
    window_y(27.5, x0, x1, 1.5, 4.5)                  # a look at the courtyard before the door opens
for y0, y1 in ((8, 14), (18, 24)):
    window_x(7.5, y0, y1, 1.5, 4.5)
    window_x(32, y0, y1, 1.5, 4.5)
skylight(14, 26, 10, 22, 6.0)
for px in (12.5, 26.5):
    pillar(px, px + 1, 15, 16, 0, 6.0)
trigger(8, 32, 6, 10, 0, 4, "lobby", spawn_interval=1.2)
enemies("enemy_horde", "lobby", ((20, 25), (11, 23), (29, 23)))
pickup("Ammo", 10, 6)
pickup("Health", 30, 6)

# ====================================================================================================================
# 3. Courtyard (OUT): x 0..40, y 28..72. Barrels, and everything else looks down on it.
# ====================================================================================================================
floor(0, 40, 28, 72, 0, OUT_FLOOR)
wall_y(27.5, 0, 7.5, 6.5, WALL_A)                  # south side, either end of the lobby
wall_y(27.5, 32.5, 40.5, 6.5, WALL_A)
wall_x(40, 28, 43.5, 6.5, WALL_A)                     # east side, south of the gallery
wall_y(72, 0, 40, UP, BODY)                           # north side: the foot of the roofs
rail(6, 40, 72, 72.25, UP)
# The walkway over the west side: the way from the warehouse's upper door to the roofs
solid(0, 6, 28, 72, UP - 0.5, UP, OUT_FLOOR, "walkway")
rail(6, 6.25, 28, 72, UP - 0.5, RAIL_H + 0.5)
for py in (30, 46, 62):
    pillar(5, 6, py, py + 1, 0, UP - 0.5)
# Cover and barrels
pillar(18, 22, 48, 52, 0, 1.2, comment="planter")
for x0, x1, y0, y1 in ((9, 11, 37, 39), (29, 31, 37, 39)):
    pillar(x0, x1, y0, y1, 0, 1.4, comment="crate")
for x0, x1 in ((11, 16), (24, 29)):
    pillar(x0, x1, 55, 55.5, 0, 1.4, WALL_B, "cover")
barrels(((19, 60), (21, 60), (20, 61.5), (33, 63), (34.5, 62), (9, 64), (10.5, 65)))
barrels(((30, 50), (12, 47)), classname="barrel")
trigger(0, 40, 42, 46, 0, 4, "yard")
barrier(17, 23, 28, 28.25, 0, DOOR_H, "yard")
enemies("enemy_horde", "yard", ((20, 68), (10, 69), (30, 69), (36, 66), (8, 60)))
pickup("Points", 20, 50, 1.2)
pickup("Ammo", 3, 31)
pickup("Health", 37, 31)
pickup("Ammo", 37, 70)
# The door into the warehouse (west), under the walkway: opens when the courtyard is clear
door_hole_x(-0.5, 36, 42, 0)
door(-0.5, 0, 36, 42, 0, "yard", 0)
checkpoint(-1.25, -1.0, 36, 42, 0)

# ====================================================================================================================
# 4. Warehouse (IN): x -36..-0.5, y 28..60, 11 m tall. The first ranged enemies, on the mezzanine.
# ====================================================================================================================
floor(-36, -0.5, 28, 60, 0)
room_walls(-36, -0.5, 28, 60, 11.5, WALL_C)           # its east wall is the courtyard's west side
ceiling(-36, -0.5, 28, 60, 11.0)
wall_x(-0.5, 60.5, 72.5, UP + RAIL_H, WALL_C)         # the courtyard's west side north of the warehouse: a parapet
solid(-36, -0.5, 52, 60, UP - 0.5, UP, IN_FLOOR, "mezzanine")
rail(-28, -24, 51.75, 52, UP - 0.5, RAIL_H + 0.5, PILLAR)   # short: a rail in front of the ranged enemies would block their shots
for px in (-20, -10):
    pillar(px, px + 1, 52, 53, 0, UP - 0.5)
ramp(-36, -28, 38, 52, 0, UP, "+y", rails="high")     # the wall is on its west side
for x0, x1, y0, y1, top in ((-12, -8, 44, 46, 2.0), (-24, -20, 40, 42, 2.0), (-18, -13, 34, 34.5, 1.4),
                            (-8, -3, 47, 47.5, 1.4), (-27, -22, 47, 47.5, 1.4)):
    pillar(x0, x1, y0, y1, 0, top, WALL_B if top < 2 else PILLAR, "cover")
trigger(-10, -3, 28, 60, 0, UP, "warehouse")
enemies("enemy_ranged", "warehouse", ((-8, 56), (-20, 56)), UP)
enemies("enemy_horde", "warehouse", ((-22, 45), (-14, 50)))
barrels(((-14, 58),), UP)                              # between the two on the mezzanine
barrels(((-30, 34), (-6, 31)), classname="barrel")
pickup("Health", -4, 34)
pickup("Ammo", -34, 30)
pickup("Points", -34, 57, UP)
pickup("Ammo", -3, 53, UP)
for y0, y1 in ((30, 36),):
    window_x(-36.5, y0, y1, 2, 8)
window_x(-36.5, 40, 50, 7, 10)
for x0, x1 in ((-30, -22), (-14, -6)):
    window_y(27.5, x0, x1, 3, 9)
    window_y(60, x0, x1, 7, 10)
skylight(-26, -10, 32, 46, 11.0)
# The upper door, onto the walkway over the courtyard: opens when the warehouse is clear
door_hole_x(-0.5, 54, 58, UP)
door(-0.5, 0, 54, 58, UP, "warehouse", 0)
checkpoint(0.25, 0.5, 54, 58, UP)
pickup("Health", 3, 30, UP)                            # the dead end of the walkway, over the lobby

# ====================================================================================================================
# 5. Rooftops (OUT): three roofs north of the courtyard, under fire from three towers across the gap
# ====================================================================================================================
floor(0, 14, 72.5, 86, UP, OUT_FLOOR, comment="roof 1")
floor(19, 33, 72.5, 86, UP + 1.5, OUT_FLOOR, comment="roof 2")
floor(38, 58, 72.5, 86, UP, OUT_FLOOR, comment="roof 3")
ramp(14, 19, 76, 80, UP, UP + 1.5, "+x")               # roof 1 to roof 2; roof 2 to roof 3 is a jump down
solid(14, 19, 76, 80, UP - 1.0, UP, BODY, "ramp deck")
for x0, x1, y, z in ((2, 7, 83, UP), (9, 13, 80, UP), (20, 25, 83, UP + 1.5), (27, 32, 80.5, UP + 1.5),
                     (40, 45, 83, UP), (49, 54, 80.5, UP)):
    pillar(x0, x1, y, y + 0.5, z, z + 1.4, WALL_B, "cover")
for x0, x1, y0, y1, top, ex, ey, bx, by in ((5, 10, 96, 101, 9.0, 6.5, 98, 8.6, 99.6),
                                            (23, 29, 97, 103, 10.0, 25, 99, 27.2, 99.8),
                                            (45, 50, 96, 101, 9.0, 48.5, 98, 46.4, 99.6)):
    floor(x0, x1, y0, y1, top, BODY, comment="tower")
    entity("enemy_ranged", ex, ey, top, wave="roofs")
    entity("explosive_barrel", bx, by, top)
pickup("Points", 27.5, 101.5, 10.0)                    # for anyone who finds a way up
trigger(6, 14, 72.5, 86, UP, UP + 4, "roofs")           # no doors on this wave: it only wakes the towers up
enemies("enemy_horde", "", ((50, 78), (44, 76)), UP)
pickup("Health", 26, 76, UP + 1.5)
pickup("Ammo", 56, 84, UP)

# ====================================================================================================================
# 6. Gallery (IN): x 40.5..68.5, y 44..72, 12 m tall, entered on its north balcony. Then the vault and the ambush.
# ====================================================================================================================
floor(40.5, 68.5, 44, 72, 0)
room_walls(40.5, 68.5, 44, 72, 12.5, WALL_B)
ceiling(40.5, 68.5, 44, 72, 12.0)
door_hole_y(72, 47, 53, UP)                            # from roof 3
checkpoint(47, 53, 72.125, 72.375, UP)
barrier(47, 53, 71.75, 72, UP, UP + DOOR_H, "gallery")
solid(40.5, 68.5, 62, 72, UP - 0.5, UP, IN_FLOOR, "north balcony")
rail(40.5, 60.5, 61.75, 62, UP - 0.5, RAIL_H + 0.5, PILLAR)
ramp(60.5, 68.5, 48, 62, 0, UP, "+y", rails="low")     # the wall is on its east side
solid(40.5, 68.5, 44, 50, UP - 0.5, UP, IN_FLOOR, "south balcony")
for px in (45, 58):
    pillar(px, px + 1, 62, 63, 0, UP - 0.5)
    pillar(px, px + 1, 49, 50, 0, UP - 0.5)
for px, py in ((45, 56), (54, 55)):
    pillar(px, px + 2, py, py + 2, 0, 2.5, comment="crate")
trigger(40.5, 68.5, 66, 70.5, UP, UP + 4, "gallery")
enemies("enemy_ranged", "gallery", ((48, 47), (62, 47)), UP)       # the far balcony
enemies("enemy_ranged", "gallery", ((43, 53), (58, 52)))
enemies("enemy_horde", "gallery", ((50, 58), (44, 60), (57, 59)))
barrels(((51, 47.5), (59, 47.5)), UP)
barrels(((48, 53), (52, 60)), classname="barrel")
pickup("Health", 42, 70, UP)
pickup("Ammo", 66, 70, UP)
for y0, y1 in ((63, 70),):
    window_x(40, y0, y1, UP + 1.0, UP + 4.0)           # from the balcony: the courtyard you fought in
window_x(40, 52, 60, 7, 10.5)
for y0, y1 in ((46, 52), (56, 62), (64, 70)):
    window_x(68.5, y0, y1, 7, 10.5)
skylight(46, 63, 52, 60, 12.0)
# The vault: x 46..62, y 30..43.5, under and beyond the south balcony. Opens when the gallery is clear.
floor(46, 62, 30, 43.5, 0)
wall_x(45.5, 29.5, 43.5, 5.5, WALL_A)
wall_x(62, 29.5, 43.5, 5.5, WALL_A)
wall_y(29.5, 46, 62, 5.5, WALL_A)
ceiling(46, 62, 30, 43.5, 5.0)
door_hole_y(43.5, 51, 57, 0)
door(51, 57, 43.5, 44, 0, "gallery", 0)
# At the loot: they appear behind you, between you and the door, right beside the barrels. (They have to appear inside
# the vault: a door that is shut when the level starts leaves a gap in the navigation mesh, so enemies never walk
# through one, even once it is open.)
trigger(46, 62, 30, 34.5, 0, 4, "vault", spawn_interval=0.5)
enemies("enemy_horde", "vault", ((54, 41), (50, 40), (58, 40), (52, 38), (56, 38)))
barrels(((48, 42.3), (60, 42.3), (54, 42.6)))
pickup("Points", 50, 32)
pickup("Points", 58, 32)
pickup("Ammo", 54, 31.5)
pickup("Health", 47.5, 36)
# Clearing the ambush opens a shortcut back to the courtyard and the way on to the shrine
door_hole_x(40, 53, 59, 0)
door(40, 40.5, 53, 59, 0, "vault", 0)
door_hole_x(62, 34, 38, 0)
door(62, 62.5, 34, 38, 0, "vault", 0)
# A glass passage to the shrine: a quiet moment with a view
floor(62.5, 72.5, 34, 38, 0)
wall_y(33.5, 62.5, 72.5, 4.5, WALL_A)
wall_y(38, 62.5, 72.5, 4.5, WALL_A)
ceiling(62.5, 72.5, 34, 38, 4.0)
window_y(33.5, 64, 71, 0.75, 3.5)
window_y(38, 64, 71, 0.75, 3.5)
checkpoint(66, 66.25, 34, 38, 0)

# ====================================================================================================================
# 7. Shrine (IN): x 73..97, y 12..40, 16 m tall and mostly glass. The shield is on the tier at the south end.
# ====================================================================================================================
floor(73, 97, 20, 40, 0)
floor(73, 97, 12, 20, TIER)
room_walls(73, 97, 12, 40, 16.5, WALL_B)
ceiling(73, 97, 12, 40, 16.0)
door_hole_x(72.5, 34, 38, 0)
door(72.5, 73, 34, 38, 0, "ambush", 1)                 # shuts behind the player when the shield is taken
ramp(81, 89, 20, 32, 0, TIER, "-y")
pillar(84, 86, 15, 17, TIER, TIER + 1.0, comment="pedestal")
entity("shield_pickup", 85.0, 16.0, TIER + 1.6, wave="ambush")
trigger(84, 86, 18, 19, TIER, TIER + 4, "ambush", manual=1)
for x0, x1 in ((75, 79), (91, 95)):
    pillar(x0, x1, 19.5, 20, TIER, TIER + 1.4, WALL_B, "cover")     # to duck behind between parries
enemies("enemy_ranged", "ambush", ((77, 36), (93, 36), (93, 26)))
pickup("Health", 77, 14, TIER)
pickup("Health", 93, 14, TIER)
for x0, x1 in ((75, 83), (87, 95)):
    window_y(11.5, x0, x1, TIER + 2.0, 14)
    window_y(40, x0, x1, 6, 13)
for y0, y1 in ((22, 28), (30, 37)):
    window_x(97, y0, y1, 6, 13)
for y0, y1 in ((14, 20), (22, 30)):
    window_x(72.5, y0, y1, 8, 13)
skylight(76, 82, 22, 38, 16.0)
skylight(88, 94, 22, 38, 16.0)
door_hole_x(97, 14, 18, TIER)
door(97, 97.5, 14, 18, TIER, "ambush", 0)
bridge(97.5, 104.5, 14, 18, TIER, "x")
checkpoint(101, 101.25, 14, 18, TIER)

# ====================================================================================================================
# 8. Crossing (OUT): x 105..153, y 2..30. A canal between two roofs, crossed by grapple. Fall in: a ramp leads out.
# ====================================================================================================================
floor(105, 113, 2, 30, TIER, OUT_FLOOR, comment="ledge A")
floor(113, 145, 2, 30, PIT, OUT_FLOOR, comment="canal")
floor(145, 153, 2, 30, TIER, OUT_FLOOR, comment="ledge B")
wall_y(1.5, 104.5, 153.5, TIER + RAIL_H, BODY)
wall_y(30, 104.5, 153.5, TIER + RAIL_H, BODY)
wall_x(104.5, 2, 30, TIER + RAIL_H, BODY)
door_hole_x(104.5, 14, 18, TIER, RAIL_H)
wall_x(153, 2, 30, TIER + 5.0, WALL_A)
for px in (123, 135):
    pillar(px, px + 4, 14, 18, PIT, TIER)
ramp(113, 125, 2, 10, PIT, TIER, "-x", rails="high")   # the south wall is on its low side
ramp(133, 145, 22, 30, PIT, TIER, "+x", rails="low")   # the north wall is on its high side
for gx in (125, 137, 149):
    b.entity("grapple_point", m(gx), m(16), m(11.0))
brush("hint_trigger", [(107, 111, 10, 22, TIER, TIER + 4, CLIP)], title="GRAPPLE",
      text="Throw the shield ({throw_shield}) at a green point to be pulled to it.|Land on the pillar, then throw at the next point.",
      seconds=9)
# The whole canal, from the edge of ledge A: stepping off, grappling across or falling in all start the wave
trigger(109, 145, 2, 30, PIT - 1.0, 14, "pit")
enemies("enemy_ranged", "pit", ((151, 8), (151, 24), (149, 16)), TIER)
pickup("Ammo", 109, 6, TIER)
pickup("Points", 137, 16, TIER)
pickup("Health", 149, 10, TIER)
door_hole_x(153, 14, 18, TIER)
door(153, 153.5, 14, 18, TIER, "pit", 0)
bridge(153.5, 161, 14, 18, TIER, "x")
checkpoint(157, 157.25, 14, 18, TIER)

# ====================================================================================================================
# 9. Plaza (OUT): x 161..193, y -2..34. The hub: the upgrade station, and a bridge to each key.
# ====================================================================================================================
floor(161, 193, -2, 34, TIER, OUT_FLOOR, comment="plaza")
for y0, y1 in ((-2, 14), (18, 34)):
    rail(160.5, 161, y0, y1, TIER - 1.0, RAIL_H + 1.0)
    rail(193, 193.5, y0, y1, TIER - 1.0, RAIL_H + 1.0)
for x0, x1 in ((160.5, 177), (181, 193.5)):
    rail(x0, x1, -2.5, -2, TIER - 1.0, RAIL_H + 1.0)
    rail(x0, x1, 34, 34.5, TIER - 1.0, RAIL_H + 1.0)
for px, py in ((168, 5), (185, 5), (168, 26), (185, 26)):
    pillar(px, px + 1, py, py + 1, TIER, TIER + 5.0, comment="lamp post")
pickup("Health", 165, 2, TIER)
pickup("Health", 165, 30, TIER)
pickup("Ammo", 189, 2, TIER)
pickup("Ammo", 189, 30, TIER)

# --- Red hall (IN), north: x 161..197, y 50..86. Ranged enemies on the side platforms, grunts below. ---
bridge(177, 181, 34, 49.5, TIER, "y")
floor(161, 197, 50, 86, TIER)
room_walls(161, 197, 50, 86, 14.5, WALL_B)
ceiling(161, 197, 50, 86, 14.0)
door_hole_y(49.5, 177, 181, TIER)
door(177, 181, 49.5, 50, TIER, "gauntlet", 1)
trigger(161, 197, 51, 57, TIER, 14, "gauntlet")
for x0, x1 in ((169, 175), (183, 189)):
    pillar(x0, x1, 62, 62.5, TIER, TIER + 1.4, WALL_B, "cover")
solid(161, 169, 62, 82, TIER, LEDGE, IN_FLOOR, "platform")
solid(189, 197, 62, 82, TIER, LEDGE, IN_FLOOR, "platform")
ramp(161, 169, 54, 62, TIER, LEDGE, "+y", rails="high")
ramp(189, 197, 54, 62, TIER, LEDGE, "+y", rails="low")
enemies("enemy_ranged", "gauntlet", ((165, 68), (165, 76), (193, 68), (193, 76)), LEDGE)
enemies("enemy_horde", "gauntlet", ((171, 78), (179, 80), (187, 78), (179, 70)), TIER)
pillar(177, 181, 83, 85, TIER, TIER + 1.0, comment="key dais")
entity("level_key", 179.0, 84.0, TIER + 2.2, key="red")
pickup("Health", 179, 54, TIER)
pickup("Ammo", 165, 56, TIER)
for y0, y1 in ((54, 60), (64, 72)):
    window_x(160.5, y0, y1, 9, 13)
    window_x(197, y0, y1, 9, 13)
for x0, x1 in ((164, 174), (184, 194)):
    window_y(49.5, x0, x1, 8, 12)                      # facing the plaza
skylight(173, 185, 56, 82, 14.0)

# --- Spire (OUT), south: x 161..193, y -50..-18. The grapple climb in the open air, the blue key at the top. ---
bridge(177, 181, -18, -2, TIER, "y")
floor(161, 193, -50, -18, TIER, OUT_FLOOR, comment="spire yard")
rail(160.5, 161, -50.5, -17.5, TIER - 1.0, RAIL_H + 1.0)
rail(193, 193.5, -50.5, -17.5, TIER - 1.0, RAIL_H + 1.0)
rail(161, 193, -50.5, -50, TIER - 1.0, RAIL_H + 1.0)
for x0, x1 in ((161, 177), (181, 193)):
    rail(x0, x1, -18, -17.5, TIER - 1.0, RAIL_H + 1.0)
barrier(177, 181, -18, -17.75, TIER, TIER + DOOR_H, "tower")
trigger(161, 193, -50, -19, TIER, 34, "tower")
for px, py, top in ((183, -26, 10.0), (167, -36, 16.0), (181, -46, 22.0)):
    pillar(px, px + 4, py, py + 4, TIER, top)
for gx, gy, gz in ((185, -24, 16.0), (169, -34, 22.0), (183, -44, 28.0)):
    b.entity("grapple_point", m(gx), m(gy), m(gz))
entity("level_key", 183.0, -44.0, 24.2, key="blue")
for x0, x1 in ((161, 165), (189, 193)):                # two watchtowers
    pillar(x0, x1, -30, -22, TIER, 12.0, BODY, "watchtower")
    rail(x0, x1, -30, -29.75, 12.0)                    # the side facing the yard stays open: a rail would block their shots
    rail(x0, x1, -22.25, -22, 12.0)
rail(161, 161.25, -30, -22, 12.0)
rail(192.75, 193, -30, -22, 12.0)
enemies("enemy_ranged", "tower", ((163, -46, TIER), (191, -46, TIER), (163, -26, 12.0), (191, -26, 12.0)))
pickup("Health", 179, -22, TIER)
pickup("Ammo", 179, -39, TIER)

# ====================================================================================================================
# 10. Gatehouse (red door, blue door) and the coliseum (OUT): x 209..257, y -10..38. Godot Man drops out of the sky.
# ====================================================================================================================
floor(193.5, 208.5, 14, 18, TIER)
solid(193, 193.5, 14, 18, BASE, TIER, IN_FLOOR, "threshold")
wall_y(13.5, 193.5, 208.5, TIER + 4.5, WALL_A)
wall_y(18, 193.5, 208.5, TIER + 4.5, WALL_A)
ceiling(193.5, 208.5, 14, 18, TIER + 4.0)
brush("key_door", [(197, 197.5, 14, 18, TIER, TIER + DOOR_H, DOOR)], key="red")
brush("key_door", [(203, 203.5, 14, 18, TIER, TIER + DOOR_H, DOOR)], key="blue")
checkpoint(205.5, 205.75, 14, 18, TIER)
floor(209, 257, -10, 38, TIER, OUT_FLOOR, comment="coliseum")
room_walls(209, 257, -10, 38, 18.0, WALL_C)
door_hole_x(208.5, 14, 18, TIER)
door(208.5, 209, 14, 18, TIER, "boss", 1)              # shuts behind the player
trigger(211, 223, -10, 38, TIER, 24, "boss")
for px, py in ((225, 0), (225, 28), (243, 0), (243, 28)):
    pillar(px - 2, px + 2, py - 2, py + 2, TIER, 16.0)
b.entity("godot_boss", m(237.0), m(14.0), m(TIER) + 1, wave="boss")
b.entity("boss_reward", m(252.0), m(14.0), m(TIER) + 1)
for x0, x1 in ((215, 227), (239, 251)):
    window_y(-10.5, x0, x1, 9, 15)
    window_y(38, x0, x1, 9, 15)
for y0, y1 in ((-4, 8), (20, 32)):
    window_x(257, y0, y1, 9, 15)
pickup("Health", 211, -6, TIER)
pickup("Health", 211, 34, TIER)
pickup("Ammo", 213, 0, TIER)
pickup("Ammo", 213, 28, TIER)
pickup("Health", 254, -7, TIER)
pickup("Health", 254, 35, TIER)
pickup("Ammo", 233, -8, TIER)
pickup("Ammo", 233, 36, TIER)

# --- Under everything: falling off the level puts the player back on the last solid ground -------------------------
brush("fall_trigger", [(-80, 300, -90, 140, BASE - 8.0, BASE - 4.0, CLIP)])

# ====================================================================================================================
# Write: cut the holes out of the walls and ceilings, then check every entity has a floor under it
# ====================================================================================================================
final = []
for box, tex, comment, cuttable in SOLIDS:
    pieces = [tuple(m(v) for v in box)]
    if cuttable:
        for cut in HOLES:
            cut_units = tuple(m(v) for v in cut)
            pieces = [q for piece in pieces for q in _cut_box(piece, cut_units)]
    for q in pieces:
        b.box(*q, tex, comment)
        final.append(q)

problems = 0
for classname, x, y, z in POINTS:
    ux, uy, uz = m(x), m(y), m(z)
    if any(x0 <= x <= x1 and y0 <= y <= y1 for x0, x1, y0, y1 in WEDGES):
        continue   # on a ramp
    inside = [q for q in final if q[0] < ux < q[1] and q[2] < uy < q[3] and q[4] < uz + 8 < q[5]]
    below = [q[5] for q in final if q[0] <= ux <= q[1] and q[2] <= uy <= q[3] and q[5] <= uz + 8]
    gap = (uz - max(below)) / 32.0 if below else None
    limit = 1.0 if classname in ("pickup", "shield_pickup", "level_key") else 0.1
    if inside or gap is None or gap > limit + (2.0 if classname in ("shield_pickup", "level_key") else 0.0):
        problems += 1
        print("CHECK %s at (%s, %s, %s): %s" % (classname, x, y, z, "inside a solid" if inside else "floor is %s below" % gap))

b.write(MAP)
print("wrote", MAP, "-", b.brush_count, "brushes,", len(b.entities), "entities,", problems, "to check")
