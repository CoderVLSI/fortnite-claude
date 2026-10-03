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

    def wedge(self, x0, x1, y_low, y_high, z_low, z_high, mat):
        """A solid ramp: flat bottom at z_low, the top rises from z_low at y_low to z_high at y_high (walkable stairs)."""
        o = self.origin
        pts = [(x0, y_low, z_low), (x1, y_low, z_low), (x0, y_high, z_low), (x1, y_high, z_low), (x0, y_high, z_high), (x1, y_high, z_high)]
        vs = [self.bm.verts.new(Vector(pt) - o) for pt in pts]
        for idx in ((0, 1, 3, 2), (2, 3, 5, 4), (0, 2, 4), (1, 5, 3), (0, 4, 5, 1)):
            try:
                self.bm.faces.new([vs[i] for i in idx])
            except ValueError:
                pass
        bmesh.ops.recalc_face_normals(self.bm, faces=list(self.bm.faces))
        self._tag(vs, mat)

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
            @ (Matrix.Rotation(-math.pi / 2, 4, "X") if axis == "Y" else (Matrix.Rotation(math.pi / 2, 4, "Y") if axis == "X" else Matrix.Identity(4)))
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


def walls(part, mat, hw, hd, height, thick, door_x, windows, door_w=1.3, door_h=2.25, win_z=(1.0, 2.2), win_w=1.4, base_z=0.0):
    """Four walls of a rectangular building; door on the -Y (front) wall."""
    holes_front = [(door_x - door_w / 2, door_x + door_w / 2, base_z, base_z + door_h)]
    holes_back = [(wx - win_w / 2, wx + win_w / 2, base_z + win_z[0], base_z + win_z[1]) for wx in windows]
    holes_side = [(-win_w / 2, win_w / 2, base_z + win_z[0], base_z + win_z[1])] if windows else []

    def wall_x(y, holes):
        cuts = sorted(holes)
        cursor = -hw
        for x0, x1, z0, z1 in cuts:
            part.box_span(cursor, x0, y - thick / 2, y + thick / 2, base_z, base_z + height, mat)
            part.box_span(x0, x1, y - thick / 2, y + thick / 2, base_z, z0, mat)
            part.box_span(x0, x1, y - thick / 2, y + thick / 2, z1, height, mat)
            cursor = x1
        part.box_span(cursor, hw, y - thick / 2, y + thick / 2, base_z, base_z + height, mat)

    def wall_y(x, holes):
        cuts = sorted(holes)
        cursor = -hd
        for y0, y1, z0, z1 in cuts:
            part.box_span(x - thick / 2, x + thick / 2, cursor, y0, base_z, base_z + height, mat)
            part.box_span(x - thick / 2, x + thick / 2, y0, y1, base_z, z0, mat)
            part.box_span(x - thick / 2, x + thick / 2, y0, y1, z1, height, mat)
            cursor = y1
        part.box_span(x - thick / 2, x + thick / 2, cursor, hd, base_z, base_z + height, mat)

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
# Every model is built mirror-symmetric about its centre plane (x = 0, or z = 0 for the pickaxe
# head) via sbox(): anything off-centre is created on both sides. The designs follow the generated
# 2D icons in assets/icons (olive AR, desert SMG, grey slide pistol, wood pump shotgun, olive
# scoped bolt rifle, curved double-ended pickaxe).


def _gun_mats():
    return dict(
        dark=material("gun_dark", (0.10, 0.10, 0.12), rough=0.45),
        steel=material("gun_steel", (0.34, 0.35, 0.38), rough=0.30),
        wood=material("gun_wood", (0.45, 0.24, 0.09)),
        poly=material("gun_poly", (0.20, 0.21, 0.23), rough=0.6),
        accent=material("accent", (0.60, 0.60, 0.65), rough=0.35),
        glass=material("scope_glass", (0.25, 0.55, 0.95), rough=0.1, emit=(0.1, 0.3, 0.8), emit_strength=0.6),
        brass=material("gun_brass", (0.85, 0.65, 0.2), rough=0.3),
        olive=material("gun_olive", (0.30, 0.36, 0.14), rough=0.7),
        tan=material("gun_tan", (0.66, 0.52, 0.22), rough=0.7),
        slide=material("gun_slide", (0.55, 0.57, 0.60), rough=0.3),
        orange=material("gun_orange", (0.78, 0.38, 0.10), rough=0.8),
    )


def sbox(g, x, y, z, size, mat, rot=(0.0, 0.0, 0.0)):
    """Box at +x and mirrored at -x (a single centred box when x == 0)."""
    g.box((x, y, z), size, mat, rot=rot)
    if abs(x) > 1e-6:
        g.box((-x, y, z), size, mat, rot=(rot[0], -rot[1], -rot[2]))


def _trigger_guard(g, m, y=0.04, z=-0.075):
    g.box((0, y, z), (0.02, 0.10, 0.012), m["steel"])
    g.box((0, y - 0.045, z + 0.025), (0.02, 0.012, 0.06), m["steel"])
    g.box((0, y + 0.03, z + 0.03), (0.012, 0.014, 0.05), m["dark"])    # trigger


def make_assault():
    m = _gun_mats()
    g = Part("Rifle")
    g.box((0, 0.04, -0.005), (0.07, 0.30, 0.10), m["dark"])                       # lower receiver
    g.box((0, 0.19, 0.055), (0.07, 0.42, 0.075), m["dark"])                       # upper receiver
    g.box((0, 0.19, 0.098), (0.04, 0.40, 0.012), m["steel"])                      # top rail
    sbox(g, 0.037, 0.19, 0.055, (0.006, 0.22, 0.03), m["accent"])                 # rarity strip
    g.box((0, 0.015, 0.135), (0.026, 0.05, 0.05), m["dark"])                      # rear sight tower
    g.box((0, 0.16, 0.152), (0.022, 0.30, 0.016), m["dark"])                      # carry handle
    g.box((0, 0.31, 0.135), (0.026, 0.035, 0.05), m["dark"])                      # handle front post
    g.box((0, 0.56, 0.03), (0.082, 0.30, 0.085), m["olive"])                      # handguard
    g.box((0, 0.56, 0.082), (0.036, 0.28, 0.012), m["steel"])                     # handguard rail
    for yy in (0.46, 0.53, 0.60, 0.67):                                           # M-LOK slots
        sbox(g, 0.042, yy, 0.03, (0.004, 0.035, 0.028), m["dark"])
    g.cone((0, 0.86, 0.03), 0.014, 0.014, 0.28, m["steel"], segments=8, axis="Y")   # barrel
    g.box((0, 0.74, 0.088), (0.014, 0.03, 0.07), m["dark"])                       # front sight post
    g.cone((0, 1.02, 0.03), 0.022, 0.022, 0.08, m["dark"], segments=8, axis="Y")    # flash hider
    g.cone((0, -0.12, 0.03), 0.026, 0.026, 0.14, m["dark"], segments=8, axis="Y")   # buffer tube
    g.box((0, -0.25, 0.015), (0.055, 0.17, 0.095), m["olive"])                    # stock
    g.box((0, -0.34, 0.0), (0.06, 0.025, 0.12), m["dark"])                        # butt pad
    g.box((0, -0.05, -0.085), (0.048, 0.07, 0.15), m["olive"], rot=(0.3, 0, 0))   # pistol grip
    g.box((0, 0.17, -0.125), (0.05, 0.085, 0.17), m["dark"], rot=(-0.12, 0, 0))   # magazine (curved: 2 pieces)
    g.box((0, 0.195, -0.255), (0.05, 0.085, 0.10), m["dark"], rot=(-0.32, 0, 0))
    sbox(g, 0.045, 0.12, 0.06, (0.012, 0.05, 0.02), m["steel"])                   # charging handle + opposite lug
    _trigger_guard(g, m)
    export("rifle", [g.build(), empty("Muzzle", (0, 1.07, 0.03))])


def make_smg():
    m = _gun_mats()
    g = Part("Smg")
    g.box((0, 0.12, 0.03), (0.07, 0.32, 0.10), m["dark"])                         # body
    g.box((0, 0.12, 0.088), (0.04, 0.30, 0.014), m["steel"])                      # rail
    sbox(g, 0.036, 0.12, 0.035, (0.006, 0.18, 0.03), m["accent"])
    g.box((0, 0.40, 0.03), (0.08, 0.26, 0.085), m["tan"])                         # handguard
    for yy in (0.32, 0.38, 0.44, 0.50):                                           # vents
        sbox(g, 0.041, yy, 0.03, (0.004, 0.03, 0.04), m["dark"])
    g.box((0, 0.40, 0.082), (0.036, 0.24, 0.012), m["steel"])
    g.cone((0, 0.60, 0.03), 0.016, 0.016, 0.16, m["steel"], segments=8, axis="Y")   # barrel
    g.cone((0, 0.69, 0.03), 0.022, 0.022, 0.05, m["dark"], segments=8, axis="Y")    # muzzle device
    g.box((0, 0.08, 0.115), (0.04, 0.07, 0.04), m["dark"])                        # red dot
    g.box((0, 0.112, 0.115), (0.03, 0.008, 0.03), m["glass"])
    g.box((0, -0.08, 0.04), (0.02, 0.10, 0.03), m["dark"])                        # stock hinge
    sbox(g, 0.026, -0.17, 0.04, (0.012, 0.20, 0.02), m["tan"])                    # twin folding stock struts
    g.box((0, -0.27, 0.035), (0.05, 0.022, 0.09), m["tan"])
    g.box((0, -0.05, -0.085), (0.05, 0.065, 0.15), m["tan"], rot=(0.3, 0, 0))     # grip
    g.box((0, 0.20, -0.17), (0.045, 0.07, 0.29), m["dark"], rot=(0.05, 0, 0))     # long magazine
    g.box((0, 0.21, -0.32), (0.05, 0.075, 0.025), m["steel"])
    g.box((0, 0.42, -0.045), (0.035, 0.05, 0.08), m["poly"])                      # foregrip
    _trigger_guard(g, m)
    export("smg", [g.build(), empty("Muzzle", (0, 0.72, 0.03))])


def make_shotgun():
    m = _gun_mats()
    g = Part("Shotgun")
    g.box((0, 0.14, 0.03), (0.075, 0.36, 0.10), m["dark"])                        # receiver
    sbox(g, 0.039, 0.14, 0.035, (0.006, 0.18, 0.03), m["accent"])
    g.cone((0, 0.68, 0.045), 0.019, 0.019, 0.72, m["steel"], segments=8, axis="Y")     # barrel
    g.cone((0, 0.62, -0.005), 0.024, 0.024, 0.58, m["dark"], segments=8, axis="Y")    # magazine tube
    g.box((0, 0.58, -0.005), (0.07, 0.24, 0.07), m["wood"])                       # pump forend
    for yy in (0.50, 0.545, 0.59, 0.635, 0.68):                                   # grip ribs
        g.box((0, yy, -0.005), (0.076, 0.016, 0.076), m["orange"])
    g.box((0, 1.04, 0.07), (0.012, 0.012, 0.025), m["brass"])                     # bead sight
    g.box((0, 0.10, 0.092), (0.03, 0.10, 0.012), m["steel"])
    g.box((0, -0.18, 0.0), (0.062, 0.34, 0.12), m["wood"], rot=(-0.06, 0, 0))     # stock
    g.box((0, -0.36, -0.01), (0.07, 0.03, 0.15), m["dark"])
    g.box((0, -0.04, -0.075), (0.045, 0.06, 0.12), m["wood"], rot=(0.25, 0, 0))
    _trigger_guard(g, m, y=0.03)
    export("shotgun", [g.build(), empty("Muzzle", (0, 1.04, 0.045))])


def make_sniper():
    m = _gun_mats()
    g = Part("Sniper")
    g.box((0, 0.20, 0.03), (0.07, 0.48, 0.10), m["dark"])                         # receiver
    sbox(g, 0.037, 0.2, 0.035, (0.006, 0.26, 0.03), m["accent"])
    g.cone((0, 0.90, 0.035), 0.016, 0.016, 0.82, m["steel"], segments=8, axis="Y")   # long barrel
    g.cone((0, 1.32, 0.035), 0.027, 0.027, 0.10, m["dark"], segments=8, axis="Y")    # muzzle brake
    sbox(g, 0.03, 1.32, 0.035, (0.012, 0.03, 0.02), m["steel"])                      # brake ports
    g.box((0, 0.58, -0.005), (0.07, 0.30, 0.07), m["olive"])                      # forend
    g.box((0.055, 0.12, 0.05), (0.012, 0.09, 0.012), m["steel"])                  # bolt handle (right side)
    g.box((0.07, 0.12, 0.05), (0.03, 0.02, 0.03), m["dark"])
    # scope: tube, objective bell, ocular, windage / elevation turrets
    g.cone((0, 0.26, 0.14), 0.030, 0.030, 0.36, m["dark"], segments=10, axis="Y")
    g.cone((0, 0.11, 0.14), 0.038, 0.038, 0.08, m["dark"], segments=10, axis="Y")
    g.cone((0, 0.44, 0.14), 0.050, 0.044, 0.12, m["dark"], segments=10, axis="Y")
    g.box((0, 0.50, 0.14), (0.07, 0.005, 0.07), m["glass"])
    sbox(g, 0.04, 0.26, 0.14, (0.03, 0.03, 0.03), m["steel"])
    g.box((0, 0.26, 0.185), (0.03, 0.03, 0.03), m["steel"])
    sbox(g, 0.0, 0.20, 0.09, (0.02, 0.03, 0.05), m["steel"])
    g.box((0, 0.33, 0.09), (0.02, 0.03, 0.05), m["steel"])
    g.box((0, -0.22, 0.015), (0.065, 0.40, 0.11), m["olive"], rot=(-0.04, 0, 0))  # chassis stock
    g.box((0, -0.15, 0.085), (0.05, 0.16, 0.03), m["olive"])                      # cheek riser
    g.box((0, -0.42, -0.005), (0.07, 0.03, 0.14), m["dark"])
    g.box((0, -0.06, -0.08), (0.045, 0.065, 0.14), m["olive"], rot=(0.25, 0, 0))
    g.box((0, 0.22, -0.10), (0.045, 0.08, 0.10), m["dark"])                       # magazine
    sbox(g, 0.03, 0.78, -0.03, (0.01, 0.22, 0.01), m["steel"], rot=(0, 0, 0.5))     # folded bipod legs
    _trigger_guard(g, m)
    export("sniper", [g.build(), empty("Muzzle", (0, 1.38, 0.035))])


def make_pistol():
    m = _gun_mats()
    g = Part("Pistol")
    g.box((0, 0.10, 0.05), (0.04, 0.30, 0.055), m["slide"])                       # slide
    for yy in (-0.02, 0.005, 0.03):                                               # rear serrations
        sbox(g, 0.0205, yy, 0.05, (0.003, 0.008, 0.04), m["dark"])
    g.box((0, 0.10, 0.012), (0.036, 0.26, 0.03), m["dark"])                       # frame
    sbox(g, 0.022, 0.12, 0.05, (0.004, 0.10, 0.02), m["accent"])
    g.cone((0, 0.27, 0.05), 0.011, 0.011, 0.05, m["dark"], segments=8, axis="Y")      # barrel tip
    g.box((0, -0.03, -0.05), (0.04, 0.07, 0.14), m["poly"], rot=(0.22, 0, 0))     # grip
    g.box((0, 0.24, 0.083), (0.012, 0.012, 0.015), m["steel"])                    # front sight
    sbox(g, 0.01, -0.04, 0.083, (0.01, 0.012, 0.015), m["steel"])                 # rear sight (two posts)
    g.box((0, 0.17, -0.025), (0.03, 0.10, 0.025), m["dark"])                      # accessory rail
    _trigger_guard(g, m, y=0.06, z=-0.03)
    export("pistol", [g.build(), empty("Muzzle", (0, 0.30, 0.05))])


def make_pickaxe():
    wood = material("pick_wood", (0.45, 0.28, 0.12))
    wrap = material("pick_wrap", (0.30, 0.17, 0.08))
    steel = material("pick_steel", (0.55, 0.57, 0.62), rough=0.3)
    dark = material("pick_dark", (0.17, 0.18, 0.21), rough=0.4)
    accent = material("accent", (0.60, 0.60, 0.65), rough=0.35)
    p = Part("Pickaxe")
    p.box((0, 0.30, 0), (0.042, 0.80, 0.042), wood)                               # handle
    for i in range(5):                                                            # leather wrap bands
        p.box((0, 0.10 + i * 0.07, 0), (0.05, 0.035, 0.05), wrap)
    p.box((0, -0.12, 0), (0.06, 0.06, 0.06), dark)                                # pommel
    p.box((0, 0.68, 0), (0.07, 0.12, 0.08), steel)                                # collar
    p.box((0, 0.68, 0), (0.075, 0.03, 0.085), dark)
    p.box((0, 0.74, 0), (0.06, 0.07, 0.07), dark)                                 # head socket
    # double-ended curved head, mirrored in z: segments follow an arc that bends down at the tips
    for sgn in (-1, 1):
        p.box((0, 0.76, sgn * 0.10), (0.04, 0.06, 0.16), dark, rot=(sgn * 0.12, 0, 0))
        p.box((0, 0.755, sgn * 0.23), (0.034, 0.05, 0.16), steel, rot=(sgn * 0.42, 0, 0))
        p.box((0, 0.725, sgn * 0.35), (0.028, 0.04, 0.12), steel, rot=(sgn * 0.85, 0, 0))
        p.box((0, 0.685, sgn * 0.42), (0.02, 0.03, 0.08), steel, rot=(sgn * 1.2, 0, 0))   # pointed tip
    sbox(p, 0.026, 0.46, 0, (0.008, 0.20, 0.03), accent)
    export("pickaxe", [p.build()])


# ------------------------------------------------------------- mythic weapons
# One bespoke model per weapon, following the generated Mythic icons: gold Hand Cannon revolver,
# hazard-striped Hornet SMG, purple Stormcaller AR, red-and-gold Dragonbreath shotgun and the
# teal Eclipse scoped rifle. Same grip origin / barrel axis / Muzzle empty as the base models, mirror-symmetric
# via sbox(), and the "accent" material is still tinted by the rarity colour in game.


def _mythic_mats():
    m = _gun_mats()
    m.update(
        gold=material("myth_gold", (0.92, 0.68, 0.18), rough=0.25),
        brass=material("myth_brass", (0.70, 0.45, 0.14), rough=0.3),
        teal=material("myth_teal", (0.05, 0.38, 0.42), rough=0.35),
        black=material("myth_black", (0.04, 0.04, 0.05), rough=0.5),
        yellow=material("myth_yellow", (0.98, 0.80, 0.05), rough=0.5),
        purple=material("myth_purple", (0.40, 0.20, 0.65), rough=0.4),
        gunmetal=material("myth_gunmetal", (0.16, 0.16, 0.21), rough=0.35),
        violet=material("myth_violet", (0.65, 0.35, 1.0), rough=0.2, emit=(0.5, 0.2, 1.0), emit_strength=1.2),
        red=material("myth_red", (0.62, 0.07, 0.07), rough=0.45),
        flame=material("myth_flame", (1.0, 0.45, 0.08), rough=0.3, emit=(1.0, 0.35, 0.05), emit_strength=1.4),
        cyan=material("myth_cyan", (0.30, 0.95, 1.0), rough=0.15, emit=(0.1, 0.8, 1.0), emit_strength=1.6),
    )
    return m


def make_pistol_mythic():
    m = _mythic_mats()
    g = Part("HandCannon")
    g.box((0, 0.06, 0.03), (0.05, 0.20, 0.09), m["gold"])                         # frame
    g.box((0, 0.20, 0.06), (0.036, 0.12, 0.05), m["brass"])                       # shroud under the rib
    g.cone((0, 0.11, 0.045), 0.062, 0.062, 0.13, m["brass"], segments=6, axis="Y")    # fluted cylinder
    for k in range(6):                                                            # chamber mouths (6-fold, mirror-safe)
        a = math.radians(30 + 60 * k)
        g.box((math.cos(a) * 0.036, 0.178, 0.045 + math.sin(a) * 0.036), (0.016, 0.006, 0.016), m["black"])
    g.cone((0, 0.30, 0.05), 0.021, 0.021, 0.20, m["gold"], segments=8, axis="Y")      # barrel
    g.box((0, 0.30, 0.088), (0.018, 0.22, 0.014), m["gold"])                      # top rib
    for yy in (0.24, 0.31):                                                       # ornamental bands
        g.cone((0, yy, 0.05), 0.030, 0.030, 0.018, m["teal"], segments=8, axis="Y")
    g.cone((0, 0.40, 0.05), 0.03, 0.026, 0.035, m["teal"], segments=8, axis="Y")      # muzzle crown
    g.box((0, -0.045, 0.092), (0.014, 0.045, 0.05), m["dark"], rot=(-0.45, 0, 0)) # hammer
    sbox(g, 0.028, 0.06, 0.035, (0.004, 0.13, 0.035), m["accent"])                # rarity glow
    g.box((0, -0.045, -0.05), (0.046, 0.08, 0.15), m["teal"], rot=(0.22, 0, 0))   # grip
    sbox(g, 0.025, -0.045, -0.05, (0.006, 0.05, 0.10), m["gold"], rot=(0.22, 0, 0))   # grip inlays
    g.box((0, 0.27, 0.09), (0.012, 0.012, 0.02), m["gold"])                       # front sight
    _trigger_guard(g, m, y=0.05, z=-0.03)
    export("pistol_mythic", [g.build(), empty("Muzzle", (0, 0.42, 0.05))])


def make_smg_mythic():
    m = _mythic_mats()
    g = Part("HornetSmg")
    g.box((0, 0.12, 0.03), (0.07, 0.32, 0.10), m["black"])                        # body
    g.box((0, 0.12, 0.088), (0.04, 0.30, 0.014), m["gunmetal"])                   # rail
    sbox(g, 0.036, 0.12, 0.035, (0.006, 0.18, 0.03), m["accent"])
    g.box((0, 0.40, 0.03), (0.08, 0.26, 0.085), m["black"])                       # handguard core
    for i in range(6):                                                            # hazard stripes
        if i % 2 == 0:
            g.box((0, 0.30 + i * 0.045, 0.03), (0.088, 0.024, 0.092), m["yellow"])
    g.cone((0, 0.62, 0.03), 0.017, 0.017, 0.18, m["gunmetal"], segments=8, axis="Y")  # barrel
    g.cone((0, 0.69, 0.03), 0.028, 0.028, 0.07, m["black"], segments=8, axis="Y")     # fat suppressor
    g.cone((0, 0.725, 0.03), 0.030, 0.030, 0.012, m["yellow"], segments=8, axis="Y")  # warning ring
    g.box((0, 0.08, 0.115), (0.04, 0.07, 0.04), m["black"])                       # sight
    g.box((0, 0.112, 0.115), (0.03, 0.008, 0.03), m["flame"])                     # amber lens
    g.box((0, -0.08, 0.04), (0.02, 0.10, 0.03), m["black"])
    sbox(g, 0.026, -0.17, 0.04, (0.012, 0.20, 0.02), m["gunmetal"])
    g.box((0, -0.27, 0.035), (0.05, 0.022, 0.09), m["yellow"])                    # stock plate
    g.box((0, -0.05, -0.085), (0.05, 0.065, 0.15), m["black"], rot=(0.3, 0, 0))   # grip
    g.box((0, 0.20, -0.12), (0.045, 0.07, 0.17), m["black"], rot=(0.04, 0, 0))    # curved magazine, 2 stripes
    g.box((0, 0.225, -0.27), (0.045, 0.07, 0.15), m["black"], rot=(0.22, 0, 0))
    g.box((0, 0.205, -0.15), (0.05, 0.075, 0.025), m["yellow"])
    g.box((0, 0.215, -0.22), (0.05, 0.075, 0.025), m["yellow"])
    g.box((0, 0.42, -0.045), (0.035, 0.05, 0.08), m["gunmetal"])
    _trigger_guard(g, m)
    export("smg_mythic", [g.build(), empty("Muzzle", (0, 0.74, 0.03))])


def make_assault_mythic():
    m = _mythic_mats()
    g = Part("StormcallerRifle")
    g.box((0, 0.04, -0.005), (0.07, 0.30, 0.10), m["gunmetal"])                   # lower receiver
    g.box((0, 0.19, 0.055), (0.07, 0.42, 0.075), m["gunmetal"])                   # upper receiver
    g.box((0, 0.19, 0.098), (0.04, 0.40, 0.012), m["violet"])                     # glowing top rail
    sbox(g, 0.037, 0.19, 0.055, (0.006, 0.22, 0.03), m["accent"])
    g.box((0, 0.015, 0.135), (0.026, 0.05, 0.05), m["dark"])
    g.box((0, 0.16, 0.152), (0.022, 0.30, 0.016), m["dark"])                      # carry handle
    g.box((0, 0.31, 0.135), (0.026, 0.035, 0.05), m["dark"])
    g.box((0, 0.56, 0.03), (0.082, 0.30, 0.085), m["purple"])                     # handguard
    for i in range(5):                                                            # lightning zig-zag, both sides
        sbox(g, 0.043, 0.45 + i * 0.055, 0.03 + (0.025 if i % 2 == 0 else -0.025), (0.004, 0.06, 0.012), m["violet"],
             rot=(0.7 if i % 2 == 0 else -0.7, 0, 0))
    g.cone((0, 0.86, 0.03), 0.014, 0.014, 0.28, m["steel"], segments=8, axis="Y")
    g.box((0, 0.74, 0.088), (0.014, 0.03, 0.07), m["dark"])
    g.cone((0, 1.0, 0.03), 0.016, 0.016, 0.07, m["dark"], segments=8, axis="Y")       # forked flash hider
    sbox(g, 0.022, 1.045, 0.03, (0.01, 0.07, 0.02), m["violet"])
    g.cone((0, -0.12, 0.03), 0.026, 0.026, 0.14, m["dark"], segments=8, axis="Y")
    g.box((0, -0.25, 0.015), (0.055, 0.17, 0.095), m["purple"])                   # stock
    g.box((0, -0.34, 0.0), (0.06, 0.025, 0.12), m["violet"])
    g.box((0, -0.05, -0.085), (0.048, 0.07, 0.15), m["purple"], rot=(0.3, 0, 0))
    g.box((0, 0.17, -0.125), (0.05, 0.085, 0.17), m["dark"], rot=(-0.12, 0, 0))
    g.box((0, 0.195, -0.255), (0.05, 0.085, 0.10), m["dark"], rot=(-0.32, 0, 0))
    g.box((0, 0.178, -0.17), (0.056, 0.09, 0.025), m["violet"], rot=(-0.12, 0, 0))   # glowing magazine band
    sbox(g, 0.045, 0.12, 0.06, (0.012, 0.05, 0.02), m["steel"])
    _trigger_guard(g, m)
    export("rifle_mythic", [g.build(), empty("Muzzle", (0, 1.08, 0.03))])


def make_shotgun_mythic():
    m = _mythic_mats()
    g = Part("DragonbreathShotgun")
    g.box((0, 0.14, 0.03), (0.075, 0.36, 0.10), m["red"])                         # receiver
    sbox(g, 0.039, 0.14, 0.035, (0.006, 0.20, 0.03), m["accent"])
    g.box((0, -0.01, 0.03), (0.08, 0.02, 0.105), m["gold"])                       # gold receiver rings
    g.box((0, 0.29, 0.03), (0.08, 0.02, 0.105), m["gold"])
    g.cone((0, 0.66, 0.045), 0.020, 0.020, 0.66, m["gunmetal"], segments=8, axis="Y") # barrel
    g.cone((0, 1.02, 0.045), 0.020, 0.048, 0.08, m["gold"], segments=8, axis="Y")     # flared dragon-mouth muzzle
    g.cone((0, 0.62, -0.005), 0.025, 0.025, 0.56, m["dark"], segments=8, axis="Y")
    for yy in (0.40, 0.55, 0.70, 0.85):                                           # gold barrel bands
        g.cone((0, yy, 0.045), 0.027, 0.027, 0.02, m["gold"], segments=8, axis="Y")
    g.box((0, 0.58, -0.005), (0.07, 0.24, 0.07), m["red"])                        # pump
    for yy in (0.50, 0.545, 0.59, 0.635, 0.68):
        g.box((0, yy, -0.005), (0.076, 0.016, 0.076), m["gold"])
    sbox(g, 0.034, -0.14, 0.03, (0.006, 0.22, 0.05), m["flame"], rot=(0, 0, 0))   # flame inlay on the stock
    g.box((0, -0.18, 0.0), (0.062, 0.34, 0.12), m["red"], rot=(-0.06, 0, 0))      # stock
    g.box((0, -0.36, -0.01), (0.07, 0.03, 0.15), m["gold"])
    g.box((0, -0.04, -0.075), (0.045, 0.06, 0.12), m["red"], rot=(0.25, 0, 0))
    g.box((0, 1.0, 0.085), (0.012, 0.012, 0.025), m["flame"])                     # ember bead sight
    _trigger_guard(g, m, y=0.03)
    export("shotgun_mythic", [g.build(), empty("Muzzle", (0, 1.07, 0.045))])


def make_sniper_mythic():
    m = _mythic_mats()
    g = Part("EclipseRifle")
    g.box((0, 0.20, 0.03), (0.07, 0.48, 0.10), m["black"])                        # receiver
    sbox(g, 0.037, 0.2, 0.035, (0.006, 0.26, 0.03), m["accent"])
    g.box((0, 0.2, 0.082), (0.03, 0.46, 0.012), m["cyan"])                        # glowing spine
    g.cone((0, 0.90, 0.035), 0.016, 0.016, 0.82, m["gunmetal"], segments=8, axis="Y")
    for i in range(6):                                                            # heat-sink rings
        g.cone((0, 0.62 + i * 0.09, 0.035), 0.026, 0.026, 0.022, m["teal"], segments=8, axis="Y")
    g.cone((0, 1.32, 0.035), 0.027, 0.027, 0.10, m["black"], segments=8, axis="Y")
    sbox(g, 0.03, 1.32, 0.035, (0.012, 0.03, 0.02), m["cyan"])
    g.box((0, 0.58, -0.005), (0.07, 0.30, 0.07), m["teal"])
    g.box((0.055, 0.12, 0.05), (0.012, 0.09, 0.012), m["steel"])
    g.box((0.07, 0.12, 0.05), (0.03, 0.02, 0.03), m["cyan"])
    g.cone((0, 0.26, 0.14), 0.032, 0.032, 0.36, m["black"], segments=10, axis="Y")    # scope
    g.cone((0, 0.11, 0.14), 0.040, 0.040, 0.08, m["black"], segments=10, axis="Y")
    g.cone((0, 0.44, 0.14), 0.054, 0.046, 0.12, m["black"], segments=10, axis="Y")
    g.cone((0, 0.505, 0.14), 0.056, 0.056, 0.012, m["cyan"], segments=12, axis="Y")   # glowing lens ring
    g.box((0, 0.512, 0.14), (0.07, 0.005, 0.07), m["glass"])
    sbox(g, 0.04, 0.26, 0.14, (0.03, 0.03, 0.03), m["teal"])
    g.box((0, 0.26, 0.185), (0.03, 0.03, 0.03), m["teal"])
    g.box((0, 0.20, 0.09), (0.02, 0.03, 0.05), m["steel"])
    g.box((0, 0.33, 0.09), (0.02, 0.03, 0.05), m["steel"])
    g.box((0, -0.22, 0.015), (0.065, 0.40, 0.11), m["teal"], rot=(-0.04, 0, 0))
    g.box((0, -0.15, 0.085), (0.05, 0.16, 0.03), m["black"])
    sbox(g, 0.034, -0.22, 0.02, (0.006, 0.30, 0.02), m["cyan"])
    g.box((0, -0.42, -0.005), (0.07, 0.03, 0.14), m["black"])
    g.box((0, -0.06, -0.08), (0.045, 0.065, 0.14), m["black"], rot=(0.25, 0, 0))
    g.box((0, 0.22, -0.10), (0.045, 0.08, 0.10), m["black"])
    sbox(g, 0.03, 0.78, -0.03, (0.01, 0.22, 0.01), m["steel"], rot=(0, 0, 0.5))
    _trigger_guard(g, m)
    export("sniper_mythic", [g.build(), empty("Muzzle", (0, 1.38, 0.035))])


# ------------------------------------------------------------- weapons & items



def make_bandage():
    white = material("bandage_white", (0.95, 0.95, 0.92))
    red = material("bandage_red", (0.85, 0.15, 0.15))
    cream = material("bandage_cream", (0.88, 0.86, 0.78))
    b = Part("Bandage")
    b.cone((0, 0, 0.12), 0.16, 0.16, 0.24, white, segments=12)
    b.cone((0, 0, 0.245), 0.10, 0.10, 0.02, cream, segments=12)                  # rolled-up top
    b.cone((0, 0, 0.255), 0.05, 0.05, 0.02, white, segments=10)
    for sgn in (-1, 1):                                                          # red cross label, both faces
        b.box((0, sgn * 0.155, 0.12), (0.10, 0.012, 0.03), red)
        b.box((0, sgn * 0.155, 0.12), (0.03, 0.012, 0.10), red)
    export("bandage", [b.build()])


def make_medkit():
    white = material("medkit_white", (0.95, 0.95, 0.95))
    red = material("medkit_red", (0.85, 0.12, 0.12))
    grey = material("medkit_grey", (0.4, 0.4, 0.42))
    m = Part("Medkit")
    m.box((0, 0, 0.15), (0.42, 0.18, 0.30), white)
    m.box((0, 0, 0.19), (0.43, 0.185, 0.02), grey)                               # lid seam
    for sgn in (-1, 1):                                                          # cross on both faces
        m.box((0, sgn * 0.095, 0.15), (0.14, 0.02, 0.05), red)
        m.box((0, sgn * 0.095, 0.15), (0.05, 0.02, 0.14), red)
    for sx in (-0.13, 0.13):                                                     # latches (mirrored)
        for sgn in (-1, 1):
            m.box((sx, sgn * 0.097, 0.19), (0.05, 0.02, 0.06), grey)
    m.box((0, 0, 0.345), (0.20, 0.03, 0.03), red)                                # carry handle
    for sx in (-0.10, 0.10):
        m.box((sx, 0, 0.32), (0.03, 0.03, 0.05), red)
    export("medkit", [m.build()])


def make_potion(name, color, size):
    glass = material(name + "_liquid", color, rough=0.15, emit=color, emit_strength=0.25)
    cork = material(name + "_cork", (0.45, 0.30, 0.15))
    p = Part(name)
    p.cone((0, 0, 0.18 * size), 0.17 * size, 0.17 * size, 0.30 * size, glass, segments=10)
    p.cone((0, 0, 0.38 * size), 0.07 * size, 0.07 * size, 0.14 * size, glass, segments=8)
    p.cone((0, 0, 0.48 * size), 0.075 * size, 0.075 * size, 0.06 * size, cork, segments=8)
    export(name, [p.build()])


def make_grenade():
    olive = material("gren_olive", (0.22, 0.30, 0.14), rough=0.6)
    steel = material("gren_steel", (0.55, 0.57, 0.60), rough=0.3)
    ring = material("gren_ring", (0.85, 0.7, 0.2), rough=0.3)
    g = Part("Grenade")
    g.blob((0, 0, 0.12), 0.11, olive, squash=1.2, jitter=0.0)                    # faceted body
    g.cone((0, 0, 0.255), 0.04, 0.04, 0.05, steel, segments=8)                   # fuse cap
    g.box((0.03, 0, 0.285), (0.075, 0.014, 0.012), steel)                        # spoon lever
    g.box((0.07, 0, 0.215), (0.012, 0.014, 0.14), steel, rot=(0.0, 0.25, 0.0))
    g.cone((-0.035, 0, 0.29), 0.022, 0.022, 0.012, ring, segments=10, axis="Y")  # pull ring
    export("grenade", [g.build()])


def make_gold_bars():
    gold = material("gold_bar", (0.95, 0.74, 0.16), rough=0.22, emit=(0.9, 0.55, 0.05), emit_strength=0.25)
    dark = material("gold_bar_edge", (0.75, 0.55, 0.08), rough=0.3)
    g = Part("GoldBars")
    for x in (-0.19, 0.19):                                                       # two bars below, one across the top
        g.box((x, 0, 0.07), (0.34, 0.22, 0.14), gold)
        g.box((x, 0, 0.145), (0.28, 0.16, 0.02), dark)
    g.box((0, 0, 0.21), (0.38, 0.22, 0.14), gold)
    g.box((0, 0, 0.285), (0.32, 0.16, 0.02), dark)
    export("gold_bars", [g.build()])


def make_vending():
    body = material("vm_body", (0.20, 0.22, 0.27), rough=0.5)
    steel = material("vm_steel", (0.55, 0.57, 0.62), rough=0.3)
    glass = material("vm_glass", (0.55, 0.85, 1.0), rough=0.1, emit=(0.35, 0.7, 1.0), emit_strength=0.9)
    dark = material("vm_dark", (0.05, 0.05, 0.07), rough=0.6)
    accent = material("accent", (0.60, 0.60, 0.65), rough=0.35)
    v = Part("VendingMachine")
    v.box((0, 0, 0.06), (1.0, 0.86, 0.12), dark)                                  # base plinth
    v.box((0, 0, 1.06), (0.94, 0.80, 1.88), body)                                 # cabinet
    v.box((0, 0.405, 1.30), (0.74, 0.03, 1.16), glass)                            # lit display window (front = +Y here, +Z in game)
    for i in range(3):                                                            # shelves with products
        z = 0.90 + i * 0.38
        v.box((0, 0.395, z), (0.78, 0.06, 0.03), steel)
        for j in range(3):
            v.box((-0.24 + j * 0.24, 0.37, z + 0.11), (0.14, 0.08, 0.16), accent)
    v.box((0, 0.405, 0.40), (0.62, 0.05, 0.26), dark)                             # dispensing flap
    v.box((0, 0.43, 0.40), (0.56, 0.02, 0.20), steel)
    v.box((0.30, 0.41, 0.62), (0.16, 0.04, 0.12), steel)                          # coin slot panel
    v.box((0.30, 0.435, 0.62), (0.08, 0.02, 0.02), dark)
    v.box((0, 0.0, 2.10), (0.98, 0.84, 0.30), accent)                             # top sign
    v.box((0, 0.425, 2.10), (0.80, 0.02, 0.16), glass)
    for sx in (-0.47, 0.47):                                                      # side trim
        v.box((sx, 0, 1.06), (0.03, 0.82, 1.9), steel)
    export("vending_machine", [v.build()])


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

def make_highrise(name, floors, width, depth, wall_color, trim_color, band_color):
    """A walkable tower block: a lobby with a door, floors joined by straight stairs along alternating sides, windows on
    every level, a flat roof with a parapet. Front (door) wall is -Y (game +Z), stairs climb towards the front."""
    FH = 3.4          # floor to floor
    SL = 0.25         # slab thickness
    wall = material(name + "_wall", wall_color)
    trim = material(name + "_trim", trim_color)
    band = material(name + "_band", band_color)
    floor = material(name + "_floor", (0.50, 0.50, 0.53))
    hw, hd = width / 2, depth / 2
    b = Part(name)
    b.box((0, 0, 0.08), (width + 0.5, depth + 0.5, 0.16), trim)
    windows = [-width / 2 + 2.2 + i * 2.6 for i in range(int((width - 3.0) // 2.6) + 1)]
    steps = 17
    rise = FH / steps
    run = 0.3
    stair_w = 1.9
    for k in range(floors):
        z0 = k * FH + 0.16 if k == 0 else k * FH
        height = FH - (SL if k > 0 else 0.0) - (0.16 if k == 0 else 0.0)
        if k == 0:
            walls(b, wall, hw, hd, height, 0.3, 0.0, windows, 2.4, 2.8, (1.0, 2.4), 1.4, base_z=0.16)
        else:
            walls(b, wall, hw, hd, height, 0.3, 0.0, windows, 1.8, 2.3, (0.9, 2.4), 1.4, base_z=z0)
        # horizontal band at each floor line
        zb = (k + 1) * FH - 0.2
        b.box_span(-hw - 0.2, hw + 0.2, -hd - 0.2, -hd + 0.05, zb, zb + 0.2, band)
        b.box_span(-hw - 0.2, hw + 0.2, hd - 0.05, hd + 0.2, zb, zb + 0.2, band)
        b.box_span(-hw - 0.2, -hw + 0.05, -hd, hd, zb, zb + 0.2, band)
        b.box_span(hw - 0.05, hw + 0.2, -hd, hd, zb, zb + 0.2, band)
        for sx in (-1, 1):
            for sy in (-1, 1):
                b.box((sx * hw, sy * hd, k * FH + FH / 2), (0.5, 0.5, FH), trim)
    # slabs (with a stairwell cut-out) for every upper level and the roof
    for k in range(1, floors + 1):
        top = k * FH
        side = -1 if k % 2 == 1 else 1
        xs = side * (hw - 0.35 - stair_w / 2)        # stair centre x
        xa, xb = xs - stair_w / 2, xs + stair_w / 2
        yb = hd - 0.3                                # the stairs start at the back wall ...
        ya = yb - steps * run                        # ... and climb towards the front
        b.box_span(-hw, xa, -hd, hd, top - SL, top, floor)
        b.box_span(xb, hw, -hd, hd, top - SL, top, floor)
        b.box_span(xa, xb, -hd, ya, top - SL, top, floor)
        b.box_span(xa, xb, yb, hd, top - SL, top, floor)
        # the stairs from level k-1 up to level k
        base = (k - 1) * FH + (0.16 if k == 1 else 0.0)
        b.wedge(xa, xb, yb, ya, base, top - 0.02, floor)
    # roof parapet and a little rooftop plant room
    rt = floors * FH
    for sx in (-1, 1):
        b.box_span(sx * hw - 0.15, sx * hw + 0.15, -hd, hd, rt, rt + 1.1, trim)
    for sy in (-1, 1):
        b.box_span(-hw, hw, sy * hd - 0.15, sy * hd + 0.15, rt, rt + 1.1, trim)
    b.box((hw * 0.45, hd * 0.2, rt + 1.2), (3.0, 3.0, 2.4), wall)
    b.box((hw * 0.45, hd * 0.2, rt + 2.5), (3.4, 3.4, 0.2), trim)
    b.box((-hw * 0.4, -hd * 0.3, rt + 3.0), (0.15, 0.15, 6.0), trim)           # antenna
    export(name, [b.build()])


def make_highrises():
    make_highrise("highrise_a", 6, 12.0, 11.0, (0.80, 0.78, 0.72), (0.35, 0.36, 0.40), (0.20, 0.45, 0.65))
    reset_scene()
    make_highrise("highrise_b", 9, 12.0, 12.0, (0.55, 0.62, 0.72), (0.22, 0.25, 0.32), (0.85, 0.65, 0.20))
    reset_scene()
    make_highrise("highrise_c", 12, 13.0, 13.0, (0.72, 0.52, 0.45), (0.28, 0.22, 0.20), (0.75, 0.25, 0.20))


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


# ------------------------------------------------------------- vehicles
# Origin = ground level under the middle of the vehicle, forward = +Y (Godot -Z).
# Wheels are separate objects centred on the axle so the game can spin/steer them.


def _wheel(name, x, y, z, radius, width, tire, hub):
    w = Part(name, origin=(x, y, z))
    w.cone((x, y, z), radius, radius, width, tire, segments=14, axis="X")
    w.cone((x + (width / 2 + 0.01) * (1 if x > 0 else -1), y, z), radius * 0.55, radius * 0.55, 0.04, hub, segments=10, axis="X")
    for k in range(4):                                          # lug marks so the spin is visible
        a = k * math.pi / 2
        w.box((x + (width / 2 + 0.03) * (1 if x > 0 else -1), y + math.cos(a) * radius * 0.35, z + math.sin(a) * radius * 0.35),
              (0.03, 0.06, 0.06), tire)
    return w.build()


def make_buggy():
    accent = material("accent", (0.9, 0.35, 0.1), rough=0.5)
    dark = material("bg_dark", (0.12, 0.12, 0.14), rough=0.6)
    steel = material("bg_steel", (0.55, 0.57, 0.6), rough=0.35)
    seat = material("bg_seat", (0.15, 0.17, 0.22))
    tire = material("bg_tire", (0.07, 0.07, 0.08), rough=0.9)
    hub = material("bg_hub", (0.7, 0.72, 0.75), rough=0.3)
    lamp = material("bg_lamp", (1.0, 0.95, 0.7), emit=(1.0, 0.9, 0.5), emit_strength=1.5)
    b = Part("Body")
    b.box((0, 0, 0.62), (1.5, 3.1, 0.22), dark)                       # chassis plate
    b.box((0, -0.15, 0.85), (1.7, 2.2, 0.34), accent)                 # tub
    b.box((0, 1.25, 0.82), (1.5, 0.95, 0.30), accent)                 # hood
    b.box((0, 1.78, 0.68), (1.75, 0.14, 0.22), steel)                 # front bumper
    b.box((0, -1.78, 0.68), (1.7, 0.14, 0.22), steel)                 # rear bumper
    b.box((0, -1.5, 0.98), (1.1, 0.55, 0.55), dark)                   # engine
    for ex in (-0.3, 0.3):
        b.cone((ex, -1.85, 1.0), 0.05, 0.05, 0.4, steel, segments=6, axis="Y")   # exhausts
    for sx in (-1, 1):                                                  # roll cage
        b.box((sx * 0.78, 0.45, 1.3), (0.07, 0.07, 1.0), steel)
        b.box((sx * 0.78, -1.05, 1.3), (0.07, 0.07, 1.0), steel)
        b.box((sx * 0.78, -0.3, 1.8), (0.07, 1.5, 0.07), steel)
    b.box((0, 0.45, 1.8), (1.6, 0.07, 0.07), steel)
    b.box((0, -1.05, 1.8), (1.6, 0.07, 0.07), steel)
    for sx in (-0.4, 0.4):                                              # seats
        b.box((sx, -0.35, 1.0), (0.5, 0.55, 0.12), seat)
        b.box((sx, -0.65, 1.3), (0.5, 0.12, 0.55), seat)
    b.box((-0.4, 0.3, 1.2), (0.4, 0.05, 0.4), dark, rot=(0.9, 0, 0))   # steering wheel
    for sx in (-0.55, 0.55):
        b.box((sx, 1.75, 0.85), (0.28, 0.06, 0.2), lamp)
    objs = [b.build()]
    for name, x, y in (("WheelFL", -0.95, 1.15), ("WheelFR", 0.95, 1.15), ("WheelRL", -0.95, -1.15), ("WheelRR", 0.95, -1.15)):
        objs.append(_wheel(name, x, y, 0.45, 0.45, 0.4, tire, hub))
    export("buggy", objs)


def make_quad():
    accent = material("accent", (0.15, 0.55, 0.85), rough=0.5)
    dark = material("qd_dark", (0.12, 0.12, 0.14), rough=0.6)
    steel = material("qd_steel", (0.55, 0.57, 0.6), rough=0.35)
    seat = material("qd_seat", (0.1, 0.1, 0.12))
    tire = material("qd_tire", (0.07, 0.07, 0.08), rough=0.9)
    hub = material("qd_hub", (0.7, 0.72, 0.75), rough=0.3)
    lamp = material("qd_lamp", (1.0, 0.95, 0.7), emit=(1.0, 0.9, 0.5), emit_strength=1.5)
    b = Part("Body")
    b.box((0, 0, 0.62), (0.75, 1.5, 0.22), dark)
    b.box((0, 0.35, 0.82), (0.8, 0.8, 0.3), accent)                   # tank / front body
    b.box((0, -0.45, 0.86), (0.55, 0.85, 0.12), seat)                  # seat
    b.box((0, -0.82, 0.7), (0.6, 0.35, 0.3), dark)                     # rear
    b.box((0, 0.5, 1.15), (0.08, 0.08, 0.5), steel, rot=(0.4, 0, 0))   # steering column
    b.box((0, 0.7, 1.35), (1.0, 0.07, 0.07), steel)                    # handlebars
    b.box((0, 0.85, 0.95), (0.3, 0.08, 0.18), lamp)
    for sx in (-1, 1):
        b.box((sx * 0.6, 0.7, 0.62), (0.08, 0.5, 0.06), steel)         # front guards
        b.box((sx * 0.6, -0.7, 0.62), (0.08, 0.5, 0.06), steel)
    objs = [b.build()]
    for name, x, y in (("WheelFL", -0.62, 0.7), ("WheelFR", 0.62, 0.7), ("WheelRL", -0.62, -0.7), ("WheelRR", 0.62, -0.7)):
        objs.append(_wheel(name, x, y, 0.38, 0.38, 0.32, tire, hub))
    export("quad", objs)


def make_boat():
    accent = material("accent", (0.9, 0.9, 0.92), rough=0.4)
    hull = material("bt_hull", (0.15, 0.3, 0.55), rough=0.45)
    dark = material("bt_dark", (0.12, 0.12, 0.14))
    seat = material("bt_seat", (0.85, 0.82, 0.75))
    glass = material("bt_glass", (0.7, 0.88, 1.0), rough=0.1)
    steel = material("bt_steel", (0.55, 0.57, 0.6), rough=0.35)
    b = Part("Body")
    b.box((0, -0.2, 0.25), (1.7, 3.2, 0.5), hull)                      # hull block
    b.box((0, 1.95, 0.25), (1.5, 1.0, 0.5), hull, rot=(0, 0, 0.0))
    for sx in (-1, 1):                                                  # pointed bow from two wedges
        b.box((sx * 0.38, 2.15, 0.28), (0.9, 1.3, 0.46), hull, rot_z=-sx * 0.45)
    b.box((0, -0.2, 0.52), (1.5, 3.0, 0.08), accent)                   # deck
    b.box((0, 0.35, 0.95), (1.0, 0.5, 0.6), accent)                    # console
    b.box((0, 0.7, 1.3), (1.0, 0.06, 0.45), glass, rot=(0.7, 0, 0))    # windshield
    for sx in (-0.4, 0.4):
        b.box((sx, -0.55, 0.85), (0.5, 0.5, 0.3), seat)
        b.box((sx, -0.85, 1.1), (0.5, 0.1, 0.45), seat)
    b.box((0, -1.9, 0.75), (0.35, 0.3, 0.7), dark)                     # outboard motor
    b.box((0, -2.0, 0.2), (0.1, 0.5, 0.8), steel)
    b.box((0, -2.0, 0.0), (0.7, 0.06, 0.12), steel)                    # propeller blade
    export("boat", [b.build()])


def main():
    if os.environ.get("ONLY") == "highrise":      # ONLY=highrise blender -b -P tools/blender/generate_assets.py
        reset_scene()
        make_highrises()
        return
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
    for fn in (make_pistol, make_smg, make_shotgun, make_sniper, make_pickaxe, make_pistol_mythic, make_smg_mythic,
               make_assault_mythic, make_shotgun_mythic, make_sniper_mythic, make_bandage, make_medkit,
               make_ammo_pickup, make_chest, make_ammo_box, make_supply, make_bus, make_glider):
        reset_scene()
        fn()
    reset_scene()
    make_highrises()
    for fn in (make_poi_buildings, make_container, make_silo, make_windmill, make_lighthouse, make_watchtower, make_crane,
               make_chimney, make_tank, make_haystack, make_fence, make_sandbags, make_radar, make_vault):
        reset_scene()
        fn()
    for fn in (make_buggy, make_quad, make_boat):
        reset_scene()
        fn()
    reset_scene()
    make_potion("mini_shield", (0.25, 0.55, 1.0), 0.8)
    reset_scene()
    make_potion("shield_potion", (0.20, 0.45, 1.0), 1.25)
    reset_scene()
    make_potion("slurp_juice", (0.20, 0.90, 0.85), 0.95)
    reset_scene()
    make_potion("chug_jug", (0.55, 0.80, 1.0), 1.5)
    reset_scene()
    make_grenade()
    reset_scene()
    make_gold_bars()
    reset_scene()
    make_vending()


if __name__ == "__main__":
    main()
