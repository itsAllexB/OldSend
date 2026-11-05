# make_app_icons.py <square source.png> <client dir>
#
# Writes OldSend's app icons at every size iOS 6 uses, finished the way Apple's own app icons are.
# iOS 6 treats apps in /Applications as system apps and draws their icons exactly as supplied: no
# rounded mask, no shadow, no gloss. Apple's apps therefore ship finished icons, and so does this.
#
# What a finished icon looks like was measured on an iPhone 4S running iOS 6.1.3, from Apple's
# icons (Mail, Notes, Messages, Settings, Safari) and from the templates iOS itself applies to App
# Store apps (/System/Library/PrivateFrameworks/MobileIcons.framework: AppIconMask, AppIconShadow,
# TableIconMask, TableIconOutline). Apple's home-screen icons are exactly that mask and shadow:
#   Home screen, iPhone (Icon@2x.png): 118 x 120 px. The icon is 114 px at x 2, y 1, with circular
#     corners of 20 px (10/57 of the size). Under it is a shadow: the same shape moved 2 px down,
#     blurred (a 5 px wide ramp: 14, 43, 85, 114 of 255 under the bottom edge, 14, 43 at the
#     sides) and 50 % black. SpringBoard puts that image 2 px down in its 118 x 124 icon, as is.
#   Home screen, iPad (Icon-72@2x.png): 148 x 152 px, the icon 144 px at x 2, y 2, a shadow
#     1.5 px down at 60 % black.
#   Settings, Spotlight, notifications (Icon-Small@2x.png): 58 x 58 px, corners of 9 px, and a thin
#     dark outline along the edge (black, 28 % at the top to 41 % at the bottom), no shadow.
#   iPad Spotlight (Icon-Small-50@2x.png): 100 x 100 px, the icon 96 px at x 2, y 2, a faint
#     one-pixel shadow under it.
# The 1x files are the same at half the size (the home-screen icon at x 1, y 0).
#
# The Info.plist must list every file, @2x ones included, in CFBundleIconFiles, as Apple's apps
# do: SpringBoard picks from the listed names only, and without Icon@2x.png it picks
# Icon-72.png (the 1x iPad icon) and scales it up, which looks soft and sits 1 px off.
#
# The source should be square, at least 512 px (1024 px best), with square corners and no gloss.
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SS = 8  # supersampling for the masks and shadows

# name: canvas w, canvas h, icon size, x, y, corner radius, shadow, outline   (pixels)
#   shadow: (drop, blur, opacity) or None; blur is a Gaussian sigma, or RAMP
RAMP = (14, 29, 42, 29, 14)  # Apple's shadow blur at @2x: the edge ramps 14, 43, 85, 114, 128
ICONS = {
    'Icon.png':             (59, 60, 57, 1, 0, 10.0, (1.0, 0.585, 0.50), False),   # iPhone home
    'Icon@2x.png':          (118, 120, 114, 2, 1, 20.0, (2.0, RAMP, 0.50), False),
    'Icon-72.png':          (74, 76, 72, 1, 1, 12.625, (0.75, 0.4, 0.60), False),  # iPad home
    'Icon-72@2x.png':       (148, 152, 144, 2, 2, 25.25, (1.5, 0.8, 0.60), False),
    'Icon-Small.png':       (29, 29, 29, 0, 0, 4.5, None, True),    # Settings, Spotlight, notifications
    'Icon-Small@2x.png':    (58, 58, 58, 0, 0, 9.0, None, True),
    'Icon-Small-50.png':    (50, 50, 48, 1, 1, 8.0, (0.5, 0, 0.18), False),   # iPad Spotlight
    'Icon-Small-50@2x.png': (100, 100, 96, 2, 2, 16.0, (1.0, 0, 0.18), False),
}


def shape(width, height, x, y, size, radius, inset=0.0):
    """Antialiased rounded square on a width x height canvas, supersampled SS times ('L')."""
    m = Image.new('L', (width * SS, height * SS), 0)
    box = [(x + inset) * SS, (y + inset) * SS, (x + size - inset) * SS - 1, (y + size - inset) * SS - 1]
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius * SS, fill=255)
    return m


def icon(source, width, height, size, x, y, radius, shadow, outline):
    canvas = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    if shadow:
        drop, sigma, opacity = shadow
        m = shape(width, height, x, y + drop, size, radius)
        if isinstance(sigma, tuple):
            # Separable kernel on the final pixels, with room around so the edges get filtered too.
            k = len(sigma)
            pad = Image.new('L', (width + 2 * k, height + 2 * k), 0)
            pad.paste(m.reduce(SS), (k, k))
            weights = [a * b for a in sigma for b in sigma]
            m = pad.filter(ImageFilter.Kernel((k, k), weights, sum(weights))).crop((k, k, k + width, k + height))
        else:
            if sigma:
                m = m.filter(ImageFilter.GaussianBlur(sigma * SS))
            m = m.reduce(SS)
        canvas.putalpha(m.point(lambda v: int(v * opacity + 0.5)))

    # One resample from the source straight to the final size keeps the art sharp.
    body = source.resize((size, size), Image.LANCZOS).convert('RGBA')
    if outline:
        # The hairline dark edge of Apple's small icons: half a point wide, black from 72/255 at
        # the top to 104/255 at the bottom, following the rounded corners.
        hair = size / 58.0
        ring = Image.new('L', (size * SS, size * SS), 255)
        ring.paste(0, mask=shape(size, size, 0, 0, size, radius - 1.25 * hair, inset=hair))
        ring = ring.reduce(SS)
        alpha = Image.new('L', (size, size))
        alpha.putdata([v * int(round(72 + 32 * (i // size) / (size - 1))) // 255
                       for i, v in enumerate(ring.tobytes())])
        dark = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        dark.putalpha(alpha)
        body.alpha_composite(dark)

    layer = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    layer.paste(body, (x, y))
    layer.putalpha(shape(width, height, x, y, size, radius).reduce(SS))
    canvas.alpha_composite(layer)
    return canvas


def main(source_path, out_dir):
    source = Image.open(source_path).convert('RGB')
    if source.size[0] != source.size[1]:
        sys.exit('the source icon must be square')
    for name, spec in ICONS.items():
        icon(source, *spec).save(os.path.join(out_dir, name), optimize=True)
        print(name, spec[:2])


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
