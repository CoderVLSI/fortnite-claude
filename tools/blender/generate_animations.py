"""Hand-keyed animation clips for the Storm Island character rig, baked with Blender.

    blender -b -P tools/blender/generate_animations.py       ->  assets/models/anims.glb

The rig is the same joint hierarchy as player.glb (Hips, Spine, Head, ShoulderL/R, ElbowL/R, HandL/R, HipL/R, KneeL/R).
Each clip is a table of keyframes; poses are written as Godot Euler angles (YXZ order, the same numbers the in-game
Animator uses: thigh / arm forward = +X, lean forward = -X, arms out to the side = +-Z), converted to Blender quaternions
here, keyed with Bezier easing and exported as glTF animations (one NLA track per clip). The game samples the clips
through scripts/AnimClips.gd and layers them on top of its procedural locomotion.

Clips:  slide (full body)  vault (full body, through a window)  mantle (full body, up a ledge)
        harvest (upper body only, the pickaxe swing)
"""

import math
import os

import bpy
from mathutils import Quaternion, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "anims.glb")
FPS = 30

JOINTS = ["Hips", "Spine", "Head", "ShoulderL", "ElbowL", "HandL", "ShoulderR", "ElbowR", "HandR", "HipL", "KneeL", "HipR", "KneeR"]
WORLD = {"Hips": (0, 0, 0.93), "Spine": (0, 0, 1.03), "Head": (0, 0, 1.53),
         "ShoulderL": (-0.34, 0, 1.47), "ElbowL": (-0.34, 0, 1.15), "HandL": (-0.34, 0, 0.84),
         "ShoulderR": (0.34, 0, 1.47), "ElbowR": (0.34, 0, 1.15), "HandR": (0.34, 0, 0.84),
         "HipL": (-0.13, 0, 0.88), "KneeL": (-0.13, 0, 0.45), "HipR": (0.13, 0, 0.88), "KneeR": (0.13, 0, 0.45)}
PARENT = {"Spine": "Hips", "Head": "Spine", "ShoulderL": "Spine", "ElbowL": "ShoulderL", "HandL": "ElbowL",
          "ShoulderR": "Spine", "ElbowR": "ShoulderR", "HandR": "ElbowR", "HipL": "Hips", "KneeL": "HipL", "HipR": "Hips", "KneeR": "HipR"}

Z = (0.0, 0.0, 0.0)


def pose(**kw):
    """pose(Hips=(rx, ry, rz), ...) -> dict; joints left out stay at rest."""
    return dict(kw)


# time (s), {joint: (rx, ry, rz)}, hips drop (+ up / - down, metres)
CLIPS = {
    # sprint -> low slide: lean back, lead leg out, trailing leg folded, arms out for balance, then up again
    "slide": {"dur": 0.85, "keys": [
        (0.00, pose(Hips=Z, Spine=Z, Head=Z, ShoulderL=Z, ShoulderR=Z, ElbowL=Z, ElbowR=Z, HipL=Z, HipR=Z, KneeL=Z, KneeR=Z), 0.0),
        (0.14, pose(Hips=(0.30, 0, 0), Spine=(0.55, 0, 0), Head=(-0.45, 0, 0.0), ShoulderL=(0.35, 0, 0.95), ShoulderR=(0.35, 0, -0.95),
                    ElbowL=(0.35, 0, 0), ElbowR=(0.35, 0, 0), HipL=(1.5, 0, 0.06), HipR=(0.7, 0, -0.06), KneeL=(-0.15, 0, 0), KneeR=(-1.55, 0, 0)), -0.64),
        (0.45, pose(Hips=(0.32, 0, 0.05), Spine=(0.62, 0, -0.05), Head=(-0.5, 0.1, 0.0), ShoulderL=(0.5, 0, 1.1), ShoulderR=(0.2, 0, -0.85),
                    ElbowL=(0.3, 0, 0), ElbowR=(0.5, 0, 0), HipL=(1.55, 0, 0.08), HipR=(0.75, 0, -0.08), KneeL=(-0.1, 0, 0), KneeR=(-1.6, 0, 0)), -0.68),
        (0.68, pose(Hips=(0.2, 0, 0), Spine=(0.35, 0, 0), Head=(-0.25, 0, 0), ShoulderL=(0.4, 0, 0.6), ShoulderR=(0.4, 0, -0.6),
                    ElbowL=(0.5, 0, 0), ElbowR=(0.5, 0, 0), HipL=(1.1, 0, 0), HipR=(0.9, 0, 0), KneeL=(-0.6, 0, 0), KneeR=(-1.2, 0, 0)), -0.38),
        (0.85, pose(Hips=Z, Spine=(-0.05, 0, 0), Head=Z, ShoulderL=(0.3, 0, 0.1), ShoulderR=(0.3, 0, -0.1), ElbowL=(0.4, 0, 0), ElbowR=(0.4, 0, 0),
                    HipL=(0.3, 0, 0), HipR=(0.3, 0, 0), KneeL=(-0.3, 0, 0), KneeR=(-0.3, 0, 0)), -0.05),
    ]},
    # hop through a window: hands out to the sill, legs tucked and swung over, drop and absorb the landing
    "vault": {"dur": 0.8, "keys": [
        (0.00, pose(Hips=Z, Spine=(-0.1, 0, 0), Head=(0.1, 0, 0), ShoulderL=(1.6, 0, 0.15), ShoulderR=(1.6, 0, -0.15), ElbowL=(0.3, 0, 0), ElbowR=(0.3, 0, 0),
                    HipL=(0.5, 0, 0), HipR=(-0.1, 0, 0), KneeL=(-0.5, 0, 0), KneeR=(-0.2, 0, 0)), 0.0),
        (0.20, pose(Hips=(-0.1, 0, 0), Spine=(-0.55, 0, 0), Head=(0.45, 0, 0), ShoulderL=(2.3, 0, 0.25), ShoulderR=(2.3, 0, -0.25), ElbowL=(0.15, 0, 0), ElbowR=(0.15, 0, 0),
                    HipL=(1.1, 0, 0.1), HipR=(0.3, 0, -0.1), KneeL=(-1.2, 0, 0), KneeR=(-0.8, 0, 0)), 0.1),
        (0.42, pose(Hips=(-0.15, 0, 0.35), Spine=(-0.4, 0, -0.2), Head=(0.3, 0, 0.1), ShoulderL=(0.9, 0, 0.4), ShoulderR=(1.2, 0, -0.3), ElbowL=(0.8, 0, 0), ElbowR=(0.5, 0, 0),
                    HipL=(1.7, 0, 0.35), HipR=(1.4, 0, -0.1), KneeL=(-1.6, 0, 0), KneeR=(-1.7, 0, 0)), 0.28),
        (0.60, pose(Hips=(-0.1, 0, 0.0), Spine=(-0.3, 0, 0), Head=(0.15, 0, 0), ShoulderL=(0.5, 0, 0.5), ShoulderR=(0.5, 0, -0.5), ElbowL=(0.6, 0, 0), ElbowR=(0.6, 0, 0),
                    HipL=(1.0, 0, 0), HipR=(0.9, 0, 0), KneeL=(-1.3, 0, 0), KneeR=(-1.4, 0, 0)), -0.22),
        (0.80, pose(Hips=Z, Spine=(-0.05, 0, 0), Head=Z, ShoulderL=(0.15, 0, 0.05), ShoulderR=(0.15, 0, -0.05), ElbowL=(0.25, 0, 0), ElbowR=(0.25, 0, 0),
                    HipL=(0.15, 0, 0), HipR=(0.15, 0, 0), KneeL=(-0.2, 0, 0), KneeR=(-0.2, 0, 0)), -0.02),
    ]},
    # climb a ledge: reach up, pull, knee up, push over, stand
    "mantle": {"dur": 0.7, "keys": [
        (0.00, pose(Hips=Z, Spine=(-0.1, 0, 0), Head=(0.2, 0, 0), ShoulderL=(2.7, 0, -0.25), ShoulderR=(2.7, 0, 0.25), ElbowL=(0.2, 0, 0), ElbowR=(0.2, 0, 0),
                    HipL=(0.4, 0, 0), HipR=(0.1, 0, 0), KneeL=(-0.6, 0, 0), KneeR=(-0.3, 0, 0)), 0.0),
        (0.28, pose(Hips=(-0.1, 0, 0), Spine=(-0.5, 0, 0), Head=(0.3, 0, 0), ShoulderL=(2.0, 0, -0.2), ShoulderR=(2.0, 0, 0.2), ElbowL=(1.5, 0, 0), ElbowR=(1.5, 0, 0),
                    HipL=(1.3, 0, 0.1), HipR=(0.3, 0, 0), KneeL=(-1.5, 0, 0), KneeR=(-0.6, 0, 0)), 0.05),
        (0.52, pose(Hips=(-0.1, 0, 0), Spine=(-0.35, 0, 0), Head=(0.15, 0, 0), ShoulderL=(0.7, 0, 0.3), ShoulderR=(0.7, 0, -0.3), ElbowL=(0.5, 0, 0), ElbowR=(0.5, 0, 0),
                    HipL=(1.0, 0, 0), HipR=(0.7, 0, 0), KneeL=(-1.3, 0, 0), KneeR=(-1.1, 0, 0)), -0.08),
        (0.70, pose(Hips=Z, Spine=(-0.05, 0, 0), Head=Z, ShoulderL=(0.2, 0, 0.05), ShoulderR=(0.2, 0, -0.05), ElbowL=(0.25, 0, 0), ElbowR=(0.25, 0, 0),
                    HipL=(0.1, 0, 0), HipR=(0.1, 0, 0), KneeL=(-0.15, 0, 0), KneeR=(-0.1, 0, 0)), 0.0),
    ]},
    # pickaxe swing (upper body only): wind up overhead, smash down, follow through
    "harvest": {"dur": 0.5, "upper": True, "keys": [
        (0.00, pose(Spine=(0.05, 0, 0), Head=(0.1, 0, 0), ShoulderR=(1.4, 0.1, 0.1), ShoulderL=(1.3, -0.4, 0.0), ElbowR=(0.9, 0, 0), ElbowL=(0.9, 0, 0)), 0.0),
        (0.17, pose(Spine=(0.22, 0.25, 0), Head=(0.2, 0, 0), ShoulderR=(2.75, 0.2, 0.15), ShoulderL=(2.5, -0.3, 0.0), ElbowR=(1.2, 0, 0), ElbowL=(1.2, 0, 0)), 0.0),
        (0.30, pose(Spine=(-0.5, -0.3, 0), Head=(-0.2, 0, 0), ShoulderR=(0.95, -0.1, 0.0), ShoulderL=(0.9, -0.4, 0.0), ElbowR=(0.25, 0, 0), ElbowL=(0.3, 0, 0)), 0.0),
        (0.40, pose(Spine=(-0.38, -0.2, 0), Head=(-0.1, 0, 0), ShoulderR=(0.8, 0, 0.05), ShoulderL=(0.8, -0.4, 0.0), ElbowR=(0.45, 0, 0), ElbowL=(0.5, 0, 0)), 0.0),
        (0.50, pose(Spine=(0.0, 0, 0), Head=Z, ShoulderR=(1.0, 0.1, 0.1), ShoulderL=(1.0, -0.4, 0.0), ElbowR=(0.8, 0, 0), ElbowL=(0.8, 0, 0)), 0.0),
    ]},
}


def quat_from_godot_euler(rx, ry, rz):
    """Godot Euler (YXZ order, Y-up) -> Blender quaternion (Z-up): R = Ry * Rx * Rz, then swap the axes."""
    qx = Quaternion((1, 0, 0), rx)
    qy = Quaternion((0, 1, 0), ry)
    qz = Quaternion((0, 0, 1), rz)
    q = qy @ qx @ qz
    return Quaternion((q.w, q.x, -q.z, q.y))


def build_rig():
    objs = {}
    for name in JOINTS:
        o = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(o)
        o.rotation_mode = "QUATERNION"
        objs[name] = o
    for name in JOINTS:
        o = objs[name]
        w = Vector(WORLD[name])
        if name in PARENT:
            o.parent = objs[PARENT[name]]
            o.location = w - Vector(WORLD[PARENT[name]])
        else:
            o.location = w
    return objs


def key_clip(objs, clip, spec):
    joints = [j for j in JOINTS if not spec.get("upper") or j in ("Spine", "Head", "ShoulderL", "ElbowL", "ShoulderR", "ElbowR")]
    for name in joints:
        o = objs[name]
        o.animation_data_create()
        act = bpy.data.actions.new("%s_%s" % (clip, name))
        o.animation_data.action = act
        for t, p, dy in spec["keys"]:
            frame = 1 + round(t * FPS)
            rx, ry, rz = p.get(name, Z)
            o.rotation_quaternion = quat_from_godot_euler(rx, ry, rz)
            o.keyframe_insert("rotation_quaternion", frame=frame)
            if name == "Hips" and not spec.get("upper"):
                o.location = Vector(WORLD["Hips"]) + Vector((0, 0, dy))
                o.keyframe_insert("location", frame=frame)
        for fc in act.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
        track = o.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, 1, act)
        strip.name = clip
        o.animation_data.action = None


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    objs = build_rig()
    for clip, spec in CLIPS.items():
        key_clip(objs, clip, spec)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs.values():
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs["Hips"]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=True,
                              export_nla_strips=True, export_force_sampling=True, export_yup=True)
    print("exported", OUT)


if __name__ == "__main__":
    main()
