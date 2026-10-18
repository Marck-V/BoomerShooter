"""Edit an existing TrenchBroom .map as text, without regenerating it, so hand edits made in TrenchBroom survive.

    from editmap import MapFile
    mf = MapFile("trenchbroom/maps/level_02.map")
    mf.remove(lambda e: e.props.get("wave") == "arena")
    mf.add(text_of_new_entity)
    mf.save()
"""
import re

NL = chr(10)


class Entity:
    def __init__(self, text):
        self.text = text
        match = re.search(r'"classname" "([^"]*)"', text)
        self.classname = match.group(1) if match else ""
        self.props = dict(re.findall(r'^"([^"]+)" "([^"]*)"', text, re.M))

    def origin(self):
        """Origin in map units, or None for brush entities."""
        if "origin" not in self.props:
            return None
        return tuple(float(v) for v in self.props["origin"].split())


WORLD_BRUSH = re.compile(r"// brush \d+[^\n]*\n\{\n((?:\(.*\n)+)\}\n?")


def brush_bounds(brush_text):
    """((x0, x1), (y0, y1), (z0, z1)) of a brush, from its plane points."""
    points = [tuple(int(v) for v in p) for p in re.findall(r"\( (-?\d+) (-?\d+) (-?\d+) \)", brush_text)]
    return tuple((min(p[i] for p in points), max(p[i] for p in points)) for i in range(3))


class MapFile:
    def __init__(self, path):
        self.path = path
        raw = open(path, newline="").read()
        self.newline = chr(13) + NL if (chr(13) + NL) in raw else NL
        raw = raw.replace(chr(13) + NL, NL)
        # Everything before the first "// entity 1" is the header plus worldspawn (entity 0)
        parts = re.split(r"\n(?=// entity [1-9]\d*\n)", raw)
        self.head = parts[0]
        self.entities = [Entity(p.rstrip(NL)) for p in parts[1:]]

    def remove(self, predicate):
        """Remove every entity for which predicate(entity) is true. Returns how many were removed."""
        kept = [e for e in self.entities if not predicate(e)]
        removed = len(self.entities) - len(kept)
        self.entities = kept
        return removed

    def world_brushes(self):
        """[(match, bounds)] for every brush of worldspawn."""
        return [(m, brush_bounds(m.group(1))) for m in WORLD_BRUSH.finditer(self.head)]

    def remove_world_brushes(self, predicate):
        """Remove worldspawn brushes whose bounds satisfy predicate(bounds). Returns how many."""
        kept = []
        position = 0
        removed = 0
        for match, bounds in self.world_brushes():
            kept.append(self.head[position:match.start()])
            position = match.end()
            if predicate(bounds):
                removed += 1
            else:
                kept.append(match.group(0))
        kept.append(self.head[position:])
        self.head = "".join(kept)
        return removed

    def add_world_brush(self, text):
        """Add a brush to worldspawn (the head ends with worldspawn's closing brace)."""
        body = self.head.rstrip(NL)
        assert body.endswith("}"), "unexpected map header"
        self.head = body[:-1].rstrip(NL) + NL + text.rstrip(NL) + NL + "}" + NL

    def add(self, text):
        self.entities.append(Entity(text.rstrip(NL)))

    def save(self):
        out = [self.head.rstrip(NL)]
        for number, entity in enumerate(self.entities, start=1):
            body = re.sub(r"^// entity \d+", "// entity %d" % number, entity.text, count=1)
            if not body.startswith("// entity"):
                body = "// entity %d" % number + NL + body
            out.append(body)
        text = NL.join(out) + NL
        with open(self.path, "w", newline="") as handle:
            handle.write(text.replace(NL, self.newline))
