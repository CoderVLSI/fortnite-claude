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


def material(name, color, rough=0.85, emit=None):
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
        bsdf.inputs["Emission Strength"].default_value = 1.5
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

    def box(self, center, size, mat, rot_z=0.0):
        verts = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        m = (
            Matrix.Translation(Vector(center) - self.origin)
            @ Matrix.Rotation(rot_z, 4, "Z")
            @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        )
        bmesh.ops.transform(self.bm, matrix=m, verts=verts)
        self._tag(verts, mat)

    def box_span(self, x0, x1, y0, y1, z0, z1, mat):
        """Axis-aligned box from min/max coordinates (skips empty spans)."""
        if x1 - x0 < 1e-4 or y1 - y0 < 1e-4 or z1 - z0 < 1e-4:
            return
        self.box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), mat)

    def cone(self, center, r_bottom, r_top, depth, mat, segments=8, scale_xy=(1.0, 1.0), rot_z=0.0):
        kwargs = dict(cap_ends=True, cap_tris=False, segments=segments, depth=depth)
        try:
            ret = bmesh.ops.create_cone(self.bm, radius1=r_bottom, radius2=r_top, **kwargs)
        except TypeError:  # older API names
            ret = bmesh.ops.create_cone(self.bm, diameter1=r_bottom, diameter2=r_top, **kwargs)
        verts = ret["verts"]
        m = (
            Matrix.Translation(Vector(center) - self.origin)
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


def make_player():
    skin = material("skin", (0.80, 0.52, 0.36))
    vest = material("vest", (0.30, 0.42, 0.22))
    pants = material("pants", (0.32, 0.22, 0.14))
    boots = material("boots", (0.10, 0.09, 0.08))
    hair = material("hair", (0.07, 0.05, 0.04))
    objs = []

    torso = Part("Torso")
    torso.box((0, 0, 1.18), (0.50, 0.28, 0.62), vest)
    torso.box((0, 0.0, 0.84), (0.46, 0.26, 0.10), pants)  # belt/hips
    objs.append(torso.build())

    head = Part("Head", origin=(0, 0, 1.50))
    head.box((0, 0, 1.64), (0.26, 0.26, 0.28), skin)
    head.box((0, -0.01, 1.80), (0.29, 0.29, 0.09), hair)
    head.box((0, 0.15, 1.77), (0.29, 0.10, 0.04), hair)  # cap brim, faces forward
    objs.append(head.build())

    for side, sx in (("L", -1), ("R", 1)):
        hip = (sx * 0.13, 0, 0.88)
        leg = Part("Leg" + side, origin=hip)
        leg.box((sx * 0.13, 0, 0.46), (0.21, 0.23, 0.86), pants)
        leg.box((sx * 0.13, 0.03, 0.06), (0.23, 0.31, 0.12), boots)
        objs.append(leg.build())

        shoulder = (sx * 0.36, 0, 1.45)
        arm = Part("Arm" + side, origin=shoulder)
        arm.box((sx * 0.36, 0, 1.20), (0.15, 0.17, 0.50), vest)
        arm.box((sx * 0.36, 0, 0.93), (0.13, 0.15, 0.14), skin)
        objs.append(arm.build())
    export("player", objs)


def make_rifle():
    dark = material("gun_dark", (0.12, 0.12, 0.14), rough=0.4)
    wood = material("gun_wood", (0.35, 0.20, 0.10))
    steel = material("gun_steel", (0.30, 0.31, 0.34), rough=0.35)
    gun = Part("Rifle")
    gun.box((0, 0.30, 0), (0.07, 0.62, 0.11), dark)
    gun.box((0, 0.78, 0.02), (0.04, 0.36, 0.04), steel)
    gun.box((0, -0.12, -0.03), (0.06, 0.26, 0.13), wood)
    gun.box((0, 0.28, -0.15), (0.05, 0.10, 0.20), dark)
    gun.box((0, 0.38, 0.08), (0.04, 0.22, 0.045), steel)
    muzzle = empty("Muzzle", (0, 0.97, 0.02))
    export("rifle", [gun.build(), muzzle])


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


def walls(part, mat, hw, hd, height, thick, door_x, windows):
    """Four walls of a rectangular building; door on the -Y (front) wall."""
    holes_front = [(door_x - 0.65, door_x + 0.65, 0.0, 2.25)]
    holes_back = [(wx - 0.7, wx + 0.7, 1.0, 2.2) for wx in windows]
    holes_side = [(-0.7, 0.7, 1.0, 2.2)]

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


def make_house(name, width, depth, height, wall_color, roof_color, trim_color, roof_h, windows):
    wall = material(name + "_wall", wall_color)
    roof = material(name + "_roof", roof_color, rough=0.7)
    trim = material(name + "_trim", trim_color)
    floor = material(name + "_floor", (0.45, 0.33, 0.22))
    hw, hd = width / 2, depth / 2
    house = Part(name)
    house.box((0, 0, 0.06), (width + 0.3, depth + 0.3, 0.12), trim)  # plinth / porch
    house.box((0, 0, 0.13), (width - 0.4, depth - 0.4, 0.04), floor)
    walls(house, wall, hw, hd, height, 0.25, 0.0, windows)
    # corner posts
    for sx in (-1, 1):
        for sy in (-1, 1):
            house.box((sx * hw, sy * hd, height / 2), (0.32, 0.32, height), trim)
    # ceiling slab under the roof so the interior is enclosed
    house.box((0, 0, height + 0.05), (width, depth, 0.12), trim)
    # hipped roof: a 4-sided cone rotated onto the wall axes, stretched to the footprint
    ov = 0.7
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


def main():
    reset_scene()
    make_player()
    reset_scene()
    make_rifle()
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


if __name__ == "__main__":
    main()
