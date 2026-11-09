"""Builds trenchbroom/maps/level_01.map: the true level 1, acts 1 to 4 (pistol, the shield, the grapple), and a stub for what follows.

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
  Exit       corridor with a checkpoint, then act 2: the first ranged enemies.
  Cover hall   28 x 24 m with four low walls. Walking in shuts the door behind you (wave "cover"): 2 ranged enemies at
             the far end and a grunt that rushes you. Teaches that their energy balls can be dodged or ducked behind.
  Gallery    36 x 24 m with four pillars and a raised balcony on the east side, reached by a ramp (wave "gallery"):
             2 ranged enemies on the balcony, 2 on the floor and 3 grunts. Ammo, health and points around.
  Exit       corridor with a checkpoint, then act 3: getting the shield.
  Stair hall   the corridor turns east into a 24 x 28 m hall, 16 m tall. A ramp climbs to a tier along the north wall
             with the shield floating on a pedestal. Taking it unlocks the shield, pauses the game with a window that
             explains it, then shuts the door behind you: three ranged enemies on the floor below open fire (wave
             "ambush"), so the first thing the player does with the shield is parry.
  Exit       corridor east (checkpoint) to act 4.
  The pit    two ledges 40 m apart over a 6 m pit, with two pillars between. Every gap is crossed by throwing the shield at
             the green grapple point above the next platform. Landing on the first pillar starts a wave (wave "pit"):
             three ranged enemies on the far ledge. Fall in and a ramp leads out on each side.
  Exit       corridor with a checkpoint, then a placeholder room where act 5 will go.
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
BALCONY = 3.0           # height of the gallery balcony
TIER = 4.0              # height of the shrine tier, the corridors after it and the ledges either side of the pit
PIT = -2.0              # the pit floor
T = 0.5                 # wall thickness (the grid's default)

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
g.add(-2, 32, 4, 37, ceiling=ROOM_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_B, ceiling_tex=CEILING)     # cover hall
g.add(1, 38, 1, 43, ceiling=CORRIDOR_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)  # corridor
g.add(-3, 44, 5, 49, ceiling=ROOM_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_C, ceiling_tex=CEILING)     # gallery
g.add(3, 46, 5, 49, floor=BALCONY, ceiling=ROOM_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_C, ceiling_tex=CEILING)  # balcony
g.add(1, 50, 1, 53, ceiling=CORRIDOR_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)  # exit corridor
g.add(1, 54, 7, 54, ceiling=CORRIDOR_HEIGHT, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)  # corridor turning east
g.add(8, 52, 13, 58, ceiling=16.0, floor_tex=FLOOR, wall_tex=WALL_B, ceiling_tex=CEILING)            # stair hall
g.add(8, 57, 13, 58, floor=TIER, ceiling=16.0, floor_tex=FLOOR, wall_tex=WALL_B, ceiling_tex=CEILING)  # the shrine on its upper tier
g.add(14, 57, 17, 57, floor=TIER, ceiling=TIER + 4.0, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)  # corridor
g.add(18, 54, 19, 60, floor=TIER, ceiling=24.0, floor_tex=FLOOR, wall_tex=WALL_C, ceiling_tex=CEILING)  # ledge A
g.add(20, 54, 27, 60, floor=PIT, ceiling=24.0, floor_tex=FLOOR, wall_tex=WALL_C, ceiling_tex=CEILING)   # the pit
g.add(28, 54, 29, 60, floor=TIER, ceiling=24.0, floor_tex=FLOOR, wall_tex=WALL_C, ceiling_tex=CEILING)  # ledge B
g.add(30, 57, 31, 57, floor=TIER, ceiling=TIER + 4.0, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)  # corridor
g.add(32, 55, 35, 59, floor=TIER, ceiling=12.0, floor_tex=FLOOR, wall_tex=WALL_A, ceiling_tex=CEILING)  # placeholder for act 5
# --- Windows and skylights -----------------------------------------------------------------------------------------
# Openings are cut out of the walls and ceilings the grid builds, with a glass pane in each (the glass shows the neon
# sky outside). The panes break like any window (one pistol shot) and have an invisible clip block behind them, so a
# broken pane still leaves nothing to fall out through.
HOLES = []        # (x0, x1, y0, y1, z0, z1) in map units: anything the grid builds that overlaps one is cut
WINDOWS = []      # brush entities to add after the build


def _cut_box(box, hole):
    x0, x1, y0, y1, z0, z1 = box
    hx0, hx1, hy0, hy1, hz0, hz1 = hole
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
    if z0 < max(z0, hz0):
        pieces.append((cx0, cx1, cy0, cy1, z0, hz0))
    if min(z1, hz1) < z1:
        pieces.append((cx0, cx1, cy0, cy1, hz1, z1))
    return pieces


_plain_box = b.box


def _box_with_holes(x0, x1, y0, y1, z0, z1, texture="world/texture_15", comment=""):
    pieces = [(x0, x1, y0, y1, z0, z1)]
    for hole in HOLES:
        pieces = [q for piece in pieces for q in _cut_box(piece, hole)]
    for q in pieces:
        _plain_box(*q, texture, comment)


b.box = _box_with_holes
GLASS = "world/texture_12_window"
WINDOW_HEALTH = 20      # one pistol shot (25) breaks a pane


def wall_window_x(wall_x, side, y0, y1, z0, z1):
    """A window in a wall that runs along y at x = wall_x (side -1: the wall is just west of the line, +1: east of it)."""
    lo, hi = (wall_x - T, wall_x) if side < 0 else (wall_x, wall_x + T)
    HOLES.append((m(lo) - 2, m(hi) + 2, m(y0), m(y1), m(z0), m(z1)))
    WINDOWS.append(((m(lo) + 3, m(lo) + 6, m(y0), m(y1), m(z0), m(z1)), (m(lo) + 6, m(hi), m(y0), m(y1), m(z0), m(z1))))


def wall_window_y(wall_y, side, x0, x1, z0, z1):
    """A window in a wall that runs along x at y = wall_y."""
    lo, hi = (wall_y - T, wall_y) if side < 0 else (wall_y, wall_y + T)
    HOLES.append((m(x0), m(x1), m(lo) - 2, m(hi) + 2, m(z0), m(z1)))
    WINDOWS.append(((m(x0), m(x1), m(lo) + 3, m(lo) + 6, m(z0), m(z1)), (m(x0), m(x1), m(lo) + 6, m(hi), m(z0), m(z1))))


def skylight(x0, x1, y0, y1, ceiling):
    """An opening in the ceiling of a room whose ceiling is at `ceiling`."""
    lo, hi = ceiling, ceiling + T
    HOLES.append((m(x0), m(x1), m(y0), m(y1), m(lo) - 2, m(hi) + 2))
    WINDOWS.append(((m(x0), m(x1), m(y0), m(y1), m(lo) + 3, m(lo) + 6), (m(x0), m(x1), m(y0), m(y1), m(lo) + 6, m(hi))))


# Yard (x -8..20, y 36..64, 8 m tall)
for y0, y1 in ((42.0, 47.0), (53.0, 58.0)):
    wall_window_x(-8.0, -1, y0, y1, 3.0, 6.5)
    wall_window_x(20.0, 1, y0, y1, 3.0, 6.5)
skylight(-5.0, -1.0, 42.0, 58.0, ROOM_HEIGHT)
skylight(13.0, 17.0, 42.0, 58.0, ROOM_HEIGHT)
# Barrel hall (x -12..24, y 84..112)
for y0, y1 in ((89.0, 94.0), (98.0, 103.0), (106.0, 110.0)):
    wall_window_x(24.0, 1, y0, y1, 3.0, 6.5)
for x0, x1 in ((-8.0, -3.0), (14.0, 20.0)):
    wall_window_y(112.0, 1, x0, x1, 4.0, 7.0)
skylight(-9.0, -3.0, 92.0, 106.0, ROOM_HEIGHT)
skylight(8.0, 16.0, 88.0, 94.0, ROOM_HEIGHT)
# Cover hall (x -8..20, y 128..152)
for y0, y1 in ((133.0, 138.0), (143.0, 148.0)):
    wall_window_x(-8.0, -1, y0, y1, 3.0, 6.5)
    wall_window_x(20.0, 1, y0, y1, 3.0, 6.5)
skylight(0.0, 12.0, 136.0, 144.0, ROOM_HEIGHT)
# Gallery (x -12..24, y 176..200)
for y0, y1 in ((180.0, 185.0), (190.0, 195.0)):
    wall_window_x(-12.0, -1, y0, y1, 3.0, 6.5)
for x0, x1 in ((-8.0, -3.0), (-0.0, 4.0)):
    wall_window_y(200.0, 1, x0, x1, 3.0, 6.5)
wall_window_y(200.0, 1, 16.0, 21.0, BALCONY + 2.0, BALCONY + 5.0)
skylight(-9.0, -3.0, 180.0, 196.0, ROOM_HEIGHT)
skylight(8.0, 14.0, 180.0, 186.0, ROOM_HEIGHT)
# Stair hall (x 32..56, y 208..236, 16 m tall)
for x0, x1 in ((35.0, 40.0), (44.0, 49.0), (51.0, 55.0)):
    wall_window_y(208.0, -1, x0, x1, 8.0, 13.0)
for y0, y1 in ((210.0, 214.0), (222.0, 227.0), (232.0, 235.0)):
    wall_window_x(32.0, -1, y0, y1, 8.0, 13.0)
for y0, y1 in ((211.0, 217.0), (220.0, 226.0)):
    wall_window_x(56.0, 1, y0, y1, 6.0, 12.0)
skylight(34.0, 39.0, 210.0, 226.0, 16.0)
skylight(48.0, 54.0, 210.0, 226.0, 16.0)
# The pit (x 72..120, y 216..244, 24 m tall)
for x0, x1 in ((76.0, 86.0), (92.0, 102.0), (108.0, 118.0)):
    wall_window_y(244.0, 1, x0, x1, 10.0, 20.0)
    wall_window_y(216.0, -1, x0, x1, 10.0, 20.0)
skylight(76.0, 82.0, 224.0, 236.0, 24.0)
skylight(92.0, 108.0, 222.0, 238.0, 24.0)
skylight(114.0, 118.0, 224.0, 236.0, 24.0)

g.build()
b.box = _plain_box
for pane, clip in WINDOWS:
    b.brush_entity("window", [pane + (GLASS,)], health=WINDOW_HEALTH)
    _plain_box(*clip, CLIP, "window clip")


def box(x0, x1, y0, y1, z0, z1, tex, comment=""):
    b.box(m(x0), m(x1), m(y0), m(y1), m(z0), m(z1), tex, comment)


def entity(classname, x, y, z=0.0, **properties):
    b.entity(classname, m(x), m(y), m(z) + 1, **properties)


def door(x0, x1, y, wave, starts_open):
    """A door across a corridor, 0.5 m thick, from y to y + 0.5."""
    b.brush_entity("locked_door", [(m(x0), m(x1), m(y), m(y + 0.5), m(0), m(CORRIDOR_HEIGHT), DOOR)],
                   wave=wave, starts_open=starts_open)


def door_x(x, y0, y1, wave, starts_open, z0=0.0):
    """A door across a corridor that runs east-west, 0.5 m thick, from x to x + 0.5, 4 m tall from z0."""
    b.brush_entity("locked_door", [(m(x), m(x + 0.5), m(y0), m(y1), m(z0), m(z0 + CORRIDOR_HEIGHT), DOOR)],
                   wave=wave, starts_open=starts_open)


def ramp_x(x0, x1, y0, y1, z_base, z_top, rises_toward, tex, comment="ramp"):
    """Wedge that rises toward +x or -x (mapgen's ramp only rises along y)."""
    a, bb, c, d = (x0, y0, z_base), (x1, y0, z_base), (x1, y1, z_base), (x0, y1, z_base)
    if rises_toward == "+x":
        e, f = (x1, y0, z_top), (x1, y1, z_top)
        faces = [[a, bb, c, d], [a, d, f, e], [bb, c, f, e], [a, bb, e], [d, c, f]]
    else:
        e, f = (x0, y0, z_top), (x0, y1, z_top)
        faces = [[a, bb, c, d], [bb, c, f, e], [a, d, f, e], [a, bb, e], [d, c, f]]
    b.convex([[tuple(m(v) for v in p) for p in face] for face in faces], tex, comment)


def trigger(x0, x1, y0, y1, wave, z1=ROOM_HEIGHT):
    b.brush_entity("wave_trigger", [(m(x0), m(x1), m(y0), m(y1), m(0), m(z1), CLIP)], wave=wave)


# --- Ramp up to the platform (south face of it, rising north) ---
b.ramp(m(-12), m(-8), m(88), m(96), m(0), m(PLATFORM), "+y", RAMP, "platform ramp")

# --- Ramp up to the balcony ---
b.ramp(m(12), m(16), m(176), m(184), m(0), m(BALCONY), "+y", RAMP, "balcony ramp")

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
trigger(-8.0, 20.0, 37.0, 43.0, "yard")
for ex, ey in ((-4.0, 58.0), (8.0, 60.0), (17.0, 58.0)):
    entity("enemy_horde", ex, ey, wave="yard")
entity("pickup", -6.0, 42.0, 0.8, type="Ammo", weapon_id="pistol")
entity("pickup", 18.0, 40.0, 0.8, type="Health")

# --- Barrel hall ---
door(4.0, 8.0, 83.5, "hall", 1)
door(4.0, 8.0, 112.0, "hall", 0)
trigger(-12.0, 24.0, 85.0, 91.0, "hall")
entity("enemy_horde", -4.0, 100.0, PLATFORM, wave="hall")      # on the platform: z is its floor height
for ex, ey in ((6.0, 106.0), (14.0, 104.0), (18.0, 96.0), (10.0, 108.0)):
    entity("enemy_horde", ex, ey, wave="hall")
for bx, by in ((12.0, 98.0), (14.0, 98.0), (13.0, 100.5)):
    entity("explosive_barrel", bx, by)
entity("barrel", 20.0, 92.0)
entity("pickup", -8.0, 108.0, PLATFORM + 0.8, type="Ammo", weapon_id="pistol")
entity("pickup", -4.0, 108.0, PLATFORM + 0.8, type="Points")
entity("pickup", -8.0, 104.0, PLATFORM + 0.8, type="Points")
entity("pickup", 20.0, 88.0, 0.8, type="Health")

# --- Exit: a checkpoint in the corridor ---
b.brush_entity("checkpoint", [(m(4.0), m(8.0), m(120.0), m(121.0), m(0), m(CORRIDOR_HEIGHT), CLIP)])

# --- Cover hall: low walls to duck behind (1.4 m high: taller than the player's crouch, below an enemy's eyeline) ---
# Enemies only notice the player within about 18 m (their vision area), so the waves are placed close to the trigger.
for x0, x1, y in ((-4.0, 2.0, 138.0), (10.0, 16.0, 138.0), (2.0, 8.0, 143.0), (-6.0, -2.0, 143.0)):
    box(x0, x1, y, y + 0.5, 0.0, 1.4, WALL_B, "cover")
door(4.0, 8.0, 127.5, "cover", 1)
door(4.0, 8.0, 152.0, "cover", 0)
trigger(-8.0, 20.0, 129.0, 135.0, "cover")
for ex, ey in ((-2.0, 149.0), (14.0, 149.0)):
    entity("enemy_ranged", ex, ey, wave="cover")
entity("enemy_horde", 6.0, 148.0, wave="cover")
entity("pickup", -6.0, 132.0, 0.8, type="Health")
entity("pickup", 18.0, 132.0, 0.8, type="Ammo", weapon_id="pistol")

# --- Gallery ---
for px, py in ((-4.0, 186.0), (4.0, 186.0), (-4.0, 192.0), (4.0, 192.0)):
    box(px - 1.0, px + 1.0, py - 1.0, py + 1.0, 0.0, ROOM_HEIGHT, PILLAR, "pillar")
door(4.0, 8.0, 175.5, "gallery", 1)
door(4.0, 8.0, 200.0, "gallery", 0)
trigger(-12.0, 24.0, 177.0, 183.0, "gallery")
for ex, ey in ((20.0, 192.0), (18.0, 195.0)):
    entity("enemy_ranged", ex, ey, BALCONY, wave="gallery")
for ex, ey in ((-6.0, 194.0), (6.0, 197.0)):
    entity("enemy_ranged", ex, ey, wave="gallery")
for ex, ey in ((-6.0, 188.0), (2.0, 190.0), (8.0, 190.0)):
    entity("enemy_horde", ex, ey, wave="gallery")
entity("pickup", -8.0, 179.0, 0.8, type="Health")
entity("pickup", 20.0, 179.0, 0.8, type="Ammo", weapon_id="pistol")
entity("pickup", 20.0, 188.0, BALCONY + 0.8, type="Points")
entity("pickup", 22.0, 196.0, BALCONY + 0.8, type="Points")
entity("pickup", -10.0, 197.0, 0.8, type="Ammo", weapon_id="pistol")
b.brush_entity("checkpoint", [(m(4.0), m(8.0), m(208.0), m(209.0), m(0), m(CORRIDOR_HEIGHT), CLIP)])

# --- Act 3: the corridor turns east into a tall hall; the ramp climbs to a tier with the shield on a pedestal ---
b.ramp(m(40), m(44), m(216), m(228), m(0), m(TIER), "+y", RAMP, "stair ramp")
box(43.0, 45.0, 231.0, 233.0, TIER, TIER + 1.0, PILLAR, "pedestal")
entity("shield_pickup", 44.0, 232.0, TIER + 1.6, wave="ambush")
b.brush_entity("wave_trigger", [(m(43.0), m(45.0), m(229.0), m(230.0), m(TIER), m(TIER + 4.0), CLIP)], wave="ambush", manual=1)
door_x(31.5, 216.0, 220.0, "ambush", 1)
door_x(56.0, 228.0, 232.0, "ambush", 0, TIER)
for ex, ey in ((36.0, 212.0), (52.0, 212.0), (52.0, 222.0)):
    entity("enemy_ranged", ex, ey, wave="ambush")
entity("pickup", 36.0, 232.0, TIER + 0.8, type="Health")
entity("pickup", 52.0, 232.0, TIER + 0.8, type="Health")
b.brush_entity("checkpoint", [(m(64.0), m(65.0), m(228.0), m(232.0), m(TIER), m(TIER + 4.0), CLIP)])

# --- Act 4: the pit. Two ledges 40 m apart with two pillars between: every gap is crossed by throwing the shield at
# the green grapple point above the next platform. Falling is a 6 m drop into the pit, with a ramp out on each side. ---
box(72.0, 80.0, 216.0, 244.0, PIT - 0.5, -0.5, WALL_C, "ledge A support")
box(112.0, 120.0, 216.0, 244.0, PIT - 0.5, -0.5, WALL_C, "ledge B support")
for px in (90.0, 102.0):
    box(px, px + 4.0, 228.0, 232.0, PIT - 0.5, TIER, PILLAR, "pillar")
ramp_x(80.0, 92.0, 216.0, 220.0, PIT, TIER, "-x", RAMP, "pit ramp A")
ramp_x(100.0, 112.0, 240.0, 244.0, PIT, TIER, "+x", RAMP, "pit ramp B")
for gx in (92.0, 104.0, 116.0):
    b.entity("grapple_point", m(gx), m(230.0), m(11.0))
b.brush_entity("hint_trigger", [(m(74.0), m(78.0), m(224.0), m(236.0), m(TIER), m(TIER + 4.0), CLIP)],
               title="GRAPPLE",
               text="Throw the shield ({throw_shield}) at a green point to be pulled to it.|Land on the pillar, then throw at the next point.|Fall in and there is a ramp out.",
               seconds=9)
# The whole pit, from the edge of ledge A: stepping off, grappling across or falling in all start the wave (a trigger on
# the first pillar alone could be skipped, and then the exit door never opened)
b.brush_entity("wave_trigger", [(m(76.0), m(112.0), m(216.0), m(244.0), m(PIT - 1.0), m(14.0), CLIP)], wave="pit")
door_x(120.0, 228.0, 232.0, "pit", 0, TIER)
for ex, ey in ((118.0, 222.0), (118.0, 238.0), (116.0, 230.0)):
    entity("enemy_ranged", ex, ey, TIER, wave="pit")
entity("pickup", 76.0, 220.0, TIER + 0.8, type="Ammo", weapon_id="pistol")
entity("pickup", 104.0, 230.0, TIER + 0.8, type="Points")
entity("pickup", 116.0, 224.0, TIER + 0.8, type="Health")
b.brush_entity("checkpoint", [(m(124.0), m(125.0), m(228.0), m(232.0), m(TIER), m(TIER + 4.0), CLIP)])

b.write(MAP)
print("wrote", MAP, "-", b.brush_count, "brushes,", len(b.entities), "entities")
