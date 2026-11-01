"""Génère toutes les icônes de l'application Solea (Android, iOS, web).

Le soleil reprend exactement le dessin du logo de l'app (SunPainter dans
lib/ui/widgets/common.dart) : disque central, 8 rayons arrondis, dégradé
jaune → orange, posé sur un fond brun nuit avec un halo chaud.

Usage (depuis app/) : python3 tool/make_icons.py   (nécessite Pillow)
"""

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)

# Couleurs de la marque (lib/core/theme.dart).
SUN = [(0.0, (0xFF, 0xC9, 0x3C)), (0.55, (0xF7, 0x94, 0x1D)), (1.0, (0xEE, 0x6A, 0x1F))]
BG_TOP = (0x33, 0x24, 0x19)
BG_BOTTOM = (0x14, 0x0E, 0x0B)
GLOW = (0xF7, 0x94, 0x1D)

MASTER = 2048  # rendu haute définition puis réduction (anticrénelage)


def _lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _gradient(stops, t):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return _lerp(c0, c1, (t - t0) / (t1 - t0) if t1 > t0 else 0)
    return stops[-1][1]


def diagonal_gradient(size, stops):
    """Dégradé du coin haut gauche vers le coin bas droit."""
    small = 256
    img = Image.new('RGB', (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            px[x, y] = _gradient(stops, (x + y) / (2 * (small - 1)))
    return img.resize((size, size), Image.BICUBIC)


def sun_mask(size, radius, center=None):
    """Masque du soleil (même géométrie que SunPainter)."""
    cx, cy = center or (size / 2, size / 2)
    r = radius
    m = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(m)
    disc = r * 0.44
    d.ellipse([cx - disc, cy - disc, cx + disc, cy + disc], fill=255)
    w = r * 0.15
    for i in range(8):
        a = i * math.pi / 4 - math.pi / 2
        x0, y0 = cx + math.cos(a) * r * 0.64, cy + math.sin(a) * r * 0.64
        x1, y1 = cx + math.cos(a) * r * 0.9, cy + math.sin(a) * r * 0.9
        d.line([x0, y0, x1, y1], fill=255, width=round(w))
        for x, y in ((x0, y0), (x1, y1)):  # bouts arrondis
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=255)
    return m


def sun_layer(size, radius):
    """Soleil en dégradé avec un léger reflet, sur fond transparent."""
    mask = sun_mask(size, radius)
    # Dégradé jaune (haut gauche) → orange (bas droit), resserré sur le soleil
    # pour que le jaune se voie bien sur le disque.
    small = 256
    grad = Image.new('RGB', (small, small))
    px = grad.load()
    k = size / small
    span = radius * 0.5
    for y in range(small):
        for x in range(small):
            t = ((x + y) * k / 2 - (size / 2 - span / 1.0)) / (2 * span)
            px[x, y] = _gradient(SUN, min(1.0, max(0.0, t)))
    color = grad.resize((size, size), Image.BICUBIC)
    # Reflet doux en haut à gauche du disque.
    hl = Image.new('L', (size, size), 0)
    hd = ImageDraw.Draw(hl)
    hr = radius * 0.30
    hx, hy = size / 2 - radius * 0.14, size / 2 - radius * 0.16
    hd.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=70)
    hl = hl.filter(ImageFilter.GaussianBlur(radius * 0.12))
    color = Image.composite(Image.new('RGB', (size, size), (255, 244, 214)), color, hl)
    layer = color.convert('RGBA')
    layer.putalpha(mask)
    return layer


def background(size):
    """Fond brun nuit avec halo chaud derrière le soleil."""
    bg = diagonal_gradient(size, [(0, BG_TOP), (1, BG_BOTTOM)]).convert('RGBA')
    glow = Image.new('L', (size, size), 0)
    gd = ImageDraw.Draw(glow)
    gr = size * 0.36
    c = size / 2
    gd.ellipse([c - gr, c - gr, c + gr, c + gr], fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.12))
    bg = Image.composite(Image.new('RGBA', (size, size), GLOW + (255,)), bg, glow)
    return bg


def sun_shadow(size, radius):
    """Lueur orangée sous le soleil (effet lumineux)."""
    m = sun_mask(size, radius).filter(ImageFilter.GaussianBlur(radius * 0.08))
    m = m.point(lambda v: v * 0.55)
    layer = Image.new('RGBA', (size, size), GLOW + (0,))
    layer.putalpha(m)
    return layer


def full_icon(sun_ratio):
    """Icône carrée pleine (iOS, maskable, base des autres)."""
    s = MASTER
    radius = s / 2 * sun_ratio
    img = background(s)
    img.alpha_composite(sun_shadow(s, radius))
    img.alpha_composite(sun_layer(s, radius))
    return img


def rounded(img, corner_ratio=0.225):
    s = img.size[0]
    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=s * corner_ratio, fill=255)
    out = img.copy()
    out.putalpha(ImageChops.multiply(out.getchannel('A'), mask))
    return out


def foreground(sun_ratio):
    """Avant-plan transparent de l'icône adaptative Android."""
    s = MASTER
    radius = s / 2 * sun_ratio
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    img.alpha_composite(sun_shadow(s, radius))
    img.alpha_composite(sun_layer(s, radius))
    return img


def save(img, rel, size, opaque=False):
    path = os.path.join(APP, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = img.resize((size, size), Image.LANCZOS)
    if opaque:
        out = out.convert('RGB')  # l'App Store refuse la transparence
    out.save(path, optimize=True)


def main():
    full = full_icon(0.60)            # icône carrée (iOS)
    maskable = full_icon(0.50)        # zone sûre des icônes masquées (cercle de 80 %)
    legacy = rounded(full_icon(0.62))  # Android < 8 et web : carré arrondi
    fg = foreground(0.54)             # icône adaptative : zone sûre de 66 dp sur 108 dp
    bg = background(MASTER)           # fond de l'icône adaptative (halo compris)

    # Android
    for d, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        save(legacy, f'android/app/src/main/res/mipmap-{d}/ic_launcher.png', px)
    for d, px in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}.items():
        save(fg, f'android/app/src/main/res/mipmap-{d}/ic_launcher_foreground.png', px)
        save(bg, f'android/app/src/main/res/mipmap-{d}/ic_launcher_background.png', px, opaque=True)

    # iOS (tailles de Contents.json)
    ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for name in os.listdir(os.path.join(APP, ios)):
        if name.endswith('.png'):
            px = Image.open(os.path.join(APP, ios, name)).size[0]
            save(full, f'{ios}/{name}', px, opaque=True)

    # Web
    save(legacy, 'web/favicon.png', 32)
    save(legacy, 'web/icons/Icon-192.png', 192)
    save(legacy, 'web/icons/Icon-512.png', 512)
    save(maskable, 'web/icons/Icon-maskable-192.png', 192)
    save(maskable, 'web/icons/Icon-maskable-512.png', 512)


if __name__ == '__main__':
    main()
