# make_app_icons.py <square source.png> <client dir>
#
# Writes OldSend's app icons at every size iOS 6 uses, the way iOS 6 wants them for apps in
# /Applications. Those are system apps to iOS 6, and it draws their icons exactly as supplied:
# no rounded mask, no gloss, no shadow added. So the corners and the shadow are in the PNGs, as in
# Apple's own and Cydia's icons, and the home-screen icons are on the canvas iOS 6 expects:
#   iPhone 59 x 60 pt (57 pt icon + 1 pt sides + shadow below), iPad 74 x 76 pt (72 pt icon).
# A plain 57 x 57 icon gets stretched to 59 x 60 by SpringBoard, which looks soft and slightly tall.
# Layout and shadow measured from Cydia's icon@2x.png (114 px body at x 2, y 1 in 118 x 120,
# corner radius 10/57 of the size, a 3 px soft black shadow under the bottom edge).
# The source should be square, at least 512 px (1024 px best), with square corners and no gloss.
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

RADIUS = 10.0 / 57.0   # iOS 6 corner radius relative to the icon size
SS = 8                 # supersampling for smooth corner edges

# name: (canvas w, canvas h, icon size, x, y, shadow)   in pixels
ICONS = {
    'Icon.png':             (59, 60, 57, 1, 0, True),     # iPhone home screen
    'Icon@2x.png':          (118, 120, 114, 2, 1, True),
    'Icon-72.png':          (74, 76, 72, 1, 0, True),     # iPad home screen
    'Icon-72@2x.png':       (148, 152, 144, 2, 1, True),
    'Icon-Small.png':       (29, 29, 29, 0, 0, False),    # Settings, notifications, Spotlight
    'Icon-Small@2x.png':    (58, 58, 58, 0, 0, False),
    'Icon-Small-50.png':    (50, 50, 50, 0, 0, False),    # iPad Spotlight
    'Icon-Small-50@2x.png': (100, 100, 100, 0, 0, False),
}


def rounded_mask(pixels, size):
    mask = Image.new('L', (pixels, pixels), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pixels, pixels], radius=RADIUS * size * SS, fill=255)
    return mask


def icon(source, width, height, size, x, y, shadow):
    canvas = Image.new('RGBA', (width * SS, height * SS), (0, 0, 0, 0))
    pixels = int(round(size * SS))
    left, top = int(round(x * SS)), int(round(y * SS))
    body = source.resize((pixels, pixels), Image.LANCZOS).convert('RGBA')
    mask = rounded_mask(pixels, size)
    body.putalpha(mask)
    if shadow:
        # A soft black shadow peeking out under the bottom edge, as on Apple's iOS 6 icons.
        unit = size / 57.0 * SS          # one point of the icon, in supersampled pixels
        drop = Image.new('L', canvas.size, 0)
        drop.paste(mask, (left, int(top + 0.9 * unit)))
        drop = drop.filter(ImageFilter.GaussianBlur(0.45 * unit)).point(lambda v: int(v * 0.55))
        shade = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
        shade.putalpha(drop)
        canvas.alpha_composite(shade)
    canvas.alpha_composite(body, (left, top))
    # Area-average down to the final size: sharp, and no ringing at the transparent edges.
    return canvas.reduce(SS)


def main(source_path, out_dir):
    source = Image.open(source_path).convert('RGB')
    if source.size[0] != source.size[1]:
        sys.exit('the source icon must be square')
    for name, spec in ICONS.items():
        icon(source, *spec).save(os.path.join(out_dir, name), optimize=True)
        print(name, spec[:2])


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
