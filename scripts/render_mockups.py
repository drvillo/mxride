#!/usr/bin/env python3
"""Render preview PNGs of the 1.0.6 main page.

Uses the same per-size table and ring geometry that source/RideView.mc
uses, and the bitmap fonts from resources/fonts (via scripts/gen_fonts.py).
Not a watch screenshot, a faithful geometric preview of what the Monkey C
code will draw. The Connect IQ simulator cannot run in this headless env
(libwebkit2gtk-4.0 and ~15 other Ubuntu 22.04-only libs are missing).

Outputs to /opt/cursor/artifacts/ (or the first argv if given), one per
state × device. States mirror the agreed contact sheet.
"""

import math
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(ROOT / "scripts"))

# ---- bitmap font tables, copied verbatim from gen_fonts.py ----

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

# ---- draw helpers ----

def draw_label(draw, cx, cy, text, color, scale=3, justify="center"):
    """Draw text using the 5×7 LABELS bitmap font. Letter spacing 1 px.
    Matches resources/fonts/labels.fnt, scale 3 → 15 px tall glyphs."""
    glyphs = [LABELS.get(c, LABELS[" "]) for c in text.upper()]
    gh = 7 * scale
    gw = 5 * scale
    advance = gw + scale  # 1-px gap at scale 3.
    total_w = advance * len(glyphs) - scale
    if justify == "center":
        x = cx - total_w // 2
    elif justify == "right":
        x = cx - total_w
    else:
        x = cx
    y = cy - gh // 2
    for g in glyphs:
        for ry, row in enumerate(g):
            for rx, bit in enumerate(row):
                if bit == "1":
                    draw.rectangle(
                        [x + rx * scale, y + ry * scale,
                         x + (rx + 1) * scale - 1, y + (ry + 1) * scale - 1],
                        fill=color,
                    )
        x += advance


def draw_seven(draw, cx, top, digits, color, cell_w=48, cell_h=70, t=6):
    """Draw 7-segment digits. Matches resources/fonts/digits.fnt."""
    total_w = cell_w * len(digits)
    x0 = cx - total_w // 2
    for ch in digits:
        mask = SEVEN.get(ch, SEVEN["0"])
        x = x0
        y = top
        w = 40
        mid = y + cell_h // 2
        bot = y + cell_h
        if mask[0]:
            draw.rectangle([x + t, y, x + w - t, y + t - 1], fill=color)
        if mask[1]:
            draw.rectangle([x + w - t, y + t, x + w - 1, mid - 1], fill=color)
        if mask[2]:
            draw.rectangle([x + w - t, mid, x + w - 1, bot - t - 1], fill=color)
        if mask[3]:
            draw.rectangle([x + t, bot - t, x + w - t, bot - 1], fill=color)
        if mask[4]:
            draw.rectangle([x, mid, x + t - 1, bot - t - 1], fill=color)
        if mask[5]:
            draw.rectangle([x, y + t, x + t - 1, mid - 1], fill=color)
        if mask[6]:
            draw.rectangle([x + t, mid - t // 2, x + w - t, mid + t // 2 - 1], fill=color)
        x0 += cell_w


# ---- ring geometry (mirrors RideView.mc) ----

def ring_width_for(side):
    if side >= 450:
        return 14
    if side >= 400:
        return 12
    if side >= 280:
        return 11
    if side >= 260:
        return 10
    return 9


def ring_outer_inset(side):
    return 10 if side >= 400 else 3


def _arc(draw, cx, cy, r, start_deg, end_deg, color, width):
    """drawArc with Monkey C angle convention (0=east, 90=north).

    PIL uses (0=east, CW). Garmin says CCW. To mimic Monkey C CCW with a
    start > end, we feed PIL the equivalent CW range. Monkey C degrees
    rotate CCW from east; PIL rotates CW from east. Convert by negating.
    """
    # Convert Monkey C (CCW from east) → PIL (CW from east): angle_pil = -angle_mc.
    s = -start_deg
    e = -end_deg
    if s > e:
        s, e = e, s
    bbox = [cx - r, cy - r, cx + r, cy + r]
    draw.arc(bbox, s, e, fill=color, width=width)


def draw_g_ring(img, draw, size, ring_g, hold_pos, hold_neg, lat_g, lon_g):
    outer = size // 2 - ring_outer_inset(size)
    rw = ring_width_for(size)
    mid_r = outer - rw // 2
    cx = size // 2
    cy = size // 2
    # Base unlit segments on both halves.
    for i in range(30):
        start = 89.5 - 6 * i
        end = 84.5 - 6 * i
        _arc(draw, cx, cy, mid_r, start, end, "#555555", rw)
        start_n = 90.5 + 6 * i
        end_n = 95.5 + 6 * i
        _arc(draw, cx, cy, mid_r, start_n, end_n, "#555555", rw)
    # Lit segments.
    inst_pos = max(0, min(30, int(ring_g * 10 + 0.5))) if ring_g > 0 else 0
    inst_neg = max(0, min(30, int(-ring_g / 0.0333 + 0.5))) if ring_g < 0 else 0
    for i in range(inst_pos):
        start = 89.5 - 6 * i
        end = 84.5 - 6 * i
        _arc(draw, cx, cy, mid_r, start, end, "#00FF00", rw)
    for i in range(inst_neg):
        start = 90.5 + 6 * i
        end = 95.5 + 6 * i
        _arc(draw, cx, cy, mid_r, start, end, "#FF0000", rw)
    # Peak-hold ticks. Short radial white line at the peak position on
    # the outside edge of the ring.
    def _tick(value, positive):
        if positive:
            step = min(30.0, value * 10.0)
            angle = 90.0 - 6.0 * step
        else:
            step = min(30.0, value / 0.0333)
            angle = 90.0 + 6.0 * step
        rad = math.radians(angle)
        r1 = outer + 2
        r2 = outer - rw - 2
        x1 = cx + r1 * math.cos(rad)
        y1 = cy - r1 * math.sin(rad)
        x2 = cx + r2 * math.cos(rad)
        y2 = cy - r2 * math.sin(rad)
        draw.line([x1, y1, x2, y2], fill="#FFFFFF", width=2)

    if hold_pos > 0.01:
        _tick(hold_pos, True)
    if hold_neg > 0.01:
        _tick(hold_neg, False)
    # Zero mark at 12.
    draw.line([cx, cy - outer - 1, cx, cy - outer + rw + 2], fill="#FFFFFF", width=2)
    # Inner yellow horizontal G arc.
    mag = math.sqrt(lat_g ** 2 + lon_g ** 2)
    if mag > 0.1:
        felt_angle = math.degrees(math.atan2(-lon_g, lat_g))
        half_sweep = min(60.0, mag * 30.0)
        inner_r = mid_r - rw // 2 - 10
        _arc(draw, cx, cy, inner_r,
             felt_angle - half_sweep, felt_angle + half_sweep,
             "#FFAA00", 2)


# ---- compositor ----

def draw_dots(draw, size, active):
    """Four 7×7 page dots. On the ride page they sit inside the ring."""
    y = size // 2 + size // 2 - ring_outer_inset(size) - ring_width_for(size) - 10
    x = size // 2 - 16
    for i in range(4):
        color = "#FFAA00" if i == active else "#555555"
        draw.rectangle([x + i * 12, y, x + i * 12 + 6, y + 6], fill=color)


def render(size, state):
    img = Image.new("RGB", (size, size), "#000000")
    draw = ImageDraw.Draw(img)
    # Mask to circle shape via a black circle *around* the inner one; we
    # just leave the corners black, which is what the watch face does.
    cx = size // 2
    cy = size // 2

    # Draw the G-ring behind the content.
    draw_g_ring(img, draw, size,
                ring_g=state["ring"], hold_pos=state["hold_pos"],
                hold_neg=state["hold_neg"], lat_g=state["lat"],
                lon_g=state["lon"])

    # Content stack. For a 260 px face we start at y=14 like rideTop.
    if size >= 400:
        y = (size - 260) // 2
    elif size >= 260:
        y = 36
    else:
        y = 14
    draw_label(draw, cx, y + 6, "REC", "#FFAA00", scale=3)
    y_digit = y + 18
    speed = state["speed"]
    draw_seven(draw, cx, y_digit, f"{speed:02d}", "#FFFF00")
    y_text = y_digit + 76
    # H line.
    hr_color = state.get("hr_color", "#FFFFFF")
    draw_label(draw, cx, y_text, f"H {state['hr']}", hr_color, scale=3)
    y_text += 26
    # timer distance.
    draw_label(draw, cx, y_text, state["timer"], "#FFFFFF", scale=3)
    y_text += 26
    # G / LAND / AIR line.
    draw_label(draw, cx, y_text, state["g_line"], state["g_color"], scale=3)

    # Dots inside the ring, ride page active (index 0).
    draw_dots(draw, size, 0)

    return img


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/opt/cursor/artifacts")
    out.mkdir(parents=True, exist_ok=True)

    states = [
        dict(name="berm",      speed=42, hr=156, hr_color="#FFAA00",
             timer="4:12 2.3", g_line="0.4 G", g_color="#00FF00",
             ring=0.4, hold_pos=0.4, hold_neg=0.0, lat=0.9, lon=0.0),
        dict(name="landing",   speed=38, hr=171, hr_color="#FF0000",
             timer="4:31 2.5", g_line="LAND 2.9", g_color="#00FF00",
             ring=2.6, hold_pos=2.9, hold_neg=0.0, lat=0.0, lon=0.0),
        dict(name="air",       speed=45, hr=168, hr_color="#FF0000",
             timer="4:30 2.5", g_line="AIR 0.6", g_color="#FF0000",
             ring=-0.9, hold_pos=0.0, hold_neg=1.0, lat=0.0, lon=0.0),
        dict(name="braking",   speed=51, hr=160, hr_color="#FFAA00",
             timer="5:02 2.9", g_line="0.1 G", g_color="#00FF00",
             ring=0.1, hold_pos=0.3, hold_neg=0.0, lat=0.0, lon=-0.7),
    ]

    sizes = [240, 260, 280, 416, 454, 466]
    for size in sizes:
        tiles = []
        for st in states:
            img = render(size, st)
            path = out / f"mxride-1.0.6-ring-{size}px-{st['name']}.png"
            img.save(path)
            tiles.append(img)
        # Contact sheet.
        gap = 8
        sheet = Image.new("RGB", (size * 4 + gap * 3 + gap * 2, size + gap * 2 + 24), "#000000")
        sx = gap
        for tile in tiles:
            sheet.paste(tile, (sx, gap))
            sx += size + gap
        sheet_path = out / f"mxride-1.0.6-ring-{size}px-contact-sheet.png"
        sheet.save(sheet_path)
        print("wrote", sheet_path)


if __name__ == "__main__":
    main()
