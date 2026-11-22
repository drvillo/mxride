#!/usr/bin/env python3
"""Write BMFont .fnt/.png resources for the dash. White ink on black."""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "resources" / "fonts"

SEVEN = {
    "0": (1, 1, 1, 1, 1, 1, 0),
    "1": (0, 1, 1, 0, 0, 0, 0),
    "2": (1, 1, 0, 1, 1, 0, 1),
    "3": (1, 1, 1, 1, 0, 0, 1),
    "4": (0, 1, 1, 0, 0, 1, 1),
    "5": (1, 0, 1, 1, 0, 1, 1),
    "6": (1, 0, 1, 1, 1, 1, 1),
    "7": (1, 1, 1, 0, 0, 0, 0),
    "8": (1, 1, 1, 1, 1, 1, 1),
    "9": (1, 1, 1, 1, 0, 1, 1),
    "-": (0, 0, 0, 0, 0, 0, 1),
}

LABELS = {
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
}


def hbar(img, x, y, w, t):
    for yy in range(y, y + t):
        for xx in range(x, x + w):
            img.putpixel((xx, yy), 255)


def vbar(img, x, y, h, t):
    for yy in range(y, y + h):
        for xx in range(x, x + t):
            img.putpixel((xx, yy), 255)


def draw_seven(img, x, y, height, mask):
    t = 6
    w = 40
    mid = y + height // 2
    bot = y + height
    if mask[0]:
        hbar(img, x + t, y, w - 2 * t, t)
    if mask[1]:
        vbar(img, x + w - t, y + t, height // 2 - t, t)
    if mask[2]:
        vbar(img, x + w - t, mid, height // 2 - t, t)
    if mask[3]:
        hbar(img, x + t, bot - t, w - 2 * t, t)
    if mask[4]:
        vbar(img, x, mid, height // 2 - t, t)
    if mask[5]:
        vbar(img, x, y + t, height // 2 - t, t)
    if mask[6]:
        hbar(img, x + t, mid - t // 2, w - 2 * t, t)
    return w


def write_fnt(path, face, size, line_h, base, scale_w, scale_h, page, chars):
    lines = [
        f'info face="{face}" size={size} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=0 padding=0,0,0,0 spacing=1,1 outline=0',
        f"common lineHeight={line_h} base={base} scaleW={scale_w} scaleH={scale_h} pages=1 packed=0 alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0",
        f'page id=0 file="{page}"',
        f"chars count={len(chars)}",
    ]
    for ch, box in chars:
        x, y, w, h, xo, yo, adv = box
        lines.append(
            f"char id={ord(ch):<3} x={x:<4} y={y:<3} width={w:<3} height={h:<3} xoffset={xo:<2} yoffset={yo:<2} xadvance={adv:<3} page=0 chnl=15"
        )
    lines.append("kernings count=0")
    path.write_text("\n".join(lines) + "\n")


def digits():
    cell_w = 48
    cell_h = 74
    order = list("0123456789-")
    img = Image.new("L", (cell_w * len(order), cell_h), 0)
    chars = []
    for i, ch in enumerate(order):
        ox = i * cell_w + 4
        draw_seven(img, ox, 2, 70, SEVEN[ch])
        chars.append((ch, (i * cell_w, 0, cell_w - 2, cell_h, 1, 0, cell_w)))
    img.save(OUT / "digits_0.png")
    write_fnt(
        OUT / "digits.fnt",
        "MxDigits",
        70,
        cell_h,
        70,
        img.width,
        img.height,
        "digits_0.png",
        chars,
    )


def labels():
    scale = 3
    gw, gh = 5 * scale, 7 * scale
    cell_w, cell_h = gw + 6, gh + 6
    order = list(" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ/.:-")
    img = Image.new("L", (cell_w * len(order), cell_h), 0)
    chars = []
    for i, ch in enumerate(order):
        rows = LABELS[ch]
        ox = i * cell_w + 2
        oy = 2
        for ry, row in enumerate(rows):
            for rx, bit in enumerate(row):
                if bit == "1":
                    for dy in range(scale):
                        for dx in range(scale):
                            img.putpixel((ox + rx * scale + dx, oy + ry * scale + dy), 255)
        chars.append((ch, (i * cell_w, 0, cell_w - 1, cell_h, 1, 0, cell_w)))
    img.save(OUT / "labels_0.png")
    write_fnt(
        OUT / "labels.fnt",
        "MxLabels",
        gh,
        cell_h,
        gh,
        img.width,
        img.height,
        "labels_0.png",
        chars,
    )


def launcher_image(size):
    icon = Image.new("RGB", (size, size), (0, 0, 0))
    yellow = (255, 214, 0)
    for y in range(size):
        for x in range(size):
            gx = x * 40.0 / size
            gy = y * 40.0 / size
            left = abs(gx - 12) < 3 and gy >= 10
            right = abs(gx - 28) < 3 and gy >= 10
            mid = abs((gx - 20) * 2 + (gy - 28)) < 4 and 14 <= gy <= 30
            top = 10 <= gy <= 14 and 9 <= gx <= 31
            if left or right or mid or top:
                icon.putpixel((x, y), yellow)
    return icon


def launcher():
    base = ROOT / "resources" / "drawables"
    base.mkdir(parents=True, exist_ok=True)
    launcher_image(40).save(base / "launcher.png")
    # 416 faces want 60 px, 454 and 466 want 65. A matching bitmap avoids a scaled icon.
    for family, size in (("round-416x416", 60), ("round-454x454", 65), ("round-466x466", 65)):
        folder = ROOT / ("resources-" + family) / "drawables"
        folder.mkdir(parents=True, exist_ok=True)
        launcher_image(size).save(folder / "launcher.png")
        (folder / "drawables.xml").write_text(
            "<drawables>\n    <bitmap id=\"LauncherIcon\" filename=\"launcher.png\" />\n</drawables>\n"
        )


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    digits()
    labels()
    launcher()


if __name__ == "__main__":
    main()
