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
