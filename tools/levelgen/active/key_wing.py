"""Adds the key wing after the sky course to level_02.map by editing the map text in place.

Run from the project root:  python tools/levelgen/active/key_wing.py

The sky course's building gets a door in its east wall, leading to:
  Hub      a big flat room. Walking in shuts the door behind you and spawns its wave; clearing it opens the south
           door. North needs the red key, east the blue key.
  Foundry  (south) a 12 m pit. Walking onto the entrance ledge shuts the door behind you and spawns its wave, and it
           reopens when they are all dead. Pillars lead over the pit by grapple to a tower with the red key. A ramp
           climbs out of the pit, so falling costs a fight, not the level, and the horde can come up it after you.
  Stack    (north, red door) a vertical room. A ramp leads to the first balcony, then grapples go over a spire and
           up two more balconies under fire to the blue key at the top. Taking it starts a wave on the floor below.
  Vault    (east, blue door) the final arena: a raised centre and high catwalks reached by grapple. Clearing the
           wave opens a reward room.

Safe to run again: it replaces everything it made (all of it is east of x = 184 m). Hand edits there are lost.
All positions in meters, x east, y north, z up. Player reach: double jump ~3.2 m, dash ~5 m.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from editmap import MapFile, brush_bounds
from mapgen import MapBuilder, m

MAP = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "trenchbroom", "maps", "level_02.map"))

FLOOR = "world/texture_15"
WALL = "world/texture_14"
FOUNDRY_WALL = "world/texture_13_wall"
STACK_WALL = "world/texture_16"
VAULT_WALL = "world/texture_17"
HALL = "world/texture_04"
TRIM = "world/texture_01"
RAMP = "world/texture_10_stairs"
PILLAR = "world/texture_04"
DOOR = "world/texture_11_door"
CLIP = "special/clip"

F = -25.0            # floor of the building, the hub and most of the wing
T = 0.5              # wall thickness
SLAB = 1.2           # floor thickness
DOOR_H = 4.0         # doors slide 4.2 m down when they open

b = MapBuilder()


def box(x0, x1, y0, y1, z0, z1, tex=TRIM, comment=""):
    b.box(m(x0), m(x1), m(y0), m(y1), m(z0), m(z1), tex, comment)


def wall_x(x0, x1, y0, y1, z0, z1, tex, gaps=()):
    """Wall running along y, with (y0, y1, z0, z1) openings."""
    y = y0
    for gy0, gy1, gz0, gz1 in sorted(gaps):
        box(x0, x1, y, gy0, z0, z1, tex, "wall")
        if gz0 > z0:
            box(x0, x1, gy0, gy1, z0, gz0, tex, "wall sill")
        box(x0, x1, gy0, gy1, gz1, z1, tex, "wall lintel")
        y = gy1
    box(x0, x1, y, y1, z0, z1, tex, "wall")


def wall_y(y0, y1, x0, x1, z0, z1, tex, gaps=()):
    """Wall running along x, with (x0, x1, z0, z1) openings."""
    x = x0
    for gx0, gx1, gz0, gz1 in sorted(gaps):
        box(x, gx0, y0, y1, z0, z1, tex, "wall")
        if gz0 > z0:
            box(gx0, gx1, y0, y1, z0, gz0, tex, "wall sill")
        box(gx0, gx1, y0, y1, gz1, z1, tex, "wall lintel")
        x = gx1
    box(x, x1, y0, y1, z0, z1, tex, "wall")


def room(x0, x1, y0, y1, floor, top, tex, west=(), east=(), south=(), north=(), skip=()):
    """Floor and four walls just outside the given interior. skip names walls another room provides."""
    box(x0, x1, y0, y1, floor - SLAB, floor, FLOOR, "floor")
    z0 = floor - SLAB
    if "west" not in skip:
        wall_x(x0 - T, x0, y0, y1, z0, top, tex, west)
    if "east" not in skip:
        wall_x(x1, x1 + T, y0, y1, z0, top, tex, east)
    if "south" not in skip:
        wall_y(y0 - T, y0, x0 - T, x1 + T, z0, top, tex, south)
    if "north" not in skip:
        wall_y(y1, y1 + T, x0 - T, x1 + T, z0, top, tex, north)


def hall_along_x(x0, x1, y0, y1, height=5.0):
    box(x0, x1, y0, y1, F - SLAB, F, FLOOR, "hall floor")
    box(x0, x1, y0, y1, F + height, F + height + T, TRIM, "hall ceiling")
    box(x0, x1, y0 - T, y0, F - SLAB, F + height + T, HALL, "hall wall")
    box(x0, x1, y1, y1 + T, F - SLAB, F + height + T, HALL, "hall wall")


def platform(x0, x1, y0, y1, top, comment, base=None, tex=PILLAR):
    """A slab, or a solid block down to base."""
    box(x0, x1, y0, y1, base if base is not None else top - 0.8, top, tex, comment)


def door_gap(a0, a1):
    return (a0, a1, F, F + DOOR_H)


def spawn(classname, points, z, **properties):
    for x, y in points:
        b.entity(classname, m(x), m(y), m(z) + 1, **properties)


def grapples(points):
    for x, y, z in points:
        b.entity("grapple_point", m(x), m(y), m(z))


def pickup(x, y, floor, kind, **properties):
    b.entity("pickup", m(x), m(y), m(floor + 0.8), type=kind, **properties)


def wave_door(x0, x1, y0, y1, wave):
    b.brush_entity("locked_door", [(m(x0), m(x1), m(y0), m(y1), m(F), m(F + DOOR_H), DOOR)], wave=wave, starts_open=1)


def key_door(x0, x1, y0, y1, key):
    b.brush_entity("key_door", [(m(x0), m(x1), m(y0), m(y1), m(F), m(F + DOOR_H), DOOR)], key=key)


def trigger(x0, x1, y0, y1, z0, z1, wave):
    b.brush_entity("wave_trigger", [(m(x0), m(x1), m(y0), m(y1), m(z0), m(z1), CLIP)], wave=wave)


# --- The building's east wall, now with a doorway
BUILDING_FLOOR = F - SLAB
BUILDING_TOP = F + 8.5
DOOR_Y = (95.0, 101.0)
wall_x(184.0, 184.5, 87.5, 108.5, BUILDING_FLOOR, BUILDING_TOP, WALL, [(DOOR_Y[0], DOOR_Y[1], F, F + 5.0)])
hall_along_x(184.5, 189.5, 94.0, 102.0)

# --- Hub: x 190..230, y 78..118. Its south wall belongs to the foundry, which is wider.
HUB_TOP = F + 14.0
room(190.0, 230.0, 78.0, 118.0, F, HUB_TOP, WALL,
     west=[(DOOR_Y[0], DOOR_Y[1], F, F + DOOR_H)],
     east=[(95.0, 101.0, F, F + DOOR_H)],
     north=[door_gap(207.0, 213.0)],
     skip=("south",))
for px, py in ((198.0, 86.0), (222.0, 86.0), (198.0, 110.0), (222.0, 110.0)):
    box(px - 1.5, px + 1.5, py - 1.5, py + 1.5, F, F + 8.0, PILLAR, "hub pillar")
box(192.0, 197.0, 89.0, 90.0, F, F + 1.2, HALL, "hub cover")
box(223.0, 228.0, 106.0, 107.0, F, F + 1.2, HALL, "hub cover")
platform(218.0, 230.0, 110.0, 118.0, F + 5.0, "hub balcony")
platform(190.0, 202.0, 78.0, 86.0, F + 5.0, "hub balcony")
grapples([(210.0, 98.0, F + 9.0), (222.0, 106.0, F + 9.0), (198.0, 90.0, F + 9.0)])
WAVE_HUB = "hub"
trigger(192.0, 198.0, 92.0, 104.0, F, F + 5.0, WAVE_HUB)
wave_door(189.5, 190.0, 95.0, 101.0, WAVE_HUB)    # shuts behind the player
b.brush_entity("locked_door", [(m(207.0), m(213.0), m(78.0), m(78.5), m(F), m(F + DOOR_H), DOOR)], wave=WAVE_HUB)   # the way on
spawn("enemy_horde", [(204.0, 92.0), (204.0, 104.0), (216.0, 90.0), (218.0, 104.0), (210.0, 86.0), (210.0, 110.0)], F, wave=WAVE_HUB)
spawn("enemy_ranged", [(224.0, 114.0)], F + 5.0, wave=WAVE_HUB)
spawn("enemy_melee_dodger", [(212.0, 98.0), (220.0, 98.0)], F, wave=WAVE_HUB)
pickup(226.0, 112.0, F + 5.0, "Health")
pickup(192.0, 80.0, F + 5.0, "Ammo", weapon_id="rifle")
pickup(210.0, 98.0, F, "Ammo", weapon_id="shotgun")

# --- Foundry: x 186..234, y 30..77.5. The pit floor is 12 m below the entrance ledge.
PIT = F - 12.0
room(186.0, 234.0, 30.0, 77.5, PIT, HUB_TOP, FOUNDRY_WALL, north=[door_gap(207.0, 213.0)])
platform(200.0, 220.0, 66.0, 72.0, F, "foundry ledge", tex=FLOOR)
platform(200.0, 234.0, 72.0, 77.5, F, "foundry ledge", tex=FLOOR)
b.ramp(m(228.0), m(234.0), m(44.0), m(72.0), m(PIT), m(F), "+y", RAMP, "foundry ramp")   # its foot stays clear of the tower
box(227.5, 228.0, 44.0, 72.0, PIT, F + 1.0, HALL, "foundry ramp wall")   # enemies can't climb its side: they use the foot

P1 = (200.0, 206.0, 54.0, 60.0, F - 3.0)
P2 = (214.0, 220.0, 46.0, 52.0, F + 1.0)
P3 = (198.0, 204.0, 36.0, 42.0, F + 5.0)
TOWER = (212.0, 226.0, 30.0, 38.0, F + 9.0)
for name, (x0, x1, y0, y1, top) in (("pillar 1", P1), ("pillar 2", P2), ("pillar 3", P3), ("key tower", TOWER)):
    platform(x0, x1, y0, y1, top, name, base=PIT)
box(190.0, 194.0, 60.0, 64.0, PIT, PIT + 1.4, HALL, "pit cover")
box(208.0, 212.0, 56.0, 58.0, PIT, PIT + 1.4, HALL, "pit cover")
box(190.0, 192.0, 44.0, 50.0, PIT, PIT + 1.4, HALL, "pit cover")
box(218.0, 224.0, 60.0, 62.0, PIT, PIT + 1.4, HALL, "pit cover")
grapples([
    (203.0, 57.0, P1[4] + 5.0),
    (217.0, 49.0, P2[4] + 5.0),
    (201.0, 39.0, P3[4] + 5.0),
    (216.0, 34.0, TOWER[4] + 5.0),
])
WAVE_RED = "foundry"
spawn("enemy_melee_dodger", [(203.0, 57.0)], P1[4], wave=WAVE_RED)
spawn("enemy_ranged", [(217.0, 49.0)], P2[4], wave=WAVE_RED)
spawn("enemy_melee_dodger", [(201.0, 39.0)], P3[4], wave=WAVE_RED)
spawn("enemy_horde", [(196.0, 56.0), (204.0, 62.0), (214.0, 64.0), (224.0, 52.0), (192.0, 40.0), (208.0, 46.0)], PIT, wave=WAVE_RED)
b.entity("level_key", m(219.0), m(34.0), m(TOWER[4] + 1.2), key="red")
pickup(217.0, 47.0, P2[4], "Health")
pickup(231.0, 40.0, PIT + 0.3, "Ammo", weapon_id="lightning")
pickup(192.0, 62.0, PIT + 1.4, "Points")

trigger(200.0, 220.0, 66.0, 75.5, F, F + 5.0, WAVE_RED)   # past the door, so it can't shut on the player
wave_door(207.0, 213.0, 77.5, 78.0, WAVE_RED)
spawn("enemy_horde", [(208.0, 36.0), (190.0, 54.0)], PIT, wave=WAVE_RED)
spawn("enemy_melee_dodger", [(205.0, 69.0), (215.0, 69.0)], F, wave=WAVE_RED)
spawn("enemy_flyer", [(195.0, 50.0), (226.0, 58.0)], F + 4.0, wave=WAVE_RED)
key_door(207.0, 213.0, 118.0, 118.5, "red")

# --- Stack: a short hall north of the red door, then a tall room climbed by balconies. x 186..234, y 124.5..170.
hall_x0, hall_x1 = 206.0, 214.0
box(hall_x0, hall_x1, 118.5, 124.0, F - SLAB, F, FLOOR, "hall floor")
box(hall_x0, hall_x1, 118.5, 124.0, F + DOOR_H + 1.0, F + DOOR_H + 1.5, TRIM, "hall ceiling")
box(hall_x0 - T, hall_x0, 118.5, 124.0, F - SLAB, F + DOOR_H + 1.5, HALL, "hall wall")
box(hall_x1, hall_x1 + T, 118.5, 124.0, F - SLAB, F + DOOR_H + 1.5, HALL, "hall wall")

STACK_TOP = 10.0
T1 = F + 8.0
T2 = F + 16.0
T3 = F + 24.0
room(186.0, 234.0, 124.5, 170.0, F, STACK_TOP, STACK_WALL, south=[door_gap(207.0, 213.0)])
b.ramp(m(186.0), m(198.0), m(126.0), m(146.0), m(F), m(T1), "+y", RAMP, "stack ramp")
box(198.0, 198.5, 126.0, 146.0, F, T1 + 1.2, HALL, "stack ramp wall")
platform(186.0, 198.0, 146.0, 170.0, T1, "balcony 1", tex=FLOOR)
platform(204.0, 216.0, 136.0, 148.0, F + 12.0, "stack spire", base=F)
platform(222.0, 234.0, 126.0, 150.0, T2, "balcony 2", tex=FLOOR)
platform(198.0, 234.0, 160.0, 170.0, T3, "balcony 3", tex=FLOOR)
box(198.0, 198.5, 146.0, 160.0, T1, T1 + 1.2, HALL, "balcony 1 rail")
box(221.5, 222.0, 126.0, 150.0, T2, T2 + 1.2, HALL, "balcony 2 rail")
box(198.0, 234.0, 159.5, 160.0, T3, T3 + 1.2, HALL, "balcony 3 rail")
box(212.0, 216.0, 154.0, 158.0, F, F + 3.0, PILLAR, "stack cover")
box(222.0, 226.0, 154.0, 158.0, F, F + 3.0, PILLAR, "stack cover")
box(202.0, 206.0, 128.0, 130.0, F, F + 1.4, HALL, "stack cover")
grapples([
    (210.0, 142.0, F + 17.0),     # over the spire, from the first balcony
    (228.0, 138.0, T2 + 5.0),     # over the second balcony, from the spire
    (228.0, 156.0, T3 + 3.0),     # up to the third balcony, across the gap
    (192.0, 134.0, T1 + 6.0),     # back up from the floor without walking round
])
spawn("enemy_horde", [(208.0, 132.0), (220.0, 130.0), (200.0, 154.0), (218.0, 162.0), (228.0, 164.0), (204.0, 166.0)], F)
spawn("enemy_melee_dodger", [(192.0, 152.0), (192.0, 164.0)], T1)
spawn("enemy_melee_dodger", [(210.0, 142.0)], F + 12.0)
spawn("enemy_ranged", [(228.0, 134.0)], T2)
spawn("enemy_melee_dodger", [(228.0, 146.0)], T2)
spawn("enemy_melee_dodger", [(204.0, 165.0)], T3)
b.entity("level_key", m(216.0), m(165.0), m(T3 + 1.2), key="blue")
pickup(192.0, 158.0, T1, "Ammo", weapon_id="shotgun")
pickup(210.0, 138.0, F + 12.0, "Health")
pickup(230.0, 148.0, T2, "Ammo", weapon_id="rifle")
pickup(228.0, 166.0, T3, "Health")

WAVE_BLUE = "stack"
trigger(198.0, 234.0, 160.0, 170.0, T3, T3 + 5.0, WAVE_BLUE)
wave_door(207.0, 213.0, 124.0, 124.5, WAVE_BLUE)
spawn("enemy_horde", [(190.0, 130.0), (210.0, 128.0), (228.0, 128.0), (214.0, 150.0), (196.0, 164.0), (224.0, 160.0)], F, wave=WAVE_BLUE)
spawn("enemy_melee_dodger", [(200.0, 140.0), (220.0, 142.0)], F, wave=WAVE_BLUE)
spawn("enemy_flyer", [(200.0, 150.0), (228.0, 152.0)], T3 + 2.0, wave=WAVE_BLUE)

# --- Blue door, hall and the Vault: x 238.5..282, y 76..120
key_door(230.0, 230.5, 95.0, 101.0, "blue")
hall_along_x(230.5, 238.0, 94.0, 102.0)
VAULT_TOP = F + 16.0
room(238.5, 282.0, 76.0, 120.0, F, VAULT_TOP, VAULT_WALL,
     west=[(95.0, 101.0, F, F + DOOR_H)], east=[(95.0, 101.0, F, F + DOOR_H)])

VC = F + 3.0     # raised centre
platform(252.0, 268.0, 92.0, 104.0, VC, "vault centre", base=F)
b.ramp(m(256.0), m(264.0), m(86.0), m(92.0), m(F), m(VC), "+y", RAMP, "vault ramp")
b.ramp(m(256.0), m(264.0), m(104.0), m(110.0), m(F), m(VC), "-y", RAMP, "vault ramp")
for wall_x0 in (255.5, 264.0):
    box(wall_x0, wall_x0 + T, 86.0, 92.0, F, VC + 1.0, HALL, "vault ramp wall")
    box(wall_x0, wall_x0 + T, 104.0, 110.0, F, VC + 1.0, HALL, "vault ramp wall")
CATWALK = F + 7.0
platform(238.5, 282.0, 76.0, 82.0, CATWALK, "south catwalk", tex=FLOOR)
platform(238.5, 282.0, 114.0, 120.0, CATWALK, "north catwalk", tex=FLOOR)
for px, py in ((246.0, 90.0), (274.0, 90.0), (246.0, 106.0), (274.0, 106.0)):
    box(px - 1.5, px + 1.5, py - 1.5, py + 1.5, F, F + 5.0, PILLAR, "vault pillar")
grapples([
    (260.0, 98.0, VC + 7.0),
    (246.0, 86.0, CATWALK + 3.0),
    (274.0, 86.0, CATWALK + 3.0),
    (246.0, 110.0, CATWALK + 3.0),
    (274.0, 110.0, CATWALK + 3.0),
])
WAVE_VAULT = "vault"
trigger(240.0, 246.0, 92.0, 104.0, F, F + 5.0, WAVE_VAULT)
wave_door(238.0, 238.5, 95.0, 101.0, WAVE_VAULT)
b.brush_entity("locked_door", [(m(282.0), m(282.5), m(95.0), m(101.0), m(F), m(F + DOOR_H), DOOR)], wave=WAVE_VAULT)
spawn("enemy_horde", [(250.0, 84.0), (262.0, 84.0), (270.0, 88.0), (278.0, 96.0), (250.0, 112.0), (262.0, 112.0),
                      (270.0, 108.0), (278.0, 104.0), (248.0, 98.0), (272.0, 98.0), (242.0, 84.0), (242.0, 112.0)], F, wave=WAVE_VAULT)
spawn("enemy_melee_dodger", [(256.0, 98.0), (264.0, 98.0)], VC, wave=WAVE_VAULT)
spawn("enemy_melee_dodger", [(276.0, 92.0), (276.0, 104.0)], F, wave=WAVE_VAULT)
spawn("enemy_ranged", [(252.0, 79.0), (268.0, 117.0)], CATWALK, wave=WAVE_VAULT)
spawn("enemy_melee_dodger", [(268.0, 79.0), (252.0, 117.0)], CATWALK, wave=WAVE_VAULT)
spawn("enemy_flyer", [(270.0, 88.0), (270.0, 108.0)], F + 7.0, wave=WAVE_VAULT)
pickup(260.0, 98.0, VC, "Health")
pickup(244.0, 79.0, CATWALK, "Ammo", weapon_id="shotgun")
pickup(276.0, 117.0, CATWALK, "Health")
pickup(276.0, 79.0, CATWALK, "Ammo", weapon_id="lightning")

# Pistol ammo along the whole route
for x, y, floor in ((218.0, 92.0, F), (205.0, 69.0, F), (200.0, 50.0, PIT), (200.0, 132.0, F), (226.0, 128.0, T2),
                    (252.0, 84.0, F), (268.0, 112.0, F), (286.0, 95.0, F)):
    pickup(x, y, floor, "Ammo", weapon_id="pistol")

# Flamethrower ammo: mostly where melee enemies crowd
for x, y, floor in ((202.0, 106.0, F), (214.0, 70.0, F), (216.0, 56.0, PIT), (192.0, 150.0, T1), (220.0, 136.0, F),
                    (250.0, 110.0, F), (270.0, 84.0, F)):
    pickup(x, y, floor, "Ammo", weapon_id="flamethrower")

# Reward room behind the vault's far door
room(282.5, 292.0, 92.0, 104.0, F, F + 5.5, TRIM, skip=("west",))
box(282.0, 282.5, 91.5, 95.0, F - SLAB, F + 5.5, VAULT_WALL, "reward wall")
box(282.0, 282.5, 101.0, 104.5, F - SLAB, F + 5.5, VAULT_WALL, "reward wall")
box(282.5, 292.0, 92.0, 104.0, F + 5.5, F + 6.0, TRIM, "reward roof")
for y, kind in ((95.0, "Points"), (98.0, "Health"), (101.0, "Points")):
    pickup(289.0, y, F, kind)

# --- Write it: drop this wing's previous version, then add the new one
LIMIT = m(184.0)
mf = MapFile(MAP)
removed_brushes = mf.remove_world_brushes(lambda bounds: bounds[0][0] >= LIMIT)


def in_wing(e):
    origin = e.origin()
    if origin is not None:
        return origin[0] > LIMIT
    if e.classname == "worldspawn":
        return False
    faces = e.text[e.text.index("{"):]
    return bool(faces.count("(")) and brush_bounds(faces)[0][0] >= LIMIT


removed_entities = mf.remove(in_wing)
for text in b.brushes:
    mf.add_world_brush(text)
for text in b.entities:
    mf.add(text)
mf.save()
print("replaced", removed_brushes, "brushes and", removed_entities, "entities with", len(b.brushes), "and", len(b.entities), "->", MAP)
