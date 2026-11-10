"""Hand edits made in TrenchBroom to level_01.map, kept as a patch that level_01_act1.py applies after generating.

The generator owns the whole map, so without this a re-run would throw away what was done by hand. The patch is a
semantic diff (generated map -> hand-edited map): brushes and entities that were removed or added. Brushes and entities
are compared by their text, so moving or resizing something shows up as one removal plus one addition.

    python tools/levelgen/active/level_01_hand_edits.py capture   # after editing in TrenchBroom: update the patch
                                                                   # from (generator output, current map)
Normally you do not run this file; level_01_act1.py imports apply_patch() and calls it as its last step.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCH = os.path.join(HERE, "level_01_hand_edits.json")
NL = chr(10)


def parse(path):
    """-> (header lines, worldspawn props dict, worldspawn brushes, entities); a brush is a tuple of plane lines,
    an entity is {"props": [(k, v)...], "brushes": [...]}"""
    text = open(path, newline="").read().replace(chr(13) + NL, NL)
    header = [l for l in text.split(NL) if l.startswith("// ") and not l.startswith("// entity") and not l.startswith("// brush")
              and not l.startswith("// Generator")]
    ents, depth, cur, brush = [], 0, None, None
    for line in text.split(NL):
        if line == "{" and depth == 0:
            cur, depth = {"props": [], "brushes": []}, 1
        elif line == "{" and depth == 1:
            brush, depth = [], 2
        elif line == "}" and depth == 2:
            cur["brushes"].append(tuple(brush))
            depth = 1
        elif line == "}" and depth == 1:
            ents.append(cur)
            depth = 0
        elif depth == 1:
            m = re.match(r'"([^"]*)" "(.*)"$', line)
            if m:
                cur["props"].append((m.group(1), m.group(2)))
        elif depth == 2 and line.startswith("("):
            brush.append(line.strip())
    return header, ents[0], ents[1:]


def ent_key(e):
    return json.dumps([sorted(e["props"]), sorted(e["brushes"])])


def write(path, header, world, ents):
    out = list(header) + ["// entity 0", "{"]
    out += ['"%s" "%s"' % kv for kv in world["props"]]
    for i, br in enumerate(world["brushes"]):
        out += ["// brush %d" % i, "{"] + list(br) + ["}"]
    out.append("}")
    for n, e in enumerate(ents, 1):
        out += ["// entity %d" % n, "{"] + ['"%s" "%s"' % kv for kv in e["props"]]
        for i, br in enumerate(e["brushes"]):
            out += ["// brush %d" % i, "{"] + list(br) + ["}"]
        out.append("}")
    open(path, "w", newline="").write(NL.join(out) + NL)


def capture(generated_path, hand_path):
    _, gw, ge = parse(generated_path)
    _, hw, he = parse(hand_path)
    gb, hb = set(gw["brushes"]), set(hw["brushes"])
    gk, hk = {ent_key(e) for e in ge}, {ent_key(e) for e in he}
    patch = {
        "world_props": hw["props"],
        "world_removed": sorted(gb - hb),
        "world_added": sorted(hb - gb),
        "entities_removed": [e for e in ge if ent_key(e) not in hk],
        "entities_added": [e for e in he if ent_key(e) not in gk],
    }
    json.dump(patch, open(PATCH, "w"), indent=1)
    print("hand edits:", len(patch["world_removed"]), "brushes removed,", len(patch["world_added"]), "added;",
          len(patch["entities_removed"]), "entities removed,", len(patch["entities_added"]), "added")


def apply_patch(map_path):
    """Apply the hand edits to a freshly generated map, in place."""
    if not os.path.exists(PATCH):
        return
    patch = json.load(open(PATCH))
    header, world, ents = parse(map_path)
    removed = set(map(tuple, map(tuple, patch["world_removed"])))
    removed = {tuple(b) for b in patch["world_removed"]}
    before = len(world["brushes"])
    world["brushes"] = [b for b in world["brushes"] if b not in removed]
    missing = len(removed) - (before - len(world["brushes"]))
    world["brushes"] += [tuple(b) for b in patch["world_added"]]
    world["props"] = [tuple(p) for p in patch["world_props"]]
    gone = {ent_key({"props": [tuple(p) for p in e["props"]], "brushes": [tuple(b) for b in e["brushes"]]})
            for e in patch["entities_removed"]}
    kept = [e for e in ents if ent_key(e) not in gone]
    missing += len(gone) - (len(ents) - len(kept))
    for e in patch["entities_added"]:
        kept.append({"props": [tuple(p) for p in e["props"]], "brushes": [tuple(b) for b in e["brushes"]]})
    write(map_path, header, world, kept)
    print("applied hand edits (%d removals did not match the generated map)" % missing)


if __name__ == "__main__":
    if sys.argv[1:] == ["capture"]:
        root = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
        hand = os.path.join(root, "trenchbroom", "maps", "level_01.map")
        gen = hand + ".generated"
        subprocess.check_call([sys.executable, os.path.join(HERE, "level_01_act1.py"), "--no-hand-edits", gen])
        capture(gen, hand)
        os.remove(gen)
    else:
        print(__doc__)
