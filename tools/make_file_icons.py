# make_file_icons.py <MaterialIcons-Regular.ttf> <MaterialIcons-Regular.codepoints> <out dir> [preview.png]
#
# Draws OldSend's file-type icons (client/icons/*.png) at 1x (32 px) and @2x (64 px) as vector art:
# a white page with a folded corner, a coloured Material Icons symbol for the kind of file, and the
# extension label. Replaces the original 32 px Mac OS X document icons, which have no Retina source.
# Material Icons: Apache-2.0, https://github.com/google/material-design-icons
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT, CODES_PATH, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
PREVIEW = sys.argv[4] if len(sys.argv) > 4 else None
CODES = dict(l.split() for l in open(CODES_PATH))
LABEL_FONT = next((p for p in (r'C:\Windows\Fonts\arialbd.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
                               '/System/Library/Fonts/Helvetica.ttc') if os.path.exists(p)), None)

# kind: (symbol, colour)
KINDS = {
    'image':   ('image',          (52, 168, 83)),
    'video':   ('movie',          (142, 68, 173)),
    'audio':   ('music_note',     (230, 81, 0)),
    'archive': ('folder_zip',     (121, 85, 72)),
    'disk':    ('album',          (96, 125, 139)),
    'code':    ('code',           (25, 118, 210)),
    'web':     ('language',       (216, 67, 21)),
    'config':  ('settings',       (96, 125, 139)),
    'text':    ('description',    (84, 110, 122)),
    'doc':     ('description',    (21, 101, 192)),
    'sheet':   ('table_chart',    (46, 125, 50)),
    'slides':  ('slideshow',      (239, 108, 0)),
    'pdf':     ('picture_as_pdf', (211, 47, 47)),
    'data':    ('storage',        (0, 121, 107)),
    'blank':   (None,             (144, 164, 174)),
}
# icon file -> (kind, label)
ICONS = {
    'jpeg': ('image', 'JPEG'), 'png': ('image', 'PNG'), 'gif': ('image', 'GIF'), 'bmp': ('image', 'BMP'),
    'tiff': ('image', 'TIFF'), 'ico': ('image', 'ICO'), 'image': ('image', ''),
    'video': ('video', ''), 'mpeg': ('video', 'MPEG'), '3gpp': ('video', '3GPP'), 'flash': ('video', 'FLASH'),
    'mp3': ('audio', 'MP3'), 'aac': ('audio', 'AAC'), 'aiff': ('audio', 'AIFF'), 'wav': ('audio', 'WAV'),
    'm4r': ('audio', 'M4R'), 'm3u': ('audio', 'M3U'), 'mp2': ('audio', 'MP2'), 'sound': ('audio', ''),
    'text': ('text', 'TXT'), 'rtf': ('doc', 'RTF'), 'log': ('text', 'LOG'),
    'html': ('web', 'HTML'), 'css': ('code', 'CSS'), 'js': ('code', 'JS'),
    'config': ('config', 'CONFIG'), 'xib': ('code', 'XIB'),
    'zip': ('archive', 'ZIP'), 'tar': ('archive', 'TAR'), 'gz': ('archive', 'GZ'), 'bz2': ('archive', 'BZ2'),
    'tbz2': ('archive', 'TBZ2'), 'tgz': ('archive', 'TGZ'), 'compressed': ('archive', ''),
    'pdf': ('pdf', 'PDF'), 'doc': ('doc', 'DOC'), 'ppt': ('slides', 'PPT'), 'spreadsheet': ('sheet', 'XLS'),
    'pages': ('doc', 'PAGES'), 'numbers': ('sheet', 'NUMBERS'), 'keynote': ('slides', 'KEY'),
    'c': ('code', 'C'), 'cpp': ('code', 'C++'), 'h': ('code', 'H'), 'm': ('code', 'M'), 'java': ('code', 'JAVA'),
    'sqlite3': ('data', 'SQLITE'), 'diskimage': ('disk', 'DMG'),
    'empty': ('blank', ''),
}
SS = 8


def glyph(d, name, cx, cy, size, colour):
    font = ImageFont.truetype(FONT, int(size))
    d.text((cx, cy), chr(int(CODES[name], 16)), font=font, fill=colour, anchor='mm')


def page(px, kind, label):
    S = px * SS
    u = S / 32.0  # one 1x pixel
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    symbol, colour = KINDS[kind]
    x0, y0, x1, y1, fold = 5.5 * u, 2 * u, 26.5 * u, 30 * u, 6.5 * u
    outline = (176, 186, 197, 255)
    body = [(x0, y0), (x1 - fold, y0), (x1, y0 + fold), (x1, y1), (x0, y1)]
    d.polygon(body, fill=outline)
    inset = 1.0 * u
    d.polygon([(x0 + inset, y0 + inset), (x1 - fold - inset * 0.4, y0 + inset), (x1 - inset, y0 + fold + inset * 0.4),
               (x1 - inset, y1 - inset), (x0 + inset, y1 - inset)], fill=(255, 255, 255, 255))
    d.polygon([(x1 - fold, y0), (x1 - fold, y0 + fold), (x1, y0 + fold)], fill=(214, 221, 229, 255))
    d.line([(x1 - fold, y0), (x1 - fold, y0 + fold), (x1, y0 + fold)], fill=outline, width=int(u))
    has_label = bool(label)
    if symbol:
        gy = (y0 + y1) / 2 - (3.2 * u if has_label else 0)
        glyph(d, symbol, (x0 + x1) / 2, gy + 0.5 * u, (12.5 if has_label else 15) * u, colour + (255,))
    if has_label:
        band_y0, band_y1 = y1 - 9.5 * u, y1 - 3 * u
        d.rounded_rectangle([x0 - 2.5 * u, band_y0, x1 + 2.5 * u, band_y1], radius=1.5 * u, fill=colour + (255,))
        size = 5.6 * u if len(label) <= 4 else (4.6 * u if len(label) <= 6 else 3.9 * u)
        f = ImageFont.truetype(LABEL_FONT, int(size))
        d.text(((x0 + x1) / 2, (band_y0 + band_y1) / 2 + 0.2 * u), label, font=f, fill=(255, 255, 255, 255), anchor='mm')
    return im.resize((px, px), Image.LANCZOS)


def folder(px):
    S = px * SS
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    glyph(ImageDraw.Draw(im), 'folder', S / 2, S / 2 + S * 0.02, S * 1.05, (88, 150, 222, 255))
    return im.resize((px, px), Image.LANCZOS)


os.makedirs(OUT, exist_ok=True)
made = {}
for name, (kind, label) in ICONS.items():
    for px, suffix in ((32, ''), (64, '@2x')):
        im = page(px, kind, label)
        im.save(os.path.join(OUT, f'{name}{suffix}.png'))
        made[(name, px)] = im
for px, suffix in ((32, ''), (64, '@2x')):
    made[('folder', px)] = folder(px)
    made[('folder', px)].save(os.path.join(OUT, f'folder{suffix}.png'))
print(len(made) // 2, 'icons')

if PREVIEW:
    names = sorted(n for n, _ in made if _ == 64)
    cols = 10
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * 84, rows * 84), (239, 239, 244, 255))
    for i, n in enumerate(names):
        im = made[(n, 64)]
        sheet.paste(im, ((i % cols) * 84 + 10, (i // cols) * 84 + 10), im)
    sheet.save(PREVIEW)
