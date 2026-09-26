"""Turns a scene's rendered frames into what the site serves.

    blender -b --factory-startup --python site/art/encode.py -- class-set

Rendering the 3D scene is the slow part, so it happens once, to RGBA PNG
frames (`blender -b site/art/class-set.blend -a`, which writes them to
.render/class-set-frames/). This script only encodes those frames, so
re-encoding at a different quality never re-renders anything.

The frames have a transparent background, and the encodes keep faith with it
differently:

    NAME.webm        VP9 with the alpha kept, so the animation floats
                     directly on the page — no desk, no rectangle.
    NAME.mp4         H.264 cannot carry alpha, so the site's own paper cream
                     is composited underneath. On the flat cream hero band
                     the fallback still blends; the page's CSS mask fades its
                     edges just in case.
    NAME-start.webp  the video's poster: its first frame exactly, alpha kept.
    NAME-end.webp    the settled last frame, alpha kept, shown instead of the
                     video to anyone who has asked for reduced motion.
"""
import glob
import os
import shutil
import sys

import bpy

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
NAME = ARGS[0] if ARGS else 'class-set'

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
FRAMES = os.path.join(REPO, '.render', f'{NAME}-frames')
OUT = os.path.join(REPO, 'site', 'public', 'art')
os.makedirs(OUT, exist_ok=True)

files = sorted(glob.glob(os.path.join(FRAMES, 'f_*.png')))
if not files:
    raise SystemExit(f'no frames in {FRAMES} - render site/art/{NAME}.blend first')


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# The site's paper: --c-paper #f6f1e3, in linear for the sequencer.
CREAM = tuple(srgb_to_linear(v) for v in (0xF6, 0xF1, 0xE3))

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
cream = strips.new_effect(name='cream', type='COLOR', channel=1, frame_start=1, length=len(files))
cream.color = CREAM
strip = strips.new_image(name='frames', filepath=files[0], channel=2, frame_start=1)
for f in files[1:]:
    strip.elements.append(os.path.basename(f))


def encode(container, codec, name, alpha):
    """Blender appends the frame range to a video's filename, so encode to a
    scratch name and move the result to the one the page asks for."""
    scratch = os.path.join(OUT, f'_tmp_{name}')
    if hasattr(scene.render.image_settings, 'media_type'):
        scene.render.image_settings.media_type = 'VIDEO'
    scene.render.image_settings.file_format = 'FFMPEG'
    ff = scene.render.ffmpeg
    # Container and codec first: the colour-mode enum narrows to what the
    # chosen format can carry, so RGBA only exists once the format is WebM.
    ff.format = container
    ff.codec = codec
    ff.constant_rate_factor = 'HIGH'
    ff.ffmpeg_preset = 'GOOD'
    ff.gopsize = 24
    ff.audio_codec = 'NONE'
    if alpha:
        try:
            # Keep the frames' alpha all the way into the file, and let
            # nothing sit underneath them.
            scene.render.image_settings.color_mode = 'RGBA'
            cream.mute = True
            strip.blend_type = 'REPLACE'
        except TypeError:
            # This build cannot write alpha into this container after all.
            # Cream under it is the honest fallback — and the page must then
            # rely on its mask, so say so loudly rather than silently.
            print(f'!! {name}: no alpha support in {container}; baking cream underneath instead')
            alpha = False
    if not alpha:
        scene.render.image_settings.color_mode = 'RGB'
        cream.mute = False
        strip.blend_type = 'ALPHA_OVER'
    scene.render.filepath = scratch
    bpy.ops.render.render(animation=True)
    made = sorted(glob.glob(scratch + '*'))
    if not made:
        raise SystemExit(f'{name}: encoder produced nothing')
    final = os.path.join(OUT, name)
    shutil.move(made[-1], final)
    print(f'wrote {final} ({os.path.getsize(final) // 1024} KB)')


def still(src, name, quality=88):
    img = bpy.data.images.load(src)
    img.file_format = 'WEBP'
    dest = os.path.join(OUT, name)
    if hasattr(scene.render.image_settings, 'media_type'):
        scene.render.image_settings.media_type = 'IMAGE'
    scene.render.image_settings.file_format = 'WEBP'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.quality = quality
    img.save_render(dest, scene=scene)
    print(f'wrote {dest} ({os.path.getsize(dest) // 1024} KB)')


encode('WEBM', 'WEBM', f'{NAME}.webm', alpha=True)
encode('MPEG4', 'H264', f'{NAME}.mp4', alpha=False)
still(files[0], f'{NAME}-start.webp')
still(files[-1], f'{NAME}-end.webp')
