# make_info_icons.py <MaterialIcons-Regular.ttf> <MaterialIcons-Regular.codepoints> <client dir>
#
# OldSend's own info buttons, replacing iOS 6's (whose "i" is an italic serif): Material Icons'
# upright "i" in a circle, 22 pt (1x and @2x).
#   InfoButtonLight: white outline circle with a slight shadow, for the navigation bar.
#   InfoButtonDark:  filled grey circle, for device rows.
# Material Icons: Apache-2.0, https://github.com/google/material-design-icons
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

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


def light(px, scale):
    mask = glyph_mask('info_outline', px)
    # iOS 6 bar-button icons: white, with a dark shadow one point above.
    shadow = ImageChops.offset(mask, 0, -scale).point(lambda a: a * 0.45)
    out = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    out.paste((20, 40, 70, 255), (0, 0), shadow)
    out.paste((255, 255, 255, 255), (0, 0), mask)
    return out


def dark(px, scale):
    mask = glyph_mask('info', px)
    out = Image.new('RGBA', (px, px), (88, 88, 94, 0))
    out.putalpha(mask)
    return out


for scale, suffix in ((1, ''), (2, '@2x')):
    px = POINTS * scale
    light(px, scale).save(os.path.join(OUT, 'InfoButtonLight%s.png' % suffix))
    dark(px, scale).save(os.path.join(OUT, 'InfoButtonDark%s.png' % suffix))
print('ok')
