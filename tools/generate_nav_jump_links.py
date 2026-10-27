"""Finds the small gaps between the walkable islands of a baked NavigationMesh and prints (or writes) the
NavigationLink3D nodes that bridge them, so ground enemies can jump across.

Usage:
    python tools/generate_nav_jump_links.py scenes/test_scenes/enemy_room.tscn            # just list them
    python tools/generate_nav_jump_links.py scenes/test_scenes/enemy_room.tscn --write    # add them to the scene

The links are ordinary NavigationLink3D nodes named JumpLink_*; re-running with --write replaces the old
JumpLink_* nodes, so a re-bake of the navigation mesh can be followed by a regeneration. Nodes can also be
moved, deleted or added by hand in the editor.
"""
import collections
import itertools
import math
import re
import sys

MAX_GAP = 3.6          # horizontal distance between two islands' edges (the mesh is already shrunk by the agent radius)
MAX_JUMP_UP = 2.0      # highest step up a jump can make
MAX_DROP = 2.0         # furthest it will jump down
MIN_AREA = 3.0         # ignore specks smaller than this
LINKS_PER_PAIR = 2     # a wide gap gets a couple of links, so enemies don't have to walk far to one
LINK_SPACING = 4.0
TRAVEL_COST = 1.5      # slightly dearer than walking, so a walkable route is still preferred


def parse_navmesh(text):
    start = text.index('[sub_resource type="NavigationMesh"')
    block = text[start:start + 3_000_000]
    flat = [float(x) for x in re.search(r'vertices = PackedVector3Array\(([^)]*)\)', block).group(1).split(',')]
    verts = [tuple(flat[i:i + 3]) for i in range(0, len(flat), 3)]
    polygon_text = re.search(r'polygons = \[(.*?)\]\n', block, re.S).group(1)
    polys = [[int(x) for x in re.findall(r'-?\d+', p)] for p in re.findall(r'PackedInt32Array\(([^)]*)\)', polygon_text)]
    return verts, polys


def islands(verts, polys):
    edge_polys = collections.defaultdict(list)
    for index, poly in enumerate(polys):
        for a, b in zip(poly, poly[1:] + poly[:1]):
            edge_polys[tuple(sorted((a, b)))].append(index)
    parent = list(range(len(polys)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for polys_on_edge in edge_polys.values():
        for other in polys_on_edge[1:]:
            ra, rb = find(polys_on_edge[0]), find(other)
            if ra != rb:
                parent[ra] = rb
    roots = sorted({find(i) for i in range(len(polys))})
    ids = {root: n for n, root in enumerate(roots)}
    boundary = collections.defaultdict(list)
    for edge, polys_on_edge in edge_polys.items():
        if len(polys_on_edge) == 1:
            boundary[ids[find(polys_on_edge[0])]].append(edge)
    area = collections.defaultdict(float)
    for index, poly in enumerate(polys):
        for k in range(1, len(poly) - 1):
            a, b, c = verts[poly[0]], verts[poly[k]], verts[poly[k + 1]]
            area[ids[find(index)]] += abs((b[0] - a[0]) * (c[2] - a[2]) - (c[0] - a[0]) * (b[2] - a[2])) / 2
    return boundary, area


def edge_samples(verts, edge, step=0.5):
    a, b = verts[edge[0]], verts[edge[1]]
    length = math.dist((a[0], a[2]), (b[0], b[2]))
    n = max(1, int(length / step))
    return [tuple(a[k] + (b[k] - a[k]) * t / n for k in range(3)) for t in range(n + 1)]


def find_links(text):
    verts, polys = parse_navmesh(text)
    boundary, area = islands(verts, polys)
    samples = {c: [p for e in edges for p in edge_samples(verts, e)] for c, edges in boundary.items()}
    links = []
    for a, b in itertools.combinations(sorted(samples), 2):
        if area[a] < MIN_AREA or area[b] < MIN_AREA:
            continue
        candidates = []
        for p in samples[a]:
            for q in samples[b]:
                dy = q[1] - p[1]
                if dy > MAX_JUMP_UP or dy < -MAX_DROP:
                    continue
                d = math.dist((p[0], p[2]), (q[0], q[2]))
                if 0.5 < d <= MAX_GAP:
                    candidates.append((d, p, q))
        if not candidates:
            continue
        candidates.sort(key=lambda c: c[0])
        shortest = candidates[0][0]
        chosen = []
        for d, p, q in candidates:
            if d > shortest + 0.8:
                break
            if all(math.dist((p[0], p[2]), (c[1][0], c[1][2])) >= LINK_SPACING for c in chosen):
                chosen.append((d, p, q))
            if len(chosen) >= LINKS_PER_PAIR:
                break
        for n, (d, p, q) in enumerate(chosen):
            links.append((a, b, n, d, p, q))
    return links, area


def node_text(a, b, n, p, q):
    return (f'[node name="JumpLink_{a}_{b}_{n}" type="NavigationLink3D" parent="."]\n'
            f'travel_cost = {TRAVEL_COST}\n'
            f'start_position = Vector3({p[0]:.2f}, {p[1]:.2f}, {p[2]:.2f})\n'
            f'end_position = Vector3({q[0]:.2f}, {q[1]:.2f}, {q[2]:.2f})\n')


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    path = sys.argv[1]
    raw = open(path, newline='').read()
    crlf = '\r\n' in raw
    text = raw.replace('\r\n', '\n')
    links, area = find_links(text)
    for a, b, n, d, p, q in links:
        print(f"island {a} (area {area[a]:.0f}) <-> {b} (area {area[b]:.0f})  gap {d:.2f}  dy {q[1] - p[1]:+.2f}  "
              f"({p[0]:.1f}, {p[1]:.1f}, {p[2]:.1f}) -> ({q[0]:.1f}, {q[1]:.1f}, {q[2]:.1f})")
    print(f"{len(links)} links")
    if '--write' not in sys.argv:
        return
    # drop the links from an earlier run, then add the new ones right after the NavigationRegion3D node
    text = re.sub(r'\[node name="JumpLink_[^\n]*\n(?:(?!\[)[^\n]*\n)*', '', text)
    marker = re.search(r'\[node name="NavigationRegion3D"[^\n]*\n(?:(?!\[)[^\n]*\n)*', text)
    insert_at = marker.end()
    text = text[:insert_at] + ''.join(node_text(a, b, n, p, q) + '\n' for a, b, n, d, p, q in links) + text[insert_at:]
    if crlf:
        text = text.replace('\n', '\r\n')
    open(path, 'w', newline='').write(text)
    print('written to', path)


main()
