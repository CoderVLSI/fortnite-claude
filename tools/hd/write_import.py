#!/usr/bin/env python3
"""Writes the .import files for HD models (embedded materials: the file names Sketchfab authors chose, such as 'Material', would clash
as external .material files). Run before tools/import_assets.sh.   write_import.py [hd/models/*.glb ...]"""
import glob, os, sys
TEMPLATE = """[remap]

importer="scene"
type="PackedScene"

[deps]

source_file="res://%s"

[params]

nodes/root_type="Spatial"
nodes/root_name="Scene Root"
nodes/root_scale=1.0
nodes/custom_script=""
nodes/storage=0
nodes/use_legacy_names=false
materials/location=0
materials/storage=0
materials/keep_on_reimport=false
meshes/octahedral_compression=true
meshes/compress=4286
meshes/ensure_tangents=true
meshes/storage=0
meshes/light_baking=0
meshes/lightmap_texel_size=0.1
skins/use_named_skins=true
external_files/store_in_subdir=false
animation/import=true
animation/fps=15
animation/filter_script=""
animation/storage=false
animation/keep_custom_tracks=false
animation/optimizer/enabled=true
animation/optimizer/max_linear_error=0.05
animation/optimizer/max_angular_error=0.01
animation/optimizer/max_angle=22
animation/optimizer/remove_unused_tracks=true
animation/clips/amount=0
animation/clip_1/name=""
animation/clip_1/start_frame=0
animation/clip_1/end_frame=0
animation/clip_1/loops=false
"""
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
files = sys.argv[1:] or glob.glob(os.path.join(root, "hd", "models", "*.glb"))
for f in files:
    rel = os.path.relpath(os.path.abspath(f), os.path.abspath(root)).replace(os.sep, "/")
    imp = os.path.join(root, rel + ".import")
    if os.path.exists(imp) and "materials/location=0" in open(imp).read():
        continue
    open(imp, "w").write(TEMPLATE % rel)
    print("wrote", rel + ".import")
