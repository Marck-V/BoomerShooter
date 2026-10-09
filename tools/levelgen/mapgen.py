"""Tiny helpers for writing TrenchBroom (Valve 220) .map files from code.

Coordinates are Quake units: X/Y are the floor plane, Z is up, 32 units = 1 meter (same as the
func_godot map settings). Every brush is an axis-aligned box.
"""

UNITS_PER_METER = 32


def m(meters):
    """Meters to map units."""
    return int(round(meters * UNITS_PER_METER))


# (plane points, u axis, v axis) per face, matching the winding TrenchBroom/func_godot expect
def _faces(x0, x1, y0, y1, z0, z1):
    return [
        (((x0, y1, z1), (x0, y0, z1), (x0, y0, z0)), (0, -1, 0), (0, 0, -1)),   # -X
        (((x0, y0, z1), (x1, y0, z1), (x1, y0, z0)), (1, 0, 0), (0, 0, -1)),    # -Y
        (((x1, y0, z0), (x1, y1, z0), (x0, y1, z0)), (-1, 0, 0), (0, -1, 0)),   # -Z
        (((x0, y1, z1), (x1, y1, z1), (x1, y0, z1)), (1, 0, 0), (0, -1, 0)),    # +Z
        (((x1, y1, z0), (x1, y1, z1), (x0, y1, z1)), (-1, 0, 0), (0, 0, -1)),   # +Y
        (((x1, y0, z1), (x1, y1, z1), (x1, y1, z0)), (0, 1, 0), (0, 0, -1)),    # +X
    ]


class MapBuilder:
    def __init__(self):
        self.brushes = []
        self.entities = []

    def box(self, x0, x1, y0, y1, z0, z1, texture="world/texture_15", comment=""):
        """Axis-aligned solid box between the given coordinates (map units)."""
        assert x0 < x1 and y0 < y1 and z0 < z1, (x0, x1, y0, y1, z0, z1)
        lines = ["// brush %d%s" % (len(self.brushes), (" - " + comment) if comment else ""), "{"]
        for points, u, v in _faces(x0, x1, y0, y1, z0, z1):
            plane = " ".join("( %d %d %d )" % p for p in points)
            lines.append("%s %s [ %d %d %d 0 ] [ %d %d %d 0 ] 90 0.125 0.125" % ((plane, texture) + u + v))
        lines.append("}")
        self.brushes.append("\n".join(lines))

    def entity(self, classname, x, y, z, **properties):
        lines = ["// entity %d" % (len(self.entities) + 1), "{", '"classname" "%s"' % classname,
                 '"origin" "%d %d %d"' % (x, y, z)]
        for key, value in properties.items():
            lines.append('"%s" "%s"' % (key, value))
        lines.append("}")
        self.entities.append("\n".join(lines))

    def write(self, path):
        out = ["// Game: BoomerShooter", "// Format: Valve", "// entity 0", "{", '"mapversion" "220"',
               '"wad" ""', '"classname" "worldspawn"', '"_tb_mod" "trenchbroom"']
        out.extend(self.brushes)
        out.append("}")
        out.extend(self.entities)
        with open(path, "w", newline="\n") as handle:
            handle.write("\n".join(out) + "\n")
