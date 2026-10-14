"""Decimates imported HD .glb files in place to a triangle budget (keeps UVs, materials, empties such as Muzzle).
   blender -b -P tools/hd/reduce.py -- <budget> file.glb [file.glb ...]"""
import bpy, sys
argv = sys.argv[sys.argv.index("--") + 1:]
budget = int(argv[0])
for path in argv[1:]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    tris = sum(len(o.data.polygons) for o in meshes)  # polygons, tris after triangulate below
    for o in meshes:
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.mode_set(mode="OBJECT")
        m = o.modifiers.new("tri", "TRIANGULATE")
        bpy.ops.object.modifier_apply(modifier=m.name)
    tris = sum(len(o.data.polygons) for o in meshes)
    if tris > budget:
        ratio = budget / float(tris)
        for o in meshes:
            bpy.context.view_layer.objects.active = o
            m = o.modifiers.new("dec", "DECIMATE")
            m.ratio = ratio
            m.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=m.name)
    after = sum(len(o.data.polygons) for o in meshes)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_image_format="AUTO")
    print("REDUCE", path, tris, "->", after)
