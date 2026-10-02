"""Generate the low-poly game assets and export them as .glb for Godot.

Run headless:
    blender -b -P tools/blender/generate_assets.py

Conventions
    * Blender is Z-up and the glTF exporter converts to Y-up, so Blender +Y
      ("forward" while modelling) becomes Godot -Z, which is Godot's forward.
    * Every prop is a single mesh with several material slots, so Godot sees
      one MeshInstance per prop (cheap to instance / MultiMesh / collide).
    * The character is split into pivoted limbs so the game can animate them.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models")

_materials = {}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()


def material(name, color, rough=0.85, emit=None, emit_strength=1.5):
    if name in _materials:
        return _materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if emit:
        socket = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
        bsdf.inputs[socket].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    _materials[name] = mat
    return mat


class Part:
    """Accumulates primitives into one mesh, with a material slot per colour."""

    def __init__(self, name, origin=(0.0, 0.0, 0.0)):
        self.name = name
        self.origin = Vector(origin)
        self.bm = bmesh.new()
        self.mats = []

    def _tag(self, verts, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        idx = self.mats.index(mat)
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index = idx

    def box(self, center, size, mat, rot_z=0.0, rot=(0.0, 0.0, 0.0)):
        verts = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        m = (
            Matrix.Translation(Vector(center) - self.origin)
            @ Matrix.Rotation(rot_z, 4, "Z")
            @ Matrix.Rotation(rot[2], 4, "Z")
            @ Matrix.Rotation(rot[1], 4, "Y")
            @ Matrix.Rotation(rot[0], 4, "X")
            @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        )
        bmesh.ops.transform(self.bm, matrix=m, verts=verts)
        self._tag(verts, mat)

    def box_span(self, x0, x1, y0, y1, z0, z1, mat):
        """Axis-aligned box from min/max coordinates (skips empty spans)."""
        if x1 - x0 < 1e-4 or y1 - y0 < 1e-4 or z1 - z0 < 1e-4:
            return
        self.box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), mat)

    def cone(self, center, r_bottom, r_top, depth, mat, segments=8, scale_xy=(1.0, 1.0), rot_z=0.0, axis="Z"):
        kwargs = dict(cap_ends=True, cap_tris=False, segments=segments, depth=depth)
        try:
            ret = bmesh.ops.create_cone(self.bm, radius1=r_bottom, radius2=r_top, **kwargs)
        except TypeError:  # older API names
            ret = bmesh.ops.create_cone(self.bm, diameter1=r_bottom, diameter2=r_top, **kwargs)
        verts = ret["verts"]
        m = (
            Matrix.Translation(Vector(center) - self.origin)
            @ (Matrix.Rotation(-math.pi / 2, 4, "X") if axis == "Y" else Matrix.Identity(4))
            @ Matrix.Diagonal((scale_xy[0], scale_xy[1], 1.0, 1.0))
            @ Matrix.Rotation(rot_z, 4, "Z")
        )
        bmesh.ops.transform(self.bm, matrix=m, verts=verts)
        self._tag(verts, mat)

    def blob(self, center, radius, mat, squash=0.6, jitter=0.25, seed=0):
        rng = random.Random(seed)
        verts = bmesh.ops.create_icosphere(self.bm, subdivisions=1, radius=radius)["verts"]
        for v in verts:
            v.co *= 1.0 + rng.uniform(-jitter, jitter)
            v.co.z *= squash
            v.co += Vector(center) - self.origin
        self._tag(verts, mat)

    def build(self, location=None):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.mats:
            mesh.materials.append(m)
        for poly in mesh.polygons:
            poly.use_smooth = False
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.location = location if location is not None else self.origin
        return obj


def empty(name, location):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    return obj


def export(name, objects):
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )
    print("exported", path)


# --------------------------------------------------------------------------- assets




def make_tree():
    bark = material("bark", (0.33, 0.20, 0.10))
    leaf_a = material("leaf_a", (0.10, 0.45, 0.16))
    leaf_b = material("leaf_b", (0.14, 0.55, 0.20))
    tree = Part("Tree")
    tree.cone((0, 0, 1.0), 0.28, 0.20, 2.0, bark, segments=6)
    tree.cone((0, 0, 2.6), 1.9, 0.15, 2.4, leaf_a, segments=8)
    tree.cone((0, 0, 4.0), 1.5, 0.12, 2.2, leaf_b, segments=8)
    tree.cone((0, 0, 5.3), 1.0, 0.05, 2.0, leaf_a, segments=8)
    export("tree", [tree.build()])


def make_rock():
    rock_a = material("rock_a", (0.48, 0.47, 0.45), rough=1.0)
    rock = Part("Rock")
    rock.blob((0, 0, 0.1), 1.0, rock_a, squash=0.7, jitter=0.3, seed=7)
    export("rock", [rock.build()])


def make_crate():
    wood = material("crate_wood", (0.52, 0.32, 0.14))
    gold = material("crate_gold", (0.95, 0.72, 0.15), rough=0.3, emit=(1.0, 0.65, 0.1))
    crate = Part("Crate")
    crate.box((0, 0, 0.35), (0.80, 0.80, 0.70), wood)
    crate.box((0, 0, 0.35), (0.84, 0.18, 0.74), gold)
    crate.box((0, 0, 0.35), (0.18, 0.84, 0.74), gold)
    crate.box((0, 0, 0.76), (0.40, 0.40, 0.08), gold)
    export("crate", [crate.build()])


def walls(part, mat, hw, hd, height, thick, door_x, windows, door_w=1.3, door_h=2.25, win_z=(1.0, 2.2), win_w=1.4):
    """Four walls of a rectangular building; door on the -Y (front) wall."""
    holes_front = [(door_x - door_w / 2, door_x + door_w / 2, 0.0, door_h)]
    holes_back = [(wx - win_w / 2, wx + win_w / 2, win_z[0], win_z[1]) for wx in windows]
    holes_side = [(-win_w / 2, win_w / 2, win_z[0], win_z[1])] if windows else []

    def wall_x(y, holes):
        cuts = sorted(holes)
        cursor = -hw
        for x0, x1, z0, z1 in cuts:
            part.box_span(cursor, x0, y - thick / 2, y + thick / 2, 0, height, mat)
            part.box_span(x0, x1, y - thick / 2, y + thick / 2, 0, z0, mat)
            part.box_span(x0, x1, y - thick / 2, y + thick / 2, z1, height, mat)
            cursor = x1
        part.box_span(cursor, hw, y - thick / 2, y + thick / 2, 0, height, mat)

    def wall_y(x, holes):
        cuts = sorted(holes)
        cursor = -hd
        for y0, y1, z0, z1 in cuts:
            part.box_span(x - thick / 2, x + thick / 2, cursor, y0, 0, height, mat)
            part.box_span(x - thick / 2, x + thick / 2, y0, y1, 0, z0, mat)
            part.box_span(x - thick / 2, x + thick / 2, y0, y1, z1, height, mat)
            cursor = y1
        part.box_span(x - thick / 2, x + thick / 2, cursor, hd, 0, height, mat)

    wall_x(-hd, holes_front)
    wall_x(hd, holes_back)
    wall_y(-hw, holes_side)
    wall_y(hw, holes_side)


def make_house(name, width, depth, height, wall_color, roof_color, trim_color, roof_h, windows, door_w=1.3, door_h=2.25, extra=None, win_z=(1.0, 2.2), win_w=1.4, roof_overhang=0.7):
    wall = material(name + "_wall", wall_color)
    roof = material(name + "_roof", roof_color, rough=0.7)
    trim = material(name + "_trim", trim_color)
    floor = material(name + "_floor", (0.45, 0.33, 0.22))
    hw, hd = width / 2, depth / 2
    house = Part(name)
    house.box((0, 0, 0.06), (width + 0.3, depth + 0.3, 0.12), trim)  # plinth / porch
    house.box((0, 0, 0.13), (width - 0.4, depth - 0.4, 0.04), floor)
    walls(house, wall, hw, hd, height, 0.25, 0.0, windows, door_w, door_h, win_z, win_w)
    # corner posts
    for sx in (-1, 1):
        for sy in (-1, 1):
            house.box((sx * hw, sy * hd, height / 2), (0.32, 0.32, height), trim)
    # ceiling slab under the roof so the interior is enclosed
    house.box((0, 0, height + 0.05), (width, depth, 0.12), trim)
    # hipped roof: a 4-sided cone rotated onto the wall axes, stretched to the footprint
    ov = roof_overhang
    house.cone(
        (0, 0, height + roof_h / 2),
        math.sqrt(2),
        0.05,
        roof_h,
        roof,
        segments=4,
        scale_xy=(hw + ov, hd + ov),
        rot_z=math.pi / 4,
    )
    if extra:
        extra(house)
    export(name, [house.build()])


def make_tower():
    steel = material("tower_steel", (0.55, 0.58, 0.62), rough=0.5)
    tank = material("tower_tank", (0.20, 0.55, 0.68), rough=0.6)
    stripe = material("tower_stripe", (0.95, 0.95, 0.95))
    roof = material("tower_roof", (0.75, 0.22, 0.18))
    tower = Part("Tower")
    for sx in (-1, 1):
        for sy in (-1, 1):
            tower.box((sx * 1.6, sy * 1.6, 4.5), (0.35, 0.35, 9.0), steel)
    for z in (2.5, 5.5, 8.2):  # cross braces
        tower.box((0, -1.6, z), (3.5, 0.18, 0.18), steel)
        tower.box((0, 1.6, z), (3.5, 0.18, 0.18), steel)
        tower.box((-1.6, 0, z), (0.18, 3.5, 0.18), steel)
        tower.box((1.6, 0, z), (0.18, 3.5, 0.18), steel)
    tower.box((0, 0, 9.05), (4.0, 4.0, 0.2), steel)
    tower.cone((0, 0, 11.0), 2.5, 2.5, 3.7, tank, segments=12)
    tower.cone((0, 0, 11.0), 2.56, 2.56, 0.7, stripe, segments=12)
    tower.cone((0, 0, 13.7), 2.7, 0.2, 1.6, roof, segments=12)
    export("tower", [tower.build()])


# ------------------------------------------------------------- character rig
# A real joint hierarchy (empties) with meshes parented to the joints, so the game can bend
# knees/elbows, swing arms and parent the weapon to the right hand.

JW = {}  # joint name -> world position at rest


def joint(name, world, parent=None):
    j = empty(name, (0, 0, 0))
    JW[name] = Vector(world)
    j.location = Vector(world) - (JW[parent.name] if parent else Vector((0, 0, 0)))
    if parent:
        j.parent = parent
    return j


def part_on(j, name, fn):
    p = Part(name, origin=JW[j.name])
    fn(p)
    ob = p.build(location=(0.0, 0.0, 0.0))
    ob.parent = j
    return ob


def make_player():
    skin = material("skin", (0.80, 0.52, 0.36))
    vest = material("vest", (0.30, 0.42, 0.22))
    pants = material("pants", (0.32, 0.22, 0.14))
    boots = material("boots", (0.10, 0.09, 0.08))
    hair = material("hair", (0.07, 0.05, 0.04))
    glove = material("glove", (0.14, 0.14, 0.16))
    pack = material("pack", (0.27, 0.23, 0.17))
    eyes = material("eyes", (0.05, 0.05, 0.08))
    objs = []

    hips = joint("Hips", (0, 0, 0.93))
    objs.append(hips)
    objs.append(part_on(hips, "PelvisMesh", lambda p: p.box((0, 0, 0.93), (0.40, 0.24, 0.20), pants)))

    spine = joint("Spine", (0, 0, 1.03), hips)
    objs.append(spine)

    def torso(p):
        p.box((0, 0, 1.27), (0.50, 0.28, 0.50), vest)
        p.box((0, 0, 1.06), (0.46, 0.26, 0.08), pack)              # belt
        p.box((0, -0.19, 1.28), (0.36, 0.10, 0.36), pack)          # backpack (rear is -Y)
        p.box((0, 0.15, 1.20), (0.34, 0.05, 0.20), pack)           # chest pouches
    objs.append(part_on(spine, "TorsoMesh", torso))

    head = joint("Head", (0, 0, 1.53), spine)
    objs.append(head)

    def head_mesh(p):
        p.box((0, 0, 1.67), (0.26, 0.26, 0.28), skin)
        p.box((0, -0.01, 1.83), (0.28, 0.28, 0.09), hair)
        p.box((0, 0.15, 1.80), (0.29, 0.10, 0.04), hair)           # cap brim, faces forward (+Y)
        p.box((-0.06, 0.131, 1.69), (0.04, 0.012, 0.04), eyes)
        p.box((0.06, 0.131, 1.69), (0.04, 0.012, 0.04), eyes)
    objs.append(part_on(head, "HeadMesh", head_mesh))

    for side, sx in (("L", -1), ("R", 1)):
        sh = joint("Shoulder" + side, (sx * 0.34, 0, 1.47), spine)
        objs.append(sh)
        objs.append(part_on(sh, "UpperArm" + side, lambda p, sx=sx: p.box((sx * 0.34, 0, 1.31), (0.15, 0.16, 0.32), vest)))
        el = joint("Elbow" + side, (sx * 0.34, 0, 1.15), sh)
        objs.append(el)

        def fore(p, sx=sx):
            p.box((sx * 0.34, 0, 0.99), (0.13, 0.14, 0.30), skin)
            p.box((sx * 0.34, 0, 0.82), (0.13, 0.13, 0.10), glove)
        objs.append(part_on(el, "Forearm" + side, fore))
        objs.append(joint("Hand" + side, (sx * 0.34, 0, 0.84), el))

        hp = joint("Hip" + side, (sx * 0.13, 0, 0.88), hips)
        objs.append(hp)
        objs.append(part_on(hp, "Thigh" + side, lambda p, sx=sx: p.box((sx * 0.13, 0, 0.67), (0.20, 0.22, 0.44), pants)))
        kn = joint("Knee" + side, (sx * 0.13, 0, 0.45), hp)
        objs.append(kn)

        def shin(p, sx=sx):
            p.box((sx * 0.13, 0, 0.25), (0.18, 0.20, 0.40), pants)
            p.box((sx * 0.13, 0.03, 0.06), (0.20, 0.30, 0.12), boots)
        objs.append(part_on(kn, "Shin" + side, shin))
    export("player", objs)


# ------------------------------------------------------------- weapons (detailed)
# Origin = the grip (where the right hand holds it), barrel points +Y (Godot -Z).
# Surfaces using the "accent" material get tinted with the item's rarity colour in game.


def _gun_mats():
    return dict(
        dark=material("gun_dark", (0.10, 0.10, 0.12), rough=0.45),
        steel=material("gun_steel", (0.34, 0.35, 0.38), rough=0.30),
        wood=material("gun_wood", (0.36, 0.20, 0.09)),
        poly=material("gun_poly", (0.20, 0.21, 0.23), rough=0.6),
        accent=material("accent", (0.60, 0.60, 0.65), rough=0.35),
        glass=material("scope_glass", (0.25, 0.55, 0.95), rough=0.1, emit=(0.1, 0.3, 0.8), emit_strength=0.6),
        brass=material("gun_brass", (0.85, 0.65, 0.2), rough=0.3),
    )


def _trigger_guard(g, m, y=0.04, z=-0.075):
    g.box((0, y, z), (0.02, 0.10, 0.012), m["steel"])
    g.box((0, y - 0.045, z + 0.025), (0.02, 0.012, 0.06), m["steel"])
    g.box((0, y + 0.03, z + 0.03), (0.012, 0.014, 0.05), m["dark"])    # trigger


def make_assault():
    m = _gun_mats()
    g = Part("Rifle")
    g.box((0, 0.17, 0.03), (0.075, 0.44, 0.105), m["dark"])                      # receiver
    g.box((0, 0.17, 0.095), (0.04, 0.40, 0.016), m["steel"])                     # top rail
    g.box((0.039, 0.18, 0.035), (0.006, 0.22, 0.03), m["accent"])                # rarity strip
    g.box((-0.039, 0.18, 0.035), (0.006, 0.22, 0.03), m["accent"])
    g.box((0, 0.56, 0.02), (0.082, 0.30, 0.09), m["poly"])                       # handguard
    g.box((0, 0.56, 0.075), (0.036, 0.28, 0.012), m["steel"])                    # handguard rail
    g.cone((0, 0.86, 0.025), 0.016, 0.016, 0.34, m["steel"], segments=8, axis="Y")  # barrel
    g.cone((0, 1.05, 0.025), 0.024, 0.024, 0.07, m["dark"], segments=8, axis="Y")   # muzzle brake
    g.box((0, 0.97, 0.062), (0.012, 0.012, 0.035), m["steel"])                   # front sight post
    g.cone((0, 0.58, 0.075), 0.011, 0.011, 0.26, m["steel"], segments=6, axis="Y")  # gas tube
    g.box((0, 0.12, 0.125), (0.055, 0.09, 0.05), m["dark"])                      # red-dot housing
    g.box((0, 0.165, 0.125), (0.04, 0.008, 0.04), m["glass"])
    g.box((0, -0.19, 0.01), (0.06, 0.34, 0.10), m["wood"])                       # stock
    g.box((0, -0.36, -0.005), (0.065, 0.03, 0.13), m["dark"])                    # butt plate
    g.box((0, -0.06, -0.085), (0.05, 0.07, 0.16), m["poly"], rot=(0.25, 0, 0))   # pistol grip
    g.box((0, 0.20, -0.125), (0.052, 0.085, 0.17), m["dark"], rot=(-0.12, 0, 0))     # magazine (curved: 2 pieces)
    g.box((0, 0.225, -0.255), (0.052, 0.085, 0.10), m["dark"], rot=(-0.32, 0, 0))
    g.box((0.045, 0.14, 0.055), (0.012, 0.05, 0.02), m["steel"])                 # charging handle
    _trigger_guard(g, m)
    export("rifle", [g.build(), empty("Muzzle", (0, 1.10, 0.025))])


def make_smg():
    m = _gun_mats()
    g = Part("Smg")
    g.box((0, 0.14, 0.03), (0.07, 0.34, 0.10), m["dark"])                        # body
    g.box((0, 0.14, 0.088), (0.04, 0.30, 0.014), m["steel"])                     # rail
    g.box((0.036, 0.15, 0.035), (0.006, 0.18, 0.03), m["accent"])
    g.box((-0.036, 0.15, 0.035), (0.006, 0.18, 0.03), m["accent"])
    g.box((0, 0.40, 0.03), (0.06, 0.20, 0.07), m["poly"])                        # shroud
    g.cone((0, 0.62, 0.03), 0.026, 0.026, 0.22, m["dark"], segments=8, axis="Y")     # suppressor
    g.box((0, 0.08, 0.115), (0.04, 0.07, 0.04), m["dark"])                       # red dot
    g.box((0, 0.112, 0.115), (0.03, 0.008, 0.03), m["glass"])
    g.box((0, -0.10, 0.04), (0.012, 0.22, 0.012), m["steel"])                    # folded stock wire
    g.box((0, -0.21, 0.04), (0.05, 0.02, 0.07), m["dark"])
    g.box((0, -0.05, -0.085), (0.05, 0.065, 0.15), m["poly"], rot=(0.3, 0, 0))   # grip
    g.box((0, 0.20, -0.17), (0.045, 0.07, 0.29), m["dark"])                      # long straight mag
    g.box((0, 0.20, -0.32), (0.05, 0.075, 0.025), m["steel"])
    g.box((0, 0.42, -0.045), (0.035, 0.05, 0.08), m["poly"])                     # foregrip
    _trigger_guard(g, m)
    export("smg", [g.build(), empty("Muzzle", (0, 0.74, 0.03))])


def make_shotgun():
    m = _gun_mats()
    g = Part("Shotgun")
    g.box((0, 0.14, 0.03), (0.075, 0.36, 0.10), m["dark"])                       # receiver
    g.box((0.039, 0.14, 0.035), (0.006, 0.18, 0.03), m["accent"])
    g.box((-0.039, 0.14, 0.035), (0.006, 0.18, 0.03), m["accent"])
    g.cone((0, 0.66, 0.045), 0.02, 0.02, 0.70, m["steel"], segments=8, axis="Y")     # barrel
    g.cone((0, 0.62, -0.005), 0.025, 0.025, 0.58, m["dark"], segments=8, axis="Y")  # magazine tube
    g.box((0, 0.58, -0.005), (0.07, 0.24, 0.07), m["wood"])                      # pump
    g.box((0, 1.02, 0.07), (0.012, 0.012, 0.025), m["brass"])                    # bead sight
    g.box((0, 0.10, 0.092), (0.03, 0.10, 0.012), m["steel"])
    g.box((0, -0.18, 0.0), (0.062, 0.34, 0.12), m["wood"], rot=(-0.06, 0, 0))    # stock
    g.box((0, -0.36, -0.01), (0.07, 0.03, 0.15), m["dark"])
    g.box((0, -0.04, -0.075), (0.045, 0.06, 0.12), m["wood"], rot=(0.25, 0, 0))
    _trigger_guard(g, m, y=0.03)
    export("shotgun", [g.build(), empty("Muzzle", (0, 1.02, 0.045))])


def make_sniper():
    m = _gun_mats()
    g = Part("Sniper")
    g.box((0, 0.20, 0.03), (0.07, 0.48, 0.10), m["dark"])                        # receiver
    g.box((0.037, 0.2, 0.035), (0.006, 0.26, 0.03), m["accent"])
    g.box((-0.037, 0.2, 0.035), (0.006, 0.26, 0.03), m["accent"])
    g.cone((0, 0.88, 0.035), 0.017, 0.017, 0.80, m["steel"], segments=8, axis="Y")   # long barrel
    g.cone((0, 1.30, 0.035), 0.028, 0.028, 0.10, m["dark"], segments=8, axis="Y")    # muzzle brake
    g.box((0, 0.58, -0.005), (0.07, 0.30, 0.07), m["poly"])                      # forend
    g.box((0.055, 0.12, 0.05), (0.012, 0.09, 0.012), m["steel"])                 # bolt handle
    g.box((0.07, 0.12, 0.05), (0.03, 0.02, 0.03), m["dark"])                     # bolt knob
    # scope
    g.cone((0, 0.26, 0.135), 0.032, 0.032, 0.34, m["dark"], segments=10, axis="Y")
    g.cone((0, 0.12, 0.135), 0.042, 0.042, 0.08, m["dark"], segments=10, axis="Y")
    g.cone((0, 0.43, 0.135), 0.048, 0.048, 0.10, m["dark"], segments=10, axis="Y")
    g.box((0, 0.435, 0.135), (0.07, 0.005, 0.07), m["glass"])
    g.box((0, 0.20, 0.09), (0.02, 0.03, 0.05), m["steel"])
    g.box((0, 0.33, 0.09), (0.02, 0.03, 0.05), m["steel"])
    g.box((0, -0.22, 0.015), (0.065, 0.40, 0.11), m["wood"], rot=(-0.04, 0, 0))   # stock with cheek riser
    g.box((0, -0.15, 0.085), (0.05, 0.16, 0.03), m["wood"])
    g.box((0, -0.42, -0.005), (0.07, 0.03, 0.14), m["dark"])
    g.box((0, -0.06, -0.08), (0.045, 0.065, 0.14), m["wood"], rot=(0.25, 0, 0))
    g.box((0, 0.22, -0.10), (0.045, 0.08, 0.10), m["dark"])                      # magazine
    g.box((-0.03, 0.78, -0.03), (0.01, 0.22, 0.01), m["steel"], rot=(0, 0, -0.5))   # folded bipod
    g.box((0.03, 0.78, -0.03), (0.01, 0.22, 0.01), m["steel"], rot=(0, 0, 0.5))
    _trigger_guard(g, m)
    export("sniper", [g.build(), empty("Muzzle", (0, 1.36, 0.035))])


def make_pistol():
    m = _gun_mats()
    g = Part("Pistol")
    g.box((0, 0.10, 0.05), (0.04, 0.30, 0.055), m["steel"])                      # slide
    g.box((0, 0.10, 0.012), (0.035, 0.26, 0.03), m["dark"])                      # frame
    g.box((0.022, 0.10, 0.05), (0.004, 0.12, 0.02), m["accent"])
    g.box((-0.022, 0.10, 0.05), (0.004, 0.12, 0.02), m["accent"])
    g.cone((0, 0.27, 0.05), 0.011, 0.011, 0.05, m["dark"], segments=8, axis="Y")     # barrel tip
    g.box((0, -0.03, -0.05), (0.04, 0.07, 0.14), m["poly"], rot=(0.22, 0, 0))    # grip
    g.box((0, 0.24, 0.083), (0.012, 0.012, 0.015), m["steel"])                   # front sight
    g.box((0, -0.04, 0.083), (0.03, 0.012, 0.015), m["steel"])                   # rear sight
    g.box((0, 0.17, -0.025), (0.03, 0.10, 0.025), m["dark"])                     # rail under the barrel
    _trigger_guard(g, m, y=0.06, z=-0.03)
    export("pistol", [g.build(), empty("Muzzle", (0, 0.30, 0.05))])


def make_pickaxe():
    wood = material("pick_wood", (0.45, 0.28, 0.12))
    steel = material("pick_steel", (0.66, 0.68, 0.72), rough=0.3)
    dark = material("pick_dark", (0.15, 0.15, 0.18))
    accent = material("accent", (0.60, 0.60, 0.65), rough=0.35)
    p = Part("Pickaxe")
    p.box((0, 0.30, 0), (0.045, 0.80, 0.045), wood)
    p.box((0, -0.12, 0), (0.05, 0.05, 0.05), dark)
    p.box((0, 0.68, 0), (0.06, 0.09, 0.09), dark)                                 # head socket
    for sgn in (-1, 1):
        p.box((0, 0.70, sgn * 0.12), (0.045, 0.07, 0.20), steel, rot=(sgn * 0.25, 0, 0))
        p.box((0, 0.70, sgn * 0.27), (0.04, 0.06, 0.14), steel, rot=(sgn * 0.7, 0, 0))
        p.box((0, 0.71, sgn * 0.34), (0.03, 0.04, 0.08), steel, rot=(sgn * 1.0, 0, 0))
    p.box((0.026, 0.46, 0), (0.008, 0.20, 0.03), accent)
    export("pickaxe", [p.build()])


# ------------------------------------------------------------- weapons & items



def make_bandage():
    white = material("bandage_white", (0.95, 0.95, 0.92))
    red = material("bandage_red", (0.85, 0.15, 0.15))
    b = Part("Bandage")
    b.cone((0, 0, 0.12), 0.16, 0.16, 0.24, white, segments=10)
    b.box((0, 0, 0.12), (0.30, 0.06, 0.22), red)
    export("bandage", [b.build()])


def make_medkit():
    white = material("medkit_white", (0.95, 0.95, 0.95))
    red = material("medkit_red", (0.85, 0.12, 0.12))
    m = Part("Medkit")
    m.box((0, 0, 0.15), (0.42, 0.18, 0.30), white)
    m.box((0, -0.095, 0.15), (0.28, 0.02, 0.08), red)
    m.box((0, -0.095, 0.15), (0.08, 0.02, 0.28), red)
    m.box((0, 0, 0.33), (0.18, 0.05, 0.06), material("medkit_grey", (0.4, 0.4, 0.42)))
    export("medkit", [m.build()])


def make_potion(name, color, size):
    glass = material(name + "_liquid", color, rough=0.15, emit=color, emit_strength=0.25)
    cork = material(name + "_cork", (0.45, 0.30, 0.15))
    p = Part(name)
    p.cone((0, 0, 0.18 * size), 0.17 * size, 0.17 * size, 0.30 * size, glass, segments=10)
    p.cone((0, 0, 0.38 * size), 0.07 * size, 0.07 * size, 0.14 * size, glass, segments=8)
    p.cone((0, 0, 0.48 * size), 0.075 * size, 0.075 * size, 0.06 * size, cork, segments=8)
    export(name, [p.build()])


def make_ammo_pickup():
    brass = material("ammo_brass", (0.85, 0.65, 0.2), rough=0.3)
    box = material("ammo_box", (0.25, 0.35, 0.2))
    a = Part("AmmoPickup")
    a.box((0, 0, 0.12), (0.40, 0.26, 0.24), box)
    for i in range(3):
        a.cone(((i - 1) * 0.10, 0, 0.30), 0.04, 0.03, 0.14, brass, segments=6)
    export("ammo_pickup", [a.build()])


# ------------------------------------------------------------- chests & drops


def make_chest():
    wood = material("chest_wood", (0.45, 0.26, 0.10))
    gold = material("chest_gold", (0.95, 0.72, 0.18), rough=0.3, emit=(1.0, 0.6, 0.1))
    base = Part("Chest")
    base.box((0, 0, 0.30), (1.10, 0.70, 0.60), wood)
    base.box((0, 0, 0.30), (1.14, 0.12, 0.64), gold)
    base.box((0.45, 0, 0.30), (0.12, 0.74, 0.64), gold)
    base.box((-0.45, 0, 0.30), (0.12, 0.74, 0.64), gold)
    base.box((0, -0.36, 0.45), (0.14, 0.05, 0.16), gold)  # lock plate on the front (-Y)
    # lid hinged at the back edge so Godot can rotate it open
    hinge = (0, 0.35, 0.60)
    lid = Part("Lid", origin=hinge)
    lid.box((0, 0, 0.72), (1.10, 0.70, 0.12), wood)
    lid.box((0, 0, 0.80), (1.00, 0.60, 0.10), wood)
    lid.box((0, 0, 0.76), (0.14, 0.74, 0.22), gold)
    export("chest", [base.build(), lid.build()])


def make_ammo_box():
    green = material("abox_green", (0.28, 0.38, 0.22))
    dark = material("abox_dark", (0.18, 0.22, 0.16))
    yellow = material("abox_yellow", (0.95, 0.80, 0.15))
    base = Part("AmmoBox")
    base.box((0, 0, 0.25), (0.90, 0.50, 0.50), green)
    base.box((0, 0, 0.52), (0.50, 0.08, 0.06), dark)  # carry handle
    base.box((0, -0.255, 0.30), (0.50, 0.02, 0.14), yellow)
    hinge = (0, 0.25, 0.50)
    lid = Part("Lid", origin=hinge)
    lid.box((0, 0, 0.55), (0.94, 0.54, 0.10), green)
    export("ammo_box", [base.build(), lid.build()])


def make_supply():
    red = material("sup_red", (0.82, 0.14, 0.12))
    white = material("sup_white", (0.95, 0.95, 0.95))
    rope = material("sup_rope", (0.85, 0.82, 0.7))
    balloon_a = material("sup_balloon_a", (0.95, 0.55, 0.12))
    balloon_b = material("sup_balloon_b", (0.98, 0.95, 0.9))
    crate = Part("Crate")
    crate.box((0, 0, 0.45), (1.20, 1.20, 0.90), red)
    crate.box((0, 0, 0.45), (1.24, 0.22, 0.94), white)
    crate.box((0, 0, 0.45), (0.22, 1.24, 0.94), white)
    hinge = (0, 0.6, 0.90)
    lid = Part("Lid", origin=hinge)
    lid.box((0, 0, 0.95), (1.24, 1.24, 0.10), white)
    balloon = Part("Balloon")
    balloon.blob((0, 0, 7.5), 2.6, balloon_a, squash=1.25, jitter=0.0, seed=3)
    balloon.blob((0, 0, 7.5), 2.65, balloon_b, squash=0.4, jitter=0.0, seed=3)
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        balloon.box((sx * 0.9, sy * 0.9, 3.6), (0.06, 0.06, 6.4), rope, rot=(sy * 0.12, -sx * 0.12, 0))
    export("supply", [crate.build(), lid.build(), balloon.build()])


# ------------------------------------------------------------- sky ferry & glider


def make_bus():
    hull = material("bus_hull", (0.12, 0.55, 0.62), rough=0.5)
    belly = material("bus_belly", (0.95, 0.60, 0.15))
    glass = material("bus_glass", (0.75, 0.9, 1.0), rough=0.1)
    steel = material("bus_steel", (0.55, 0.58, 0.62), rough=0.4)
    bus = Part("Bus")
    bus.cone((0, 0, 0), 1.9, 1.9, 13.0, hull, segments=12, rot_z=0.0)  # placeholder cylinder, re-oriented below
    # rebuild as a horizontal hull: cylinders point along Z by default, so rotate verts
    bm = bus.bm
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"), verts=bm.verts)
    bus.box((0, 0, -1.55), (2.6, 11.0, 0.7), belly)
    for i in range(6):
        bus.box((0, -4.5 + i * 1.8 + 0.0, 0.6), (4.04, 1.0, 0.9), glass)
    bus.box((0, 6.7, 0.2), (2.4, 2.2, 2.4), hull)  # nose block
    bus.box((0, -6.2, 1.9), (0.3, 2.8, 2.6), belly)  # tail fin
    bus.box((0, -6.0, 0.4), (6.0, 1.4, 0.18), belly)  # tail plane
    bus.box((0, 1.0, 0.1), (9.0, 2.0, 0.22), steel)  # wings
    bus.box((-4.2, 1.0, 0.1), (0.2, 0.5, 0.5), steel)
    bus.box((4.2, 1.0, 0.1), (0.2, 0.5, 0.5), steel)
    objs = [bus.build()]
    for side, sx in (("L", -4.2), ("R", 4.2)):
        prop = Part("Prop" + side, origin=(sx, 1.9, 0.1))
        prop.box((sx, 1.9, 0.1), (0.5, 0.12, 4.2), steel)
        prop.box((sx, 1.9, 0.1), (4.2, 0.12, 0.5), steel)
        prop.box((sx, 1.7, 0.1), (0.7, 0.5, 0.7), belly)
        objs.append(prop.build())
    export("battle_bus", objs)


def make_glider():
    orange = material("gl_orange", (0.95, 0.45, 0.12))
    cream = material("gl_cream", (0.98, 0.93, 0.80))
    rope = material("gl_rope", (0.2, 0.2, 0.22))
    g = Part("Glider")
    # arched canopy of three panels, origin at the pilot's feet, shoulders at z=1.45
    g.box((0, 0.0, 2.75), (1.5, 1.7, 0.07), orange)
    g.box((-1.35, 0.0, 2.62), (1.4, 1.6, 0.07), cream, rot=(0, -0.22, 0))
    g.box((1.35, 0.0, 2.62), (1.4, 1.6, 0.07), cream, rot=(0, 0.22, 0))
    g.box((-2.35, 0.0, 2.35), (1.0, 1.3, 0.07), orange, rot=(0, -0.55, 0))
    g.box((2.35, 0.0, 2.35), (1.0, 1.3, 0.07), orange, rot=(0, 0.55, 0))
    for sx in (-1, 1):
        g.box((sx * 0.42, 0.0, 2.1), (0.03, 0.03, 1.4), rope, rot=(0, sx * 0.55, 0))
    export("glider", [g.build()])


# ------------------------------------------------------------- POI buildings & props

def make_poi_buildings():
    # lakeside lodge: big timber hall with a porch and a stone chimney
    def lodge_extra(h):
        stone = material("lodge_stone", (0.50, 0.48, 0.46))
        post = material("lodge_post", (0.35, 0.22, 0.12))
        h.box((6.2, 1.0, 3.0), (1.6, 1.6, 6.0), stone)                       # chimney stack
        for px in (-4.5, -1.5, 1.5, 4.5):                                    # porch posts and roof
            h.box((px, -5.9, 1.5), (0.3, 0.3, 3.0), post)
        h.box((0, -6.3, 3.05), (13.0, 2.6, 0.2), post)
    make_house("lodge", 14.0, 10.0, 3.6, (0.62, 0.45, 0.26), (0.28, 0.20, 0.14), (0.38, 0.25, 0.13), 2.6, [-4.0, -1.5, 1.5, 4.0], door_w=1.8, door_h=2.5, extra=lodge_extra)
    reset_scene()
    make_house("cabin", 6.5, 5.5, 2.9, (0.50, 0.34, 0.18), (0.24, 0.30, 0.20), (0.32, 0.20, 0.10), 1.7, [-1.8, 1.8])
    reset_scene()
    # barn: red with white trim and a wide door
    def barn_extra(h):
        white = material("barn_white", (0.95, 0.95, 0.92))
        for sgn in (-1, 1):
            h.box((sgn * 1.7, -7.12, 1.7), (0.18, 0.12, 3.4), white)
        h.box((0, -7.12, 3.4), (3.6, 0.12, 0.18), white)
        h.box((0, -7.12, 1.7), (3.4, 0.1, 0.12), white, rot=(0, 0.74, 0))
    make_house("barn", 10.0, 14.0, 4.2, (0.66, 0.14, 0.11), (0.35, 0.36, 0.40), (0.95, 0.95, 0.92), 3.2, [-3.0, 3.0], door_w=3.4, door_h=3.4, extra=barn_extra)
    reset_scene()
    make_house("warehouse", 18.0, 11.0, 5.5, (0.55, 0.58, 0.60), (0.26, 0.28, 0.32), (0.80, 0.55, 0.15), 0.9, [-6.0, 0.0, 6.0], door_w=4.0, door_h=4.2, win_z=(3.2, 4.6), win_w=1.8, roof_overhang=0.4)
    reset_scene()
    make_house("bunker", 10.0, 8.0, 3.0, (0.52, 0.53, 0.50), (0.38, 0.39, 0.37), (0.30, 0.31, 0.29), 0.45, [], door_w=1.8, door_h=2.4, roof_overhang=0.5)
    reset_scene()
    make_house("keeper_house", 6.0, 5.0, 2.8, (0.93, 0.93, 0.90), (0.62, 0.20, 0.16), (0.40, 0.40, 0.42), 1.6, [-1.6, 1.6])


def make_container():
    body = material("accent", (0.60, 0.60, 0.65), rough=0.6)
    rib = material("cont_rib", (0.14, 0.14, 0.16), rough=0.7)
    steel = material("cont_steel", (0.5, 0.5, 0.54), rough=0.4)
    c = Part("Container")
    c.box((0, 0, 1.3), (2.4, 6.0, 2.5), body)
    for i in range(-5, 6):
        c.box((0, i * 0.52, 1.3), (2.46, 0.08, 2.56), rib)
    c.box((0, -3.03, 1.3), (2.2, 0.06, 2.3), rib)
    c.box((0, -3.07, 1.3), (0.05, 0.04, 2.3), steel)
    for sx in (-0.35, 0.35):
        c.box((sx, -3.08, 1.3), (0.05, 0.05, 1.9), steel)
    export("container", [c.build()])


def make_silo():
    metal = material("silo_metal", (0.72, 0.75, 0.78), rough=0.4)
    band = material("silo_band", (0.45, 0.48, 0.52), rough=0.5)
    s_ = Part("Silo")
    s_.cone((0, 0, 5.5), 2.2, 2.2, 11.0, metal, segments=14)
    for z in (1.5, 4.5, 7.5, 10.2):
        s_.cone((0, 0, z), 2.27, 2.27, 0.25, band, segments=14)
    s_.cone((0, 0, 11.7), 2.2, 0.35, 1.8, metal, segments=14)
    s_.box((0, -2.3, 1.0), (0.9, 0.2, 2.0), band)
    export("silo", [s_.build()])


def make_windmill():
    wood = material("wm_wood", (0.55, 0.38, 0.20))
    white = material("wm_white", (0.92, 0.90, 0.85))
    red = material("wm_red", (0.62, 0.18, 0.14))
    mill = Part("Windmill")
    mill.cone((0, 0, 5.0), 3.0, 1.8, 10.0, white, segments=8)
    mill.cone((0, 0, 10.9), 2.0, 0.2, 2.0, red, segments=8)
    mill.box((0, -3.0, 1.1), (1.2, 0.2, 2.2), wood)
    mill.box((0, 1.7, 9.2), (0.9, 1.4, 0.9), wood)          # hub housing
    blades = Part("Blades", origin=(0, 2.5, 9.2))
    blades.box((0, 2.5, 9.2), (0.45, 0.35, 0.45), red)
    for ang in (0.0, math.pi / 2, math.pi, 3 * math.pi / 2):
        cx, cz = math.sin(ang), math.cos(ang)
        blades.box((cx * 3.2, 2.5, 9.2 + cz * 3.2), (0.5 if abs(cz) > 0.5 else 5.8, 0.12, 5.8 if abs(cz) > 0.5 else 0.5), wood)
        blades.box((cx * 3.4, 2.46, 9.2 + cz * 3.4), (0.9 if abs(cz) > 0.5 else 3.8, 0.1, 3.8 if abs(cz) > 0.5 else 0.9), white)
    export("windmill", [mill.build(), blades.build()])


def make_lighthouse():
    white = material("lh_white", (0.95, 0.95, 0.93))
    red = material("lh_red", (0.78, 0.14, 0.12))
    glass = material("lh_glass", (0.9, 0.95, 1.0), rough=0.1, emit=(1.0, 0.9, 0.5), emit_strength=0.8)
    iron = material("lh_iron", (0.15, 0.15, 0.18))
    lh = Part("Lighthouse")
    z = 0.0
    radii = [(3.4, 3.0), (3.0, 2.7), (2.7, 2.45), (2.45, 2.25)]
    for i, (r0, r1) in enumerate(radii):
        lh.cone((0, 0, z + 2.0), r0, r1, 4.0, red if i % 2 == 0 else white, segments=14)
        z += 4.0
    lh.cone((0, 0, z + 0.15), 3.2, 3.2, 0.3, iron, segments=14)             # gallery floor
    lh.cone((0, 0, z + 1.9), 1.6, 1.6, 3.2, glass, segments=10)              # lamp room
    for ang in range(8):
        a = ang * math.pi / 4
        lh.box((math.cos(a) * 1.65, math.sin(a) * 1.65, z + 1.9), (0.12, 0.12, 3.3), iron)
    lh.cone((0, 0, z + 4.2), 2.1, 0.2, 1.8, red, segments=10)
    lh.box((0, -3.3, 1.2), (1.2, 0.3, 2.4), iron)
    export("lighthouse", [lh.build()])


def make_watchtower():
    wood = material("wt_wood", (0.45, 0.30, 0.16))
    dark = material("wt_dark", (0.28, 0.20, 0.12))
    roof = material("wt_roof", (0.35, 0.36, 0.38))
    t = Part("Watchtower")
    for sx in (-1, 1):
        for sy in (-1, 1):
            t.box((sx * 1.5, sy * 1.5, 3.0), (0.3, 0.3, 6.0), wood)
    for z in (1.5, 3.5):
        for ang in (0, math.pi / 2):
            t.box((0, 0, z), (3.4, 0.15, 0.15), dark, rot_z=ang)
    t.box((0, 0, 6.1), (3.8, 3.8, 0.25), dark)                               # platform
    for sgn in (-1, 1):
        t.box((sgn * 1.85, 0, 6.8), (0.12, 3.8, 1.2), wood)
        t.box((0, sgn * 1.85, 6.8), (3.8, 0.12, 1.2), wood)
    for sx in (-1, 1):
        for sy in (-1, 1):
            t.box((sx * 1.85, sy * 1.85, 8.0), (0.18, 0.18, 2.4), dark)
    t.cone((0, 0, 9.5), 3.7, 0.2, 1.6, roof, segments=4, rot_z=math.pi / 4)
    for i in range(12):                                                       # ladder
        t.box((0.0, -1.62, 0.5 + i * 0.5), (0.7, 0.08, 0.08), dark)
    t.box((-0.35, -1.62, 3.0), (0.07, 0.08, 6.0), dark)
    t.box((0.35, -1.62, 3.0), (0.07, 0.08, 6.0), dark)
    export("watchtower", [t.build()])


def make_crane():
    steel = material("crane_steel", (0.88, 0.62, 0.12), rough=0.5)
    dark = material("crane_dark", (0.2, 0.2, 0.22))
    cr = Part("Crane")
    for sx in (-1, 1):
        for sy in (-1, 1):
            cr.box((sx * 3.5, sy * 1.2, 7.0), (0.5, 0.5, 14.0), steel)
    for z in (3.0, 7.0, 11.0):
        cr.box((0, 1.2, z), (7.4, 0.3, 0.3), steel)
        cr.box((0, -1.2, z), (7.4, 0.3, 0.3), steel)
    cr.box((0, 0, 14.4), (9.0, 3.2, 0.8), steel)
    cr.box((0, -9.0, 15.0), (1.2, 22.0, 1.0), steel)                         # boom
    cr.box((0, 0, 16.2), (2.4, 2.4, 2.0), dark)                              # cab
    cr.box((0, -16.0, 11.0), (0.1, 0.1, 8.0), dark)                          # cable
    cr.box((0, -16.0, 6.8), (0.8, 0.8, 0.6), dark)                           # hook block
    export("crane", [cr.build()])


def make_chimney():
    brick = material("ch_brick", (0.58, 0.28, 0.20))
    white = material("ch_white", (0.93, 0.93, 0.9))
    c = Part("Chimney")
    z = 0.0
    for i in range(5):
        c.cone((0, 0, z + 2.0), 1.5 - i * 0.12, 1.38 - i * 0.12, 4.0, brick if i % 2 == 0 else white, segments=12)
        z += 4.0
    c.cone((0, 0, z + 0.2), 1.0, 1.0, 0.4, material("ch_top", (0.15, 0.15, 0.17)), segments=12)
    export("chimney", [c.build()])


def make_tank():
    metal = material("tank_metal", (0.70, 0.72, 0.75), rough=0.4)
    dark = material("tank_dark", (0.25, 0.27, 0.30))
    t = Part("Tank")
    t.cone((0, 0, 3.5), 3.2, 3.2, 7.0, metal, segments=16)
    t.cone((0, 0, 7.4), 3.2, 1.0, 0.8, metal, segments=16)
    t.cone((0, 0, 1.0), 3.3, 3.3, 0.3, dark, segments=16)
    for i in range(14):
        t.box((3.35, 0, 0.6 + i * 0.5), (0.1, 0.8, 0.08), dark)
    t.box((3.4, 0.45, 3.5), (0.08, 0.08, 7.0), dark)
    t.box((3.4, -0.45, 3.5), (0.08, 0.08, 7.0), dark)
    export("tank", [t.build()])


def make_haystack():
    straw = material("hay_straw", (0.85, 0.72, 0.30))
    dark = material("hay_dark", (0.70, 0.56, 0.22))
    h = Part("Haystack")
    h.cone((0, 0, 0.8), 1.5, 1.5, 1.6, straw, segments=10)
    h.blob((0, 0, 1.6), 1.5, dark, squash=0.55, jitter=0.05, seed=2)
    export("haystack", [h.build()])


def make_fence():
    wood = material("fence_wood", (0.55, 0.38, 0.20))
    f = Part("Fence")
    for x in (-1.5, 0.0, 1.5):
        f.box((x, 0, 0.55), (0.14, 0.14, 1.1), wood)
    for z in (0.45, 0.85):
        f.box((0, 0, z), (3.1, 0.07, 0.12), wood)
    export("fence", [f.build()])


def make_sandbags():
    sand = material("sb_sand", (0.70, 0.62, 0.42))
    dark = material("sb_dark", (0.58, 0.50, 0.34))
    sb = Part("Sandbags")
    rng = random.Random(4)
    for row in range(3):
        for i in range(6):
            x = -1.45 + i * 0.58 + (0.29 if row % 2 else 0)
            sb.box((x, rng.uniform(-0.03, 0.03), 0.18 + row * 0.30), (0.56, 0.42, 0.28), sand if (i + row) % 2 else dark, rot_z=rng.uniform(-0.05, 0.05))
    export("sandbags", [sb.build()])


def make_radar():
    concrete = material("rd_concrete", (0.6, 0.6, 0.58))
    white = material("rd_white", (0.92, 0.93, 0.95), rough=0.4)
    red = material("rd_red", (0.8, 0.15, 0.12))
    base = Part("RadarBase")
    base.box((0, 0, 0.4), (5.0, 5.0, 0.8), concrete)
    base.cone((0, 0, 3.8), 1.0, 0.7, 6.0, concrete, segments=8)
    base.box((0, 0, 7.1), (1.6, 1.6, 0.4), concrete)
    dish = Part("Dish", origin=(0, 0, 7.6))
    dish.cone((0, 0, 8.4), 3.6, 0.5, 1.5, white, segments=16, axis="Z")        # bowl (wide end at the bottom, tilted below)
    dish.box((0, 0, 7.8), (0.5, 0.5, 0.9), concrete)
    dish.box((0, 1.5, 9.4), (0.1, 3.0, 0.1), red, rot=(0.6, 0, 0))
    dish.box((0, 0, 9.5), (0.35, 0.35, 0.35), red)
    export("radar", [base.build(), dish.build()])


def make_vault():
    steel = material("vault_steel", (0.30, 0.32, 0.36), rough=0.35)
    red = material("accent", (0.9, 0.2, 0.15), rough=0.4, emit=(0.9, 0.1, 0.05), emit_strength=0.8)
    dark = material("vault_dark", (0.12, 0.12, 0.14))
    base = Part("Chest")
    base.box((0, 0, 0.42), (1.3, 0.9, 0.84), steel)
    base.box((0, -0.46, 0.42), (1.0, 0.06, 0.66), dark)
    base.box((0, -0.5, 0.42), (0.35, 0.05, 0.35), red)
    for sx in (-0.62, 0.62):
        base.box((sx, 0, 0.42), (0.1, 0.94, 0.9), dark)
    hinge = (0, 0.45, 0.84)
    lid = Part("Lid", origin=hinge)
    lid.box((0, 0, 0.9), (1.3, 0.9, 0.12), steel)
    lid.box((0, 0, 0.98), (0.9, 0.6, 0.06), red)
    export("vault", [base.build(), lid.build()])


def main():
    reset_scene()
    make_player()
    reset_scene()
    make_assault()
    reset_scene()
    make_tree()
    reset_scene()
    make_rock()
    reset_scene()
    make_crate()
    reset_scene()
    make_house("house_a", 8.0, 7.0, 3.2, (0.93, 0.90, 0.82), (0.68, 0.22, 0.17), (0.42, 0.30, 0.20), 1.9, [-2.2, 2.2])
    reset_scene()
    make_house("house_b", 10.0, 8.0, 3.4, (0.55, 0.65, 0.78), (0.22, 0.26, 0.34), (0.90, 0.90, 0.92), 1.6, [-3.0, 0.0, 3.0])
    reset_scene()
    make_tower()
    for fn in (make_pistol, make_smg, make_shotgun, make_sniper, make_pickaxe, make_bandage, make_medkit,
               make_ammo_pickup, make_chest, make_ammo_box, make_supply, make_bus, make_glider):
        reset_scene()
        fn()
    for fn in (make_poi_buildings, make_container, make_silo, make_windmill, make_lighthouse, make_watchtower, make_crane,
               make_chimney, make_tank, make_haystack, make_fence, make_sandbags, make_radar, make_vault):
        reset_scene()
        fn()
    reset_scene()
    make_potion("mini_shield", (0.25, 0.55, 1.0), 0.8)
    reset_scene()
    make_potion("shield_potion", (0.20, 0.45, 1.0), 1.25)


if __name__ == "__main__":
    main()
