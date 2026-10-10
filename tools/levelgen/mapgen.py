"""Tiny helpers for writing TrenchBroom (Valve 220) .map files from code.

Coordinates are Quake units: X/Y are the floor plane, Z is up, 32 units = 1 meter (same as the
func_godot map settings). Brushes are axis-aligned boxes, plus wedge ramps.
"""

UNITS_PER_METER = 32
NL = chr(10)


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


def _orient(points, inside):
    """Order three points so the plane normal faces away from the interior point (same rule as the box faces)."""
    p1, p2, p3 = points
    a = tuple(p3[i] - p1[i] for i in range(3))
    b = tuple(p2[i] - p1[i] for i in range(3))
    normal = (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
    to_inside = tuple(inside[i] - p1[i] for i in range(3))
    if sum(normal[i] * to_inside[i] for i in range(3)) > 0:
        return (p1, p3, p2)
    return points


class MapBuilder:
    def __init__(self):
        self.brushes = []
        self.entities = []
        self.brush_count = 0

    def _box_text(self, x0, x1, y0, y1, z0, z1, texture, comment=""):
        assert x0 < x1 and y0 < y1 and z0 < z1, (x0, x1, y0, y1, z0, z1)
        lines = ["// brush %d%s" % (self.brush_count, (" - " + comment) if comment else ""), "{"]
        self.brush_count += 1
        for points, u, v in _faces(x0, x1, y0, y1, z0, z1):
            plane = " ".join("( %d %d %d )" % p for p in points)
            lines.append("%s %s [ %d %d %d 0 ] [ %d %d %d 0 ] 90 0.125 0.125" % ((plane, texture) + u + v))
        lines.append("}")
        return NL.join(lines)

    def box(self, x0, x1, y0, y1, z0, z1, texture="world/texture_15", comment=""):
        """Axis-aligned solid box between the given coordinates (map units)."""
        self.brushes.append(self._box_text(x0, x1, y0, y1, z0, z1, texture, comment))

    def brush_entity(self, classname, boxes, **properties):
        """A brush entity (trigger, door...) made of boxes: each is (x0, x1, y0, y1, z0, z1, texture)."""
        lines = ["// entity %d" % (len(self.entities) + 1), "{", '"classname" "%s"' % classname]
        for key, value in properties.items():
            lines.append('"%s" "%s"' % (key, value))
        for box in boxes:
            lines.append(self._box_text(*box, comment=classname))
        lines.append("}")
        self.entities.append(NL.join(lines))

    def convex(self, faces, texture, comment=""):
        """Brush from faces, each a list of 3+ vertices (x, y, z) of that face. The solid must be convex."""
        verts = [v for face in faces for v in face]
        inside = tuple(sum(v[i] for v in verts) / len(verts) for i in range(3))
        lines = ["// brush %d%s" % (self.brush_count, (" - " + comment) if comment else ""), "{"]
        self.brush_count += 1
        for face in faces:
            p1, p2, p3 = _orient(tuple(face[:3]), inside)
            plane = " ".join("( %d %d %d )" % p for p in (p1, p2, p3))
            lines.append("%s %s [ 1 0 0 0 ] [ 0 -1 0 0 ] 90 0.125 0.125" % (plane, texture))
        lines.append("}")
        self.brushes.append(NL.join(lines))

    def ramp(self, x0, x1, y0, y1, z_base, z_top, rises_toward="+y", texture="world/texture_15", comment=""):
        """Wedge: a flat bottom at z_base, rising from zero thickness to z_top over the run."""
        if rises_toward == "+y":
            a, b, c, d = (x0, y0, z_base), (x1, y0, z_base), (x1, y1, z_base), (x0, y1, z_base)
            e, f = (x0, y1, z_top), (x1, y1, z_top)
        elif rises_toward == "-y":
            a, b, c, d = (x0, y1, z_base), (x1, y1, z_base), (x1, y0, z_base), (x0, y0, z_base)
            e, f = (x0, y0, z_top), (x1, y0, z_top)
        else:
            raise ValueError(rises_toward)
        self.convex([[a, b, c, d], [d, c, f, e], [a, d, e], [b, c, f], [a, b, f, e]], texture, comment or "ramp")

    def entity(self, classname, x, y, z, **properties):
        lines = ["// entity %d" % (len(self.entities) + 1), "{", '"classname" "%s"' % classname,
                 '"origin" "%d %d %d"' % (x, y, z)]
        for key, value in properties.items():
            lines.append('"%s" "%s"' % (key, value))
        lines.append("}")
        self.entities.append(NL.join(lines))

    def write(self, path):
        out = ["// Game: BoomerShooter", "// Format: Valve", "// entity 0", "{", '"mapversion" "220"',
               '"wad" ""', '"classname" "worldspawn"', '"_tb_mod" "trenchbroom"']
        out.extend(self.brushes)
        out.append("}")
        out.extend(self.entities)
        with open(path, "w", newline=NL) as handle:
            handle.write(NL.join(out) + NL)


class TileGrid:
    """Rooms and corridors on a grid of square cells (4 m by default).

    Each walkable cell has a floor height and an optional ceiling height (meters). Floors and ceilings are
    merged along rows, and a wall is generated on every edge between a walkable and a non-walkable cell, so
    doorways are just two touching rooms. Where two touching rooms have different heights, a lintel closes
    the gap above the lower one.
    """

    def __init__(self, builder, cell=4.0, wall_thickness=0.5):
        self.b = builder
        self.cell = cell
        self.t = wall_thickness
        self.cells = {}

    def add(self, x0, y0, x1, y1, floor=0.0, ceiling=None, wall_height=None, floor_tex="world/texture_15",
            wall_tex="world/texture_14", ceiling_tex="world/texture_01"):
        """Mark the cells x0..x1, y0..y1 (inclusive, in cell units) as walkable."""
        for cx in range(x0, x1 + 1):
            for cy in range(y0, y1 + 1):
                self.cells[(cx, cy)] = dict(floor=floor, ceiling=ceiling, wall_height=wall_height,
                                            floor_tex=floor_tex, wall_tex=wall_tex, ceiling_tex=ceiling_tex)

    def path(self, points, **kwargs):
        """Walkable cells along a polyline of cell coordinates (axis-aligned segments)."""
        for (ax, ay), (bx, by) in zip(points, points[1:]):
            self.add(min(ax, bx), min(ay, by), max(ax, bx), max(ay, by), **kwargs)

    def center(self, cx, cy):
        return (cx + 0.5) * self.cell, (cy + 0.5) * self.cell

    def build(self):
        c = self.cell
        # Floors: solid from the lowest point up to the floor height, merged along x
        for cy in sorted({k[1] for k in self.cells}):
            self._runs(cy, lambda cell: (cell["floor"], cell["floor_tex"]),
                       lambda x0, x1, key, cy=cy: self.b.box(m(x0 * c), m(x1 * c), m(cy * c), m((cy + 1) * c),
                                                             m(min(key[0], 0.0) - 0.5), m(key[0]), key[1], "floor"))
        # Ceilings
        for cy in sorted({k[1] for k in self.cells}):
            self._runs(cy, lambda cell: (cell["ceiling"], cell["ceiling_tex"]) if cell["ceiling"] is not None else None,
                       lambda x0, x1, key, cy=cy: self.b.box(m(x0 * c), m(x1 * c), m(cy * c), m((cy + 1) * c),
                                                             m(key[0]), m(key[0] + 0.5), key[1], "ceiling"))
        # Walls on every walkable/non-walkable edge, merged along the edge
        for horizontal in (True, False):
            self._walls(horizontal)
        self._lintels()

    def _runs(self, cy, key_of, emit):
        xs = sorted(k[0] for k in self.cells if k[1] == cy)
        start = None
        prev = None
        prev_key = None
        for cx in xs + [None]:
            key = key_of(self.cells[(cx, cy)]) if cx is not None else None
            contiguous = cx is not None and prev is not None and cx == prev + 1 and key == prev_key
            if not contiguous:
                if start is not None and prev_key is not None:
                    emit(start, prev + 1, prev_key)
                start = cx
            prev, prev_key = cx, key

    def _wall_params(self, cell):
        top = cell["wall_height"] if cell["wall_height"] is not None else (
            cell["ceiling"] + 0.5 if cell["ceiling"] is not None else cell["floor"] + 6.0)
        return (cell["floor"], top, cell["wall_tex"])

    def _walls(self, horizontal):
        """horizontal=True: walls running along x at the north/south edges of cells; False: along y (east/west)."""
        edges = {}
        for (cx, cy), cell in self.cells.items():
            for side in (-1, 1):
                neighbor = (cx, cy + side) if horizontal else (cx + side, cy)
                if neighbor in self.cells:
                    continue
                line = cy + (1 if side > 0 else 0) if horizontal else cx + (1 if side > 0 else 0)
                pos = cx if horizontal else cy
                edges.setdefault((line, side, self._wall_params(cell)), []).append(pos)
        for (line, side, params), positions in edges.items():
            positions.sort()
            run_start = prev = positions[0]
            for pos in positions[1:] + [None]:
                if pos is not None and pos == prev + 1:
                    prev = pos
                    continue
                self._emit_wall(horizontal, line, side, run_start, prev + 1, params)
                if pos is not None:
                    run_start = prev = pos

    def _emit_wall(self, horizontal, line, side, a, b, params):
        c, t = self.cell, self.t
        floor, top, tex = params
        a0, a1 = m(a * c) - m(t), m(b * c) + m(t)            # extend along the wall to cover corners
        edge = m(line * c)
        out0, out1 = (edge, edge + m(t)) if side > 0 else (edge - m(t), edge)
        z0, z1 = m(min(floor, 0.0) - 0.5), m(top)
        if horizontal:
            self.b.box(a0, a1, out0, out1, z0, z1, tex, "wall")
        else:
            self.b.box(out0, out1, a0, a1, z0, z1, tex, "wall")

    def _top(self, cell):
        return self._wall_params(cell)[1]

    def _lintels(self):
        c, t = self.cell, self.t
        for (cx, cy), cell in self.cells.items():
            for dx, dy in ((1, 0), (0, 1)):
                other = self.cells.get((cx + dx, cy + dy))
                if other is None:
                    continue
                top_a, top_b = self._top(cell), self._top(other)
                if abs(top_a - top_b) < 0.01:
                    continue
                low_is_a = top_a < top_b
                low, high = (top_a, top_b) if low_is_a else (top_b, top_a)
                tex = cell["wall_tex"] if not low_is_a else other["wall_tex"]
                if dx:
                    edge = m((cx + 1) * c)
                    x0, x1 = (edge - m(t), edge) if low_is_a else (edge, edge + m(t))
                    self.b.box(x0, x1, m(cy * c), m((cy + 1) * c), m(low), m(high), tex, "lintel")
                else:
                    edge = m((cy + 1) * c)
                    y0, y1 = (edge - m(t), edge) if low_is_a else (edge, edge + m(t))
                    self.b.box(m(cx * c), m((cx + 1) * c), y0, y1, m(low), m(high), tex, "lintel")
