# Blender (headless) normaliser for HD models:
#   blender -b -P tools/hd/normalize.py -- <source.gltf|glb> <reference.glb> <out.glb> [--tris N] [--tex PX] [--fit longest|volume]
# It rotates the Sketchfab model by whichever of the 24 axis-aligned orientations best matches the reference (the pixel-mode model with the
# same name) in size and in how its bulk is spread along each axis, scales it to the reference's size, centres it on the reference's centre,
# decimates it to a triangle budget, shrinks the textures and writes a .glb (PNG textures: this Godot build has no JPG importer).
import bpy, sys, os, math, itertools
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
src, ref, out = argv[0], argv[1], argv[2]
opts = {"tris": 12000, "tex": 1024, "fit": "longest", "maps": "color"}
i = 3
while i < len(argv):
    if argv[i] == "--tris": opts["tris"] = int(argv[i + 1]); i += 2
    elif argv[i] == "--tex": opts["tex"] = int(argv[i + 1]); i += 2
    elif argv[i] == "--fit": opts["fit"] = argv[i + 1]; i += 2
    elif argv[i] == "--maps": opts["maps"] = argv[i + 1]; i += 2           # color | color+normal | all
    else: i += 1


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for b in list(bpy.data.meshes) + list(bpy.data.materials) + list(bpy.data.images):
        try:
            (bpy.data.meshes if isinstance(b, bpy.types.Mesh) else bpy.data.materials if isinstance(b, bpy.types.Material) else bpy.data.images).remove(b)
        except Exception:
            pass


def do_import(path):
    if path.lower().endswith((".gltf", ".glb")):
        bpy.ops.import_scene.gltf(filepath=path)
    else:
        raise SystemExit("unsupported " + path)
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def world_points(objs, step=1):
    pts = []
    for o in objs:
        mw = o.matrix_world
        for k, v in enumerate(o.data.vertices):
            if k % step == 0:
                pts.append(mw @ v.co)
    return pts


def bbox(pts, q=0.004):
    # robust box: ignores the outermost 0.4% of vertices per axis (stray bits, floor planes, hidden helper meshes)
    n = len(pts)
    k = int(n * q)
    mn = []
    mx = []
    for a in range(3):
        vals = sorted(p[a] for p in pts)
        mn.append(vals[k])
        mx.append(vals[n - 1 - k])
    return Vector(mn), Vector(mx)


def profile(pts, axis, mn, mx, bins=8):
    span = max(mx[axis] - mn[axis], 1e-6)
    h = [0.0] * bins
    others = [a for a in range(3) if a != axis]
    ext = [[1e9, -1e9] for _ in range(bins)]
    for p in pts:
        b = min(bins - 1, int((p[axis] - mn[axis]) / span * bins))
        for a in others:
            ext[b][0] = min(ext[b][0], p[a]); ext[b][1] = max(ext[b][1], p[a])
    out = []
    for b in range(bins):
        if ext[b][0] > ext[b][1]:
            out.append(0.0)
        else:
            out.append(sum(ext[b][1] - ext[b][0] for _ in [0]) )
    m = max(out) or 1.0
    return [v / m for v in out]


# ---- reference
clear()
ref_objs = do_import(ref)
rpts = world_points(ref_objs)
rmn, rmx = bbox(rpts)
rdim = rmx - rmn
rcen = (rmn + rmx) / 2
rprof = [profile(rpts, a, rmn, rmx) for a in range(3)]
# named helper empties on the pixel model (the weapon "Muzzle"): the HD model gets the same ones at the same places
ref_empties = [(o.name, o.matrix_world.translation.copy()) for o in bpy.context.scene.objects if o.type == "EMPTY" and o.name in ("Muzzle", "Grip", "Scope")]

# ---- source
clear()
objs = do_import(src)
# skinned models (an armature with the mesh bound to it): bake the pose into the mesh and drop the rig, otherwise the exported skin keeps
# the original bone scales and the model comes out huge or distorted
for o in list(objs):
    if o.data.users > 1:
        o.data = o.data.copy()
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        if m.type == "ARMATURE":
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception as e:
                print("NORMALIZE armature apply failed:", e)
    o.vertex_groups.clear()
for o in list(bpy.context.scene.objects):
    if o.type == "ARMATURE":
        bpy.data.objects.remove(o, do_unlink=True)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
# join everything into one mesh object (keeps materials)
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
for o in objs:
    o.parent = None
    o.matrix_world = o.matrix_world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
spts = [obj.matrix_world @ v.co for v in obj.data.vertices]

# the 24 proper rotations of the cube
mats = []
for perm in itertools.permutations(range(3)):
    for signs in itertools.product([1, -1], repeat=3):
        m = Matrix([[0, 0, 0], [0, 0, 0], [0, 0, 0]])
        for r in range(3):
            m[r][perm[r]] = signs[r]
        if m.determinant() > 0:
            mats.append(m)
best = None
step = max(1, len(spts) // 4000)
for m in mats:
    pts = [m @ p for p in spts[::step]]
    mn, mx = bbox(pts)
    dim = mx - mn
    scale = {"longest": max(rdim) / max(max(dim), 1e-9), "volume": (rdim.x * rdim.y * rdim.z / max(dim.x * dim.y * dim.z, 1e-12)) ** (1 / 3), "box": (rdim.x * rdim.y * rdim.z / max(dim.x * dim.y * dim.z, 1e-12)) ** (1 / 3)}[opts["fit"]]
    dsc = Vector((dim.x * scale, dim.y * scale, dim.z * scale))
    size_err = sum(abs(dsc[a] - rdim[a]) / max(rdim[a], 1e-6) for a in range(3))
    prof_err = 0.0
    for a in range(3):
        pr = profile(pts, a, mn, mx)
        prof_err += sum(abs(pr[k] - rprof[a][k]) for k in range(len(pr))) / len(pr)
    score = size_err * 2.0 + prof_err
    if best is None or score < best[0]:
        best = (score, m)
m = best[1]
print("NORMALIZE best score %.3f ref dims %s src n=%d" % (best[0], tuple(round(v, 3) for v in rdim), len(spts)))
for v in obj.data.vertices:
    v.co = m @ v.co
obj.data.update()
pts = [v.co.copy() for v in obj.data.vertices]
mn, mx = bbox(pts)
dim = mx - mn
scale = {"longest": max(rdim) / max(max(dim), 1e-9), "volume": (rdim.x * rdim.y * rdim.z / max(dim.x * dim.y * dim.z, 1e-12)) ** (1 / 3), "box": 1.0}[opts["fit"]]
cen = (mn + mx) / 2
axis_scale = Vector((rdim.x / max(dim.x, 1e-9), rdim.y / max(dim.y, 1e-9), rdim.z / max(dim.z, 1e-9))) if opts["fit"] == "box" else Vector((scale, scale, scale))
print("NORMALIZE src dims %s scale %.4f" % (tuple(round(v, 3) for v in dim), scale))
for v in obj.data.vertices:
    d = v.co - cen
    v.co = Vector((d.x * axis_scale.x, d.y * axis_scale.y, d.z * axis_scale.z)) + rcen
obj.data.update()
obj.location = (0, 0, 0)
obj.rotation_euler = (0, 0, 0)
obj.scale = (1, 1, 1)

# ---- decimate
bpy.context.view_layer.objects.active = obj
tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
if tris > opts["tris"]:
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.ratio = opts["tris"] / tris
    bpy.ops.object.modifier_apply(modifier="dec")
    print("NORMALIZE decimated %d -> %d tris" % (tris, sum(len(p.vertices) - 2 for p in obj.data.polygons)))

# ---- legacy specular/glossiness (KHR_materials_pbrSpecularGlossiness) or other custom node groups: rebuild a plain Principled material
# from the best colour image, otherwise the colour texture is lost on export
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    nt = mat.node_tree
    pr = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"]
    if pr and pr[0].inputs["Base Color"].is_linked:
        continue
    imgs = [n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image]
    if not imgs:
        continue
    imgs.sort(key=lambda n: 0 if any(k in n.image.name.lower() for k in ("diffuse", "color", "albedo", "base")) else 1)
    out_node = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
    if out_node is None:
        continue
    bsdf = pr[0] if pr else nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(imgs[0].outputs["Color"], bsdf.inputs["Base Color"])
    if imgs[0].image.alpha_mode != "NONE" and mat.blend_method in ("CLIP", "BLEND", "HASHED"):
        nt.links.new(imgs[0].outputs["Alpha"], bsdf.inputs["Alpha"])
    for l in list(out_node.inputs["Surface"].links):
        nt.links.remove(l)
    nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])

# ---- keep the file small: by default only the colour map survives (metal / roughness become constants, no normal map)
if opts["maps"] != "all":
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type != "BSDF_PRINCIPLED":
                continue
            for name in ("Metallic", "Roughness"):
                for link in list(node.inputs[name].links):
                    mat.node_tree.links.remove(link)
            node.inputs["Metallic"].default_value = 0.25
            node.inputs["Roughness"].default_value = 0.6
            if opts["maps"] == "color":
                for link in list(node.inputs["Normal"].links):
                    mat.node_tree.links.remove(link)
        used = {n.image for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and any(o.is_linked for o in n.outputs)}
        for n in list(mat.node_tree.nodes):
            if n.type == "TEX_IMAGE" and not any(o.is_linked for o in n.outputs):
                mat.node_tree.nodes.remove(n)
    for img in list(bpy.data.images):
        if img.users == 0 or not any(n.image == img for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes if n.type == "TEX_IMAGE"):
            bpy.data.images.remove(img)

# ---- textures
for img in bpy.data.images:
    if img.size[0] > opts["tex"] or img.size[1] > opts["tex"]:
        k = opts["tex"] / max(img.size[0], img.size[1])
        img.scale(max(1, int(img.size[0] * k)), max(1, int(img.size[1] * k)))

for nm, pos in ref_empties:
    e = bpy.data.objects.new(nm, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = pos
    print("NORMALIZE copied empty", nm, tuple(round(v, 3) for v in pos))
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_image_format="AUTO", export_apply=True, export_yup=True)
final_tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
print("NORMALIZE done %s tris=%d size=%.1f KB" % (out, final_tris, os.path.getsize(out) / 1024.0))
