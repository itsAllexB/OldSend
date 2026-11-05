# make_app_icons.py <square source.png> <client dir>
#
# Writes OldSend's app icons at every size iOS 6 uses, with the rounded corners cut out.
# Apps in /Applications are system apps to iOS 6, and it draws their icons exactly as supplied
# (no mask, no gloss), so the corners must be in the PNGs, as in Apple's own and Cydia's icons.
# The source should be square, at least 512 px (1024 px best), with square corners and no gloss.
import os
import sys

from PIL import Image, ImageDraw

SIZES = {
    'Icon.png': 57, 'Icon@2x.png': 114,                 # iPhone home screen
    'Icon-72.png': 72, 'Icon-72@2x.png': 144,           # iPad home screen
    'Icon-Small.png': 29, 'Icon-Small@2x.png': 58,      # Settings, notifications, Spotlight
    'Icon-Small-50.png': 50, 'Icon-Small-50@2x.png': 100,  # iPad Spotlight
}
RADIUS = 10.0 / 57.0   # iOS 6 corner radius relative to the icon size
SS = 8                 # supersampling for smooth corner edges


def rounded(source, size):
    big = source.resize((size * SS, size * SS), Image.LANCZOS)
    mask = Image.new('L', big.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big.size[0] - 1, big.size[1] - 1],
                                           radius=RADIUS * size * SS, fill=255)
    big.putalpha(mask)
    return big.resize((size, size), Image.LANCZOS)


def main(source_path, out_dir):
    source = Image.open(source_path).convert('RGB')
    if source.size[0] != source.size[1]:
        sys.exit('the source icon must be square')
    for name, size in SIZES.items():
        rounded(source, size).save(os.path.join(out_dir, name), optimize=True)
        print(name, size)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
