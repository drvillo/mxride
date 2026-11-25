#!/usr/bin/env python3
"""Replay synthetic accel traces through the jump detector.

The traces are not a wrist recording. They check that the gates in
scripts/jump_detector.py do what the plan says on made-up samples:
clean airs, whoops, a braking bump, and 70 Hz engine vibration.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from jump_detector import JumpDetector

G = 1000


def samples_of(rate, seconds):
    return int(round(seconds * rate))


def ride(z_mg, n, gyro=0):
    return [(0, 0, z_mg, gyro, 0, 0)] * n


def freefall(n, vib=0.0, rate=25, gyro=0, phase=0.0):
    rows = []
    for i in range(n):
        t = phase + i / rate
        z = int(round(vib * math.sin(2 * math.pi * 70.0 * t)))
        rows.append((0, 0, z, gyro, 0, 0))
    return rows


def vibe(n, rate, amp, phase=0.0, gyro=0):
    rows = []
    for i in range(n):
        t = phase + i / rate
        z = int(round(G + amp * math.sin(2 * math.pi * 70.0 * t)))
        rows.append((0, 0, z, gyro, 0, 0))
    return rows


def play(rate, gyro_on, rows, has_fix=True, kmh=40):
    det = JumpDetector(rate, gyro_on)
    det.set_speed(has_fix, kmh)
    batch = rate
    for start in range(0, len(rows), batch):
        chunk = rows[start:start + batch]
        if gyro_on and len(chunk) * 2 < rate:
            det.abort()
            continue
        for ax, ay, az, gx, gy, gz in chunk:
            det.push(ax, ay, az, gx, gy, gz)
    return det


def settle(rate):
    return ride(G, samples_of(rate, 1.0))


def clean_jump(rate, air_s, spike=3500):
    air_n = samples_of(rate, air_s)
    rows = []
    rows += settle(rate)
    rows += freefall(air_n, rate=rate)
    rows += ride(spike, 2)
    rows += settle(rate)
    rows += ride(G, samples_of(rate, 0.5))
    return rows


def whoops(rate):
    rows = settle(rate)
    for _ in range(6):
        rows += freefall(samples_of(rate, 0.15), rate=rate)
        rows += ride(2800, 1)
        rows += ride(G, samples_of(rate, 0.40))
    rows += settle(rate)
    return rows


def braking_bump(rate):
    rows = settle(rate)
    rows += ride(4500, 3)
    rows += ride(G, samples_of(rate, 2.0))
    return rows


def rough(rate, seconds=20.0, amp=600):
    return vibe(samples_of(rate, seconds), rate, amp)


def rough_with_jump(rate, air_s=1.0, amp=600):
    pre = samples_of(rate, 3.0)
    air = samples_of(rate, air_s)
    post = samples_of(rate, 3.0)
    rows = vibe(pre, rate, amp)
    rows += freefall(air, vib=amp, rate=rate, phase=pre / rate)
    rows += ride(3500, 2)
    rows += vibe(post, rate, amp, phase=(pre + air) / rate)
    return rows


def soft_jump(rate, air_s=0.8):
    """0.60 g the whole air, with a 150 deg/s pitch pulse. Accel-only should miss it."""
    n = samples_of(rate, air_s)
    rows = settle(rate)
    rows += freefall(n, rate=rate, gyro=150)
    # keep a 0.60 g bias instead of true freefall
    biased = []
    for ax, ay, az, gx, gy, gz in rows[samples_of(rate, 1.0):samples_of(rate, 1.0) + n]:
        biased.append((ax, ay, 600, gx, gy, gz))
    rows = settle(rate) + biased + ride(3500, 2) + settle(rate)
    return rows


def report_case(name, true_s, det):
    n = len(det.events)
    true_ms = int(round(true_s * 1000))
    if n == 0:
        err = None
        detail = "none"
        if true_ms:
            detail = "none  error n/a (missed %d ms)" % true_ms
    else:
        best = min(det.events, key=lambda ev: abs(ev[0] - true_ms))
        err = best[0] - true_ms
        bits = []
        for ms, score in det.events:
            bits.append("%d ms score %d  error %+d ms" % (ms, score, ms - true_ms))
        detail = ", ".join(bits)
    print("%-28s count %d  %s" % (name, n, detail))
    return n, err


def run_rate(rate):
    print("\n== %d Hz, accelerometer only ==" % rate)
    rows = [
        ("clean 0.3 s", 0.3, clean_jump(rate, 0.3), True, 40),
        ("clean 0.5 s", 0.5, clean_jump(rate, 0.5), True, 40),
        ("clean 1.0 s", 1.0, clean_jump(rate, 1.0), True, 40),
        ("clean 1.5 s", 1.5, clean_jump(rate, 1.5), True, 40),
        ("whoops 0.15 s x6", 0.15, whoops(rate), True, 40),
        ("braking bump", 0.0, braking_bump(rate), True, 40),
        ("rough 70 Hz 20 s", 0.0, rough(rate), True, 40),
        ("rough + 1.0 s jump", 1.0, rough_with_jump(rate, 1.0), True, 40),
        ("1.0 s at 5 km/h", 1.0, clean_jump(rate, 1.0), True, 5),
        ("1.0 s no fix", 1.0, clean_jump(rate, 1.0), False, 0),
    ]
    out = []
    for name, true_s, trace, fix, kmh in rows:
        det = play(rate, False, trace, fix, kmh)
        n, err = report_case(name, true_s, det)
        out.append((name, n, err))
    print("\n== %d Hz, accelerometer + gyroscope ==" % rate)
    soft = play(rate, True, soft_jump(rate), True, 40)
    report_case("soft 0.8 s + gyro pulse", 0.8, soft)
    soft_off = play(rate, False, soft_jump(rate), True, 40)
    report_case("soft 0.8 s, gyro off", 0.8, soft_off)
    return out


def main():
    run_rate(25)
    run_rate(100)


if __name__ == "__main__":
    main()
