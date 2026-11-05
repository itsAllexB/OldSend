# make_info_icons.py <MaterialIcons-Regular.ttf> <MaterialIcons-Regular.codepoints> <client dir>
#
# OldSend's own info buttons, replacing iOS 6's (whose "i" is an italic serif), 1x and @2x:
#   InfoButtonDark: Material Icons' filled circle with an upright "i", 22 pt, for device rows.
#   InfoBarItem:    a bold upright "i" for a bordered navigation-bar button (Receive page), in
#                   the weight of the system "+" next to it on the Send page; iOS draws bar-item
#                   images as white masks with its own emboss, so only the shape matters.
# Material Icons: Apache-2.0, https://github.com/google/material-design-icons
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT, CODES_PATH, OUT = sys.argv[1:4]
CODES = dict(l.split() for l in open(CODES_PATH))
POINTS = 22
SS = 8


def glyph_mask(name, px):
    big = Image.new('L', (px * SS, px * SS), 0)
    font = ImageFont.truetype(FONT, px * SS)
    ImageDraw.Draw(big).text((px * SS / 2, px * SS / 2), chr(int(CODES[name], 16)),
                             font=font, fill=255, anchor='mm')
    return big.resize((px, px), Image.LANCZOS)


def bar_item(scale):
    # 13 x 20 pt: a round dot over a stem with rounded ends, 4 pt wide like the "+". iOS sizes
    # an image bar button from the image plus fixed padding (it ignores `width`), and 13 pt
    # makes it as wide as the system + button.
    px = 20 * scale
    wide = 13 * scale
    big = Image.new('L', (wide * SS, px * SS), 0)
    d = ImageDraw.Draw(big)
    u = scale * SS            # one point
    width = 4.0 * u
    cx = wide * SS / 2.0
    d.ellipse([cx - 2.3 * u, 1.5 * u, cx + 2.3 * u, 6.1 * u], fill=255)           # dot
    d.rounded_rectangle([cx - width / 2, 8.0 * u, cx + width / 2, 18.5 * u],      # stem
                        radius=width / 2, fill=255)
    out = Image.new('RGBA', (wide, px), (255, 255, 255, 0))
    out.putalpha(big.resize((wide, px), Image.LANCZOS))
    return out


def dark(px, scale):
    mask = glyph_mask('info', px)
    out = Image.new('RGBA', (px, px), (88, 88, 94, 0))
    out.putalpha(mask)
    return out


for scale, suffix in ((1, ''), (2, '@2x')):
    px = POINTS * scale
    bar_item(scale).save(os.path.join(OUT, 'InfoBarItem%s.png' % suffix))
    dark(px, scale).save(os.path.join(OUT, 'InfoButtonDark%s.png' % suffix))
print('ok')
