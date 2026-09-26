"""Turns a scene's rendered frames into what the site serves.

    blender -b --factory-startup --python site/art/encode.py -- marking-scan

Rendering the 3D scene is the slow part, so it happens once, to PNG frames
(`blender -b site/art/marking-scan.blend -a`, which writes them to
.render/marking-scan-frames/). This script only encodes those frames, so
re-encoding at a different quality never re-renders anything.

Writes into site/public/art/, for a scene called NAME:
    NAME.webm        VP9, what nearly every browser plays
    NAME.mp4         H.264, for the ones that will not play VP9
    NAME-start.webp  the video's poster: its first frame exactly, so nothing
                     jumps when playback begins
    NAME-end.webp    the settled last frame, shown instead of the video to
                     anyone who has asked for reduced motion
"""
import glob
import os
import shutil
import sys

import bpy

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
NAME = ARGS[0] if ARGS else 'marking-scan'

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
FRAMES = os.path.join(REPO, '.render', f'{NAME}-frames')
OUT = os.path.join(REPO, 'site', 'public', 'art')
os.makedirs(OUT, exist_ok=True)

files = sorted(glob.glob(os.path.join(FRAMES, 'f_*.png')))
if not files:
    raise SystemExit(f'no frames in {FRAMES} - render site/art/{NAME}.blend first')

scene = bpy.context.scene
scene.render.resolution_x = 1400
scene.render.resolution_y = 980
scene.render.resolution_percentage = 100
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = len(files)
scene.render.use_sequencer = True

se = scene.sequence_editor_create()
# Blender 4.4 renamed the strip collection from `sequences` to `strips`.
strips = se.strips if hasattr(se, 'strips') else se.sequences
strip = strips.new_image(name='frames', filepath=files[0], channel=1, frame_start=1)
for f in files[1:]:
    strip.elements.append(os.path.basename(f))


def encode(container, codec, name):
    """Blender appends the frame range to a video's filename, so encode to a
    scratch name and move the result to the one the page asks for."""
    scratch = os.path.join(OUT, f'_tmp_{name}')
    # Blender 5 splits output into media types, and FFMPEG is not even in
    # the list of file formats until the media type says video.
    if hasattr(scene.render.image_settings, 'media_type'):
        scene.render.image_settings.media_type = 'VIDEO'
    scene.render.image_settings.file_format = 'FFMPEG'
    scene.render.image_settings.color_mode = 'RGB'
    ff = scene.render.ffmpeg
    ff.format = container
    ff.codec = codec
    ff.constant_rate_factor = 'HIGH'
    ff.ffmpeg_preset = 'GOOD'
    # A keyframe on every frame is waste on a clip this short; one a second
    # is plenty and keeps the file small.
    ff.gopsize = 24
    ff.audio_codec = 'NONE'
    scene.render.filepath = scratch
    bpy.ops.render.render(animation=True)
    made = sorted(glob.glob(scratch + '*'))
    if not made:
        raise SystemExit(f'{name}: encoder produced nothing')
    final = os.path.join(OUT, name)
    shutil.move(made[-1], final)
    print(f'wrote {final} ({os.path.getsize(final) // 1024} KB)')


def still(src, name, quality=86):
    img = bpy.data.images.load(src)
    img.file_format = 'WEBP'
    dest = os.path.join(OUT, name)
    if hasattr(scene.render.image_settings, 'media_type'):
        scene.render.image_settings.media_type = 'IMAGE'
    scene.render.image_settings.file_format = 'WEBP'
    scene.render.image_settings.quality = quality
    img.save_render(dest, scene=scene)
    print(f'wrote {dest} ({os.path.getsize(dest) // 1024} KB)')


encode('WEBM', 'WEBM', f'{NAME}.webm')
encode('MPEG4', 'H264', f'{NAME}.mp4')
still(files[0], f'{NAME}-start.webp')
still(files[-1], f'{NAME}-end.webp')
