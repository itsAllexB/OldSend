# make_info_icons.py <MaterialIcons-Regular.ttf> <MaterialIcons-Regular.codepoints> <client dir>
#
# OldSend's own info button for the Send page's device rows (iOS 6's has an italic serif "i"):
#   InfoButtonDark: Material Icons' filled circle with an upright "i", 22 pt, 1x and @2x.
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


def dark(px, scale):
    mask = glyph_mask('info', px)
    out = Image.new('RGBA', (px, px), (88, 88, 94, 0))
    out.putalpha(mask)
    return out


for scale, suffix in ((1, ''), (2, '@2x')):
    px = POINTS * scale
    dark(px, scale).save(os.path.join(OUT, 'InfoButtonDark%s.png' % suffix))
print('ok')
