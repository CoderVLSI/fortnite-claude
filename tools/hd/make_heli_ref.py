# blender -b -P tools/hd/make_heli_ref.py   -> tools/hd/refs/helicopter.glb : a block helicopter with the same size / axes as the
# primitive one in scripts/Helicopter.gd (nose toward -Z in Godot), used as the reference when fitting a Sketchfab helicopter.
import bpy, os
bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.delete()
boxes = [  # (size x,y,z) (pos x,y,z) in Godot axes
    ((1.9, 1.35, 3.0), (0, 1.25, 0.2)), ((1.7, 1.0, 1.0), (0, 1.1, -1.7)), ((0.45, 0.45, 3.2), (0, 1.55, 3.0)), ((0.18, 1.3, 0.7), (0, 2.1, 4.5)),
    ((0.12, 0.12, 3.4), (-0.9, 0.18, 0.1)), ((0.12, 0.12, 3.4), (0.9, 0.18, 0.1)), ((0.5, 0.35, 0.8), (0, 2.1, 0.0)),
]
for size, pos in boxes:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(pos[0], -pos[2], pos[1]))     # Godot (x,y,z) -> Blender (x,-z,y)
    o = bpy.context.active_object
    o.scale = (size[0], size[2], size[1])
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=os.path.join(os.path.dirname(os.path.abspath(__file__)), "refs", "helicopter.glb"), export_format="GLB", export_yup=True)
