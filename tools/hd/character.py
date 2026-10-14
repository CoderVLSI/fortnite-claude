# Blender (headless): turn a rigged Sketchfab humanoid into an HD character with the SAME joint nodes as the pixel player.glb
# (Hips, HipL/R, KneeL/R, Spine, Head, ShoulderL/R, ElbowL/R, HandL/R) so Animator.gd drives it unchanged. The skinned mesh is baked in
# its imported pose, split into rigid parts by the dominant bone of every face, arms are rotated down (T-pose -> hanging), the character
# is scaled to the pixel player's height and turned to face -Z (Godot).
#   blender -b -P tools/hd/character.py -- <source.gltf> <out.glb> [--height 1.88] [--tex 512] [--tris 12000]
import bpy, sys, os, math, re
from mathutils import Vector, Matrix
import bmesh

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
opts = {"height": 1.88, "tex": 512, "tris": 12000}
i = 2
while i < len(argv):
    k = argv[i].lstrip("-")
    if k in opts:
        opts[k] = type(opts[k])(argv[i + 1]); i += 2
    else:
        i += 1

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
if not meshes or not arms:
    raise SystemExit("CHAR no mesh or no armature")

# ---------------------------------------------------------------- bone info (world space, imported pose)
bones = {}
for a in arms:
    for b in a.data.bones:
        bones[b.name] = (a.matrix_world @ b.head_local, a.matrix_world @ b.tail_local)


def part_of(name):
    n = re.sub(r"[^a-z0-9]", "", name.lower())
    if any(k in n for k in ("head", "neck", "jaw", "eye", "hair", "helmet", "face", "ear", "nose", "brow", "tongue", "teeth")):
        return "Head"
    if any(k in n for k in ("finger", "thumb", "index", "middle", "ring", "pinky", "hand", "palm", "wrist")):
        return "Fore"
    if any(k in n for k in ("forearm", "lowerarm", "elbow", "foreArm".lower())):
        return "Fore"
    if any(k in n for k in ("upperarm", "uparm")) or (("arm" in n) and not any(k in n for k in ("armor", "armour", "forearm"))):
        return "Upper"
    if any(k in n for k in ("thigh", "upleg", "upperleg", "uleg")):
        return "Thigh"
    if any(k in n for k in ("calf", "shin", "lowerleg", "lleg", "knee", "foot", "toe", "ball", "ankle")):
        return "Shin"
    if "leg" in n:
        return "Thigh"
    if any(k in n for k in ("pelvis", "hips", "hip", "root")):
        return "Pelvis"
    return "Torso"


def side_of(name):
    n = name.lower()
    if re.search(r"(^|[._ :-])(l|left)([._ :-]|$)", n) or "left" in n or n.endswith("l") and re.search(r"[._-]l$", n):
        return "L"
    if re.search(r"(^|[._ :-])(r|right)([._ :-]|$)", n) or "right" in n:
        return "R"
    return ""


# ---------------------------------------------------------------- label bones by the skeleton's shape (names are unreliable)
ROLE = {}       # bone name -> part ("Pelvis","Torso","Head","Upper","Fore","Thigh","Shin")
ROLE_BONES = {"thigh": [], "calf": [], "upper": [], "fore": [], "hand": [], "spine": None, "neck": None, "hips": None}
src_mz = min(v.co.z for o in meshes for v in o.data.vertices) if False else None


def label_bones():
    allb = {}
    for a in arms:
        for b in a.data.bones:
            allb[b.name] = (b, a)
    if not allb:
        return False
    # source height from the meshes (world)
    zs_ = []
    for o in meshes:
        mw = o.matrix_world
        nv_ = len(o.data.vertices)
        for vi in range(0, nv_, max(1, nv_ // 3000)):
            zs_.append((mw @ o.data.vertices[vi].co).z)
    zs_.sort()
    Hs = zs_[-1] - zs_[0]

    def head(n):
        b, a = allb[n]
        return a.matrix_world @ b.head_local

    def kids(n):
        return [c.name for c in allb[n][0].children]

    zcache = {}

    def zspan(n):
        if n not in zcache:
            lo = hi = head(n).z
            for c in kids(n):
                if head(c).length < 1e-3:
                    continue                       # junk end bones parked at the origin (some exporters do this)
                a, b = zspan(c)
                lo, hi = min(lo, a), max(hi, b)
            zcache[n] = (lo, hi)
        return zcache[n]

    def goes_down(c, n):
        return zspan(c)[0] < head(n).z - 0.25 * Hs and abs(head(c).x - head(n).x) > 0.01 * Hs

    # hips: a bone with >= 2 children whose branches reach far below it, on opposite sides
    hips = None
    for n in allb:
        down = [c for c in kids(n) if goes_down(c, n)]
        xs = [head(c).x for c in down]
        if len(down) >= 2 and min(xs) < 0 < max(xs):
            if hips is None or head(n).z > head(hips).z:
                hips = n
    if hips is None:
        return False
    ROLE[hips] = "Pelvis"
    ROLE_BONES["hips"] = hips

    def mark_desc(n, part):
        ROLE[n] = part
        for c in kids(n):
            mark_desc(c, part)

    for c in kids(hips):
        v = head(c) - head(hips)
        if goes_down(c, hips):                                  # a leg: thigh bone, then calf bone, then foot
            ROLE[c] = "Thigh"
            ROLE_BONES["thigh"].append(c)
            ks = [k for k in kids(c) if (head(k) - head(c)).z < 0]
            if ks:
                calf = ks[0]
                ROLE_BONES["calf"].append(calf)
                mark_desc(calf, "Shin")
            for k in kids(c):
                if k not in ks:
                    mark_desc(k, "Thigh")
        elif zspan(c)[1] > head(hips).z + 0.15 * Hs:           # the spine
            chain = []
            cur = c
            while True:
                chain.append(cur)
                ROLE[cur] = "Torso"
                ups = kids(cur)
                lateral = [k for k in ups if abs((head(k) - head(cur)).x) > 0.04 * Hs]
                if len(lateral) >= 2 or not ups:
                    break
                cur = max(ups, key=lambda k: (head(k) - head(cur)).z)
            ROLE_BONES["spine"] = chain[0]
            chest = chain[-1]
            for k in kids(chest):
                dv = head(k) - head(chest)
                if abs(dv.x) > 0.04 * Hs:                       # an arm chain (clavicle? upper arm, forearm, hand ...)
                    ch = [k]
                    cur2 = k
                    while kids(cur2):
                        nxt = max(kids(cur2), key=lambda q: abs(head(q).x))
                        ch.append(nxt)
                        cur2 = nxt
                    # clavicle present when the first bone starts close to the body axis and the chain is long
                    if abs(head(ch[0]).x) < 0.07 * Hs and len(ch) >= 4:
                        ROLE[ch[0]] = "Torso"
                        ch = ch[1:]
                    ROLE_BONES["upper"].append(ch[0])
                    if len(ch) > 1:
                        ROLE_BONES["fore"].append(ch[1])
                    if len(ch) > 2:
                        ROLE_BONES["hand"].append(ch[2])
                    ROLE[ch[0]] = "Upper"
                    for q in ch[1:]:
                        mark_desc(q, "Fore")
                    # sibling branches (fingers hang off the wrist; the chain only followed one)
                    for q in ch:
                        for sib in kids(q):
                            if sib not in ROLE:
                                mark_desc(sib, ROLE[q] if q in ROLE else "Fore")
                elif dv.z > 0 or True:                           # neck / head
                    ROLE_BONES["neck"] = ROLE_BONES["neck"] or k
                    mark_desc(k, "Head")
        else:
            ROLE[c] = "Torso"
    # everything else inherits from its parent
    for n in allb:
        if n not in ROLE:
            par = allb[n][0].parent
            while par is not None and par.name not in ROLE:
                par = par.parent
            ROLE[n] = ROLE[par.name] if par is not None else "Torso"
    return True


have_roles = label_bones()
print("CHAR skeleton labelled:", have_roles, {k: (v if not isinstance(v, list) else len(v)) for k, v in ROLE_BONES.items()})

# ---------------------------------------------------------------- bake the pose, remember each vertex's dominant bone
for o in meshes:
    if o.data.users > 1:
        o.data = o.data.copy()
vparts = {}          # (object name, vertex index) -> (part, side-by-name)
for o in meshes:
    names = {g.index: g.name for g in o.vertex_groups}
    for v in o.data.vertices:
        best = None
        for g in v.groups:
            if best is None or g.weight > best.weight:
                best = g
        if best is None:
            vparts[(o.name, v.index)] = ("Torso", "")
        else:
            nm = names.get(best.group, "")
            vparts[(o.name, v.index)] = ((ROLE.get(nm) if have_roles and nm in ROLE else part_of(nm)), side_of(nm))
for o in meshes:
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        if m.type == "ARMATURE":
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception as e:
                print("CHAR armature apply failed", e)

# ---------------------------------------------------------------- one combined bmesh in world space
mats = []
for o in meshes:
    for m in o.data.materials:
        if m is not None and m not in mats:
            mats.append(m)
print("CHAR materials", len(mats), [m.name for m in mats])
bm = bmesh.new()
uv_lay = bm.loops.layers.uv.new("UVMap")
face_part = []
for o in meshes:
    me = o.data
    mw = o.matrix_world
    mapping = {}
    for v in me.vertices:
        nv = bm.verts.new(mw @ v.co)
        mapping[v.index] = nv
    bm.verts.ensure_lookup_table()
    for p in me.polygons:
        try:
            f = bm.faces.new([mapping[k] for k in p.vertices])
        except ValueError:
            continue
        uvl = me.uv_layers.active
        if uvl is not None:
            for li, loop in enumerate(f.loops):
                loop[uv_lay].uv = uvl.data[p.loop_indices[li]].uv
        try:
            f.material_index = mats.index(o.data.materials[p.material_index])
        except (IndexError, ValueError):
            f.material_index = 0
        f.smooth = p.use_smooth
        # majority part of the face
        votes = {}
        for k in p.vertices:
            pp = vparts.get((o.name, k), ("Torso", ""))[0]
            votes[pp] = votes.get(pp, 0) + 1
        face_part.append((f, max(votes, key=votes.get)))
for o in list(meshes):
    pass

allv = [v.co.copy() for v in bm.verts]
zs = sorted(v.z for v in allv)
k = int(len(zs) * 0.003)
zmin, zmax = zs[k], zs[-1 - k]
H = zmax - zmin
scale = opts["height"] / H
print("CHAR source height %.3f -> scale %.4f" % (H, scale))

# ---------------------------------------------------------------- joints from the bones (fallback: proportions)
def bone_head(pred, side=None):
    best = None
    for name, (h, t) in bones.items():
        if pred(re.sub(r"[^a-z0-9]", "", name.lower())):
            s = side_of(name)
            if side is not None and s and s != side:
                continue
            if side is not None and not s:
                # decide by geometry: character left = -x in our rig (after orientation); keep both and choose below
                pass
            cand = (name, h, t)
            if best is None:
                best = []
            best.append(cand)
    return best or []


def pick(pred, want_sign=None, prefer_low=False):
    cands = bone_head(pred)
    if not cands:
        return None
    if want_sign is not None:
        c2 = [c for c in cands if (c[1].x * want_sign) > 0.01 * H]
        if c2:
            cands = c2
    cands.sort(key=lambda c: c[1].z, reverse=not prefer_low)
    return cands[0]


# which way is the character facing? use the feet: the toe end of the Shin part vs the ankle
feet = [v for v in bm.verts if v.co.z < zmin + 0.06 * H]
leg = [v for v in bm.verts if zmin + 0.12 * H < v.co.z < zmin + 0.3 * H]
if feet and leg:
    ly = sum(v.co.y for v in leg) / len(leg)
    fmax = max(v.co.y for v in feet) - ly
    fmin = ly - min(v.co.y for v in feet)
    ratio = (fmax - fmin) / max(fmax + fmin, 1e-6)
    # glTF characters normally face +Z, which Blender imports as -Y; only a clear toe cue says otherwise
    facing = 1.0 if ratio > 0.2 else -1.0       # +1 = already faces +Y (Godot -Z), -1 = turn it round
    print("CHAR feet extents front %.3f back %.3f" % (fmax, fmin))
else:
    facing = 1.0
print("CHAR facing", facing)
# rotate everything about Z by 180 degrees if it faces -Y
rot = Matrix.Rotation(math.pi if facing < 0 else 0.0, 3, "Z")
cx = sum(v.x for v in allv) / len(allv)
cy = sum(v.y for v in allv) / len(allv)


def xf(p):
    q = rot @ Vector((p.x - cx, p.y - cy, p.z - zmin))
    return q * scale


for v in bm.verts:
    v.co = xf(v.co)
bones_x = {n: (xf(h), xf(t)) for n, (h, t) in bones.items()}

# left = -x
def lr_of(name_side, p):
    return "L" if p.x < 0 else "R"

H2 = opts["height"]
prop = {"hips": 0.93, "hip": 0.13, "knee": 0.45, "spine": 0.10, "head": 0.50, "shx": 0.34, "shy": 0.44, "elbow": 0.32, "hand": 0.31}
def find_bone(pred, sign=None, low=False):
    cands = []
    for name, (h, t) in bones_x.items():
        if pred(re.sub(r"[^a-z0-9]", "", name.lower())):
            cands.append((name, h, t))
    if sign is not None:
        c2 = [c for c in cands if c[1].x * sign > 0.02]
        if c2:
            cands = c2
        else:
            c2 = [c for c in cands if side_of(c[0]) == ("L" if sign < 0 else "R")]
            if c2:
                cands = c2
    if not cands:
        return None
    cands.sort(key=lambda c: c[1].z, reverse=not low)
    return cands[0]


hips_b = find_bone(lambda n: "hips" in n or "pelvis" in n, low=False)


def role_bone(name):
    return (name, bones_x[name][0], bones_x[name][1]) if name in bones_x else None


def role_pick(names, sign):
    cands = [n for n in names if n in bones_x and bones_x[n][0].x * sign > 0.0]
    return role_bone(cands[0]) if cands else None


if have_roles:
    hips_b = role_bone(ROLE_BONES["hips"])
hips_pos = hips_b[1] if hips_b else Vector((0, 0, 0.93 * H2 / 1.88))
if hips_b and hips_pos.z < 0.2 * H2:
    hips_pos = Vector((0, 0, 0.5 * H2))
hips_pos = Vector((0, hips_pos.y * 0.0, hips_pos.z))        # centred on the body axis
thigh = {s: find_bone(lambda n: any(k in n for k in ("thigh", "upleg", "upperleg")), sign=s) for s in (-1, 1)}
calf = {s: find_bone(lambda n: any(k in n for k in ("calf", "shin", "lowerleg")), sign=s) for s in (-1, 1)}
upper = {s: find_bone(lambda n: any(k in n for k in ("upperarm", "uparm")) or ("arm" in n and "fore" not in n and "lower" not in n and "armor" not in n), sign=s) for s in (-1, 1)}
fore = {s: find_bone(lambda n: any(k in n for k in ("forearm", "lowerarm")), sign=s) for s in (-1, 1)}
handb = {s: find_bone(lambda n: n.endswith("hand") or "hand" in n and "finger" not in n and "index" not in n and "thumb" not in n, sign=s) for s in (-1, 1)}
spine_b = find_bone(lambda n: "spine" in n, low=True)
head_b = find_bone(lambda n: n.endswith("head") or n == "head", low=False)
neck_b = find_bone(lambda n: "neck" in n, low=True)
if have_roles:
    thigh = {s_: role_pick(ROLE_BONES["thigh"], s_) for s_ in (-1, 1)}
    calf = {s_: role_pick(ROLE_BONES["calf"], s_) for s_ in (-1, 1)}
    upper = {s_: role_pick(ROLE_BONES["upper"], s_) for s_ in (-1, 1)}
    fore = {s_: role_pick(ROLE_BONES["fore"], s_) for s_ in (-1, 1)}
    handb = {s_: role_pick(ROLE_BONES["hand"], s_) for s_ in (-1, 1)}
    spine_b = role_bone(ROLE_BONES["spine"]) if ROLE_BONES["spine"] else spine_b
    neck_b = role_bone(ROLE_BONES["neck"]) if ROLE_BONES["neck"] else neck_b

def P(b, default):
    return b[1] if b else default

J = {}
J["Hips"] = hips_pos
for s, sd in ((-1, "L"), (1, "R")):
    J["Hip" + sd] = P(thigh[s], Vector((0.13 * s, 0, hips_pos.z - 0.05)))
    J["Knee" + sd] = P(calf[s], Vector((J["Hip" + sd].x, 0, hips_pos.z - 0.5)))
    J["Shoulder" + sd] = P(upper[s], Vector((0.34 * s, 0, hips_pos.z + 0.55)))
    J["Elbow" + sd] = P(fore[s], J["Shoulder" + sd] + Vector((0, 0, -0.32)))
    J["Hand" + sd] = P(handb[s], J["Elbow" + sd] + Vector((0, 0, -0.31)))
J["Spine"] = P(spine_b, hips_pos + Vector((0, 0, 0.10)))
J["Head"] = P(neck_b, P(head_b, J["Spine"] + Vector((0, 0, 0.5))))
for k in list(J):
    J[k] = Vector(J[k])
# the middle joints sit on the body axis
for k in ("Hips", "Spine", "Head"):
    J[k].x = 0.0
    J[k].y = J["Hips"].y if k == "Hips" else 0.0
# make the legs hang straight down from the hips and put y (depth) = 0 for limb joints
for sd in ("L", "R"):
    for k in ("Hip", "Knee", "Shoulder", "Elbow", "Hand"):
        J[k + sd].y = 0.0

# ---------------------------------------------------------------- arms: rotate so that shoulder->hand points straight down
def rotate_part_about(faces_verts, pivot, R):
    for v in faces_verts:
        v.co = pivot + R @ (v.co - pivot)

part_verts = {}
for f, p in face_part:
    for v in f.verts:
        part_verts.setdefault(p, set()).add(v)
# sides of the limb parts by geometry (x sign of the face centre)
side_faces = {}
for f, p in face_part:
    c = sum((v.co for v in f.verts), Vector()) / len(f.verts)
    key = p
    if p in ("Upper", "Fore", "Thigh", "Shin"):
        key = p + ("L" if c.x < 0 else "R")
    side_faces.setdefault(key, []).append(f)

for sd, s in (("L", -1), ("R", 1)):
    sh = J["Shoulder" + sd]
    hd = J["Hand" + sd]
    v = hd - sh
    down = Vector((0, 0, -1))
    if v.length > 1e-4:
        ax = v.normalized().cross(down)
        ang = v.normalized().angle(down)
        if ax.length > 1e-5 and ang > 0.05:
            R = Matrix.Rotation(ang, 3, ax.normalized())
            verts = set()
            for key in ("Upper" + sd, "Fore" + sd):
                for f in side_faces.get(key, []):
                    verts.update(f.verts)
            rotate_part_about(verts, sh, R)
            J["Elbow" + sd] = sh + R @ (J["Elbow" + sd] - sh)
            J["Hand" + sd] = sh + R @ (J["Hand" + sd] - sh)
            print("CHAR arm", sd, "rotated %.0f deg" % math.degrees(ang))

# ---------------------------------------------------------------- build the output scene: Empties + one mesh per part
src_me = bpy.data.meshes.new("src")
bm.to_mesh(src_me)

# remove originals
for o in list(bpy.context.scene.objects):
    bpy.data.objects.remove(o, do_unlink=True)

def mk_empty(name, parent, world_pos, parent_pos):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    e.location = world_pos - parent_pos
    return e

root = bpy.data.objects.new("player", None)
bpy.context.scene.collection.objects.link(root)
H_ = {}
H_["Hips"] = mk_empty("Hips", root, J["Hips"], Vector())
for sd in ("L", "R"):
    H_["Hip" + sd] = mk_empty("Hip" + sd, H_["Hips"], J["Hip" + sd], J["Hips"])
    H_["Knee" + sd] = mk_empty("Knee" + sd, H_["Hip" + sd], J["Knee" + sd], J["Hip" + sd])
H_["Spine"] = mk_empty("Spine", H_["Hips"], J["Spine"], J["Hips"])
H_["Head"] = mk_empty("Head", H_["Spine"], J["Head"], J["Spine"])
for sd in ("L", "R"):
    H_["Shoulder" + sd] = mk_empty("Shoulder" + sd, H_["Spine"], J["Shoulder" + sd], J["Spine"])
    H_["Elbow" + sd] = mk_empty("Elbow" + sd, H_["Shoulder" + sd], J["Elbow" + sd], J["Shoulder" + sd])
    H_["Hand" + sd] = mk_empty("Hand" + sd, H_["Elbow" + sd], J["Hand" + sd], J["Elbow" + sd])

# which joint owns each part (its pivot): geometry in that joint's local frame
OWN = {"Head": ("Head", None), "Torso": ("Spine", None), "Pelvis": ("Hips", None)}
for sd in ("L", "R"):
    OWN["Upper" + sd] = ("Shoulder" + sd, sd)
    OWN["Fore" + sd] = ("Elbow" + sd, sd)
    OWN["Thigh" + sd] = ("Hip" + sd, sd)
    OWN["Shin" + sd] = ("Knee" + sd, sd)

# faces per final part name
final_faces = {}
for f, p in face_part:
    if not f.is_valid:
        continue
    c = sum((v.co for v in f.verts), Vector()) / len(f.verts)
    name = p
    if p in ("Upper", "Fore", "Thigh", "Shin"):
        name = p + ("L" if c.x < 0 else "R")
    final_faces.setdefault(name, []).append(f)

# the combined mesh keeps face order, so index faces by their position in bm.faces
bm.faces.ensure_lookup_table()
face_index = {f: i for i, f in enumerate(bm.faces)}
total_tris = 0
for pname, flist in final_faces.items():
    joint, _ = OWN.get(pname, ("Spine", None))
    pivot = J[joint]
    nb = bmesh.new()
    nuv = nb.loops.layers.uv.new("UVMap")
    vmap = {}
    for f in flist:
        nv = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = nb.verts.new(v.co - pivot)
            nv.append(vmap[v])
        try:
            nf = nb.faces.new(nv)
            nf.material_index = f.material_index
            nf.smooth = f.smooth
            for li, loop in enumerate(nf.loops):
                loop[nuv].uv = f.loops[li][uv_lay].uv
        except ValueError:
            pass
    me = bpy.data.meshes.new(pname)
    nb.to_mesh(me)
    nb.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(pname + "Mesh" if pname not in ("Head",) else "HeadMesh", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = H_[joint]
    total_tris += sum(len(p.vertices) - 2 for p in me.polygons)
print("CHAR parts", {k: len(v) for k, v in final_faces.items()}, "tris", total_tris)

# ---------------------------------------------------------------- textures / materials: keep the colour map only, shrink
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    nt = mat.node_tree
    pr = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"]
    if not (pr and pr[0].inputs["Base Color"].is_linked):
        imgs = [n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image]
        imgs.sort(key=lambda n: 0 if any(k in n.image.name.lower() for k in ("diffuse", "color", "albedo", "base")) else 1)
        out_node = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
        if imgs and out_node is not None:
            bsdf = pr[0] if pr else nt.nodes.new("ShaderNodeBsdfPrincipled")
            nt.links.new(imgs[0].outputs["Color"], bsdf.inputs["Base Color"])
            for l in list(out_node.inputs["Surface"].links):
                nt.links.remove(l)
            nt.links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
            pr = [bsdf]
    for node in pr:
        for name in ("Metallic", "Roughness"):
            for link in list(node.inputs[name].links):
                nt.links.remove(link)
        node.inputs["Metallic"].default_value = 0.1
        node.inputs["Roughness"].default_value = 0.7
        for link in list(node.inputs["Normal"].links):
            nt.links.remove(link)
    for n in list(nt.nodes):
        if n.type == "TEX_IMAGE" and not any(o.is_linked for o in n.outputs):
            nt.nodes.remove(n)
for img in list(bpy.data.images):
    if not any(n.image == img for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes if n.type == "TEX_IMAGE"):
        bpy.data.images.remove(img)
        continue
    if img.size[0] > opts["tex"] or img.size[1] > opts["tex"]:
        kk = opts["tex"] / max(img.size[0], img.size[1])
        img.scale(max(1, int(img.size[0] * kk)), max(1, int(img.size[1] * kk)))

for ob in bpy.context.scene.objects:
    if ob.type == "MESH":
        print("CHAR obj", ob.name, [m.name if m else None for m in ob.data.materials], len(ob.data.polygons), set(p.material_index for p in ob.data.polygons))
        break
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_image_format="AUTO", export_apply=True, export_yup=True)
print("CHAR done %s %.1f KB" % (out, os.path.getsize(out) / 1024.0))
