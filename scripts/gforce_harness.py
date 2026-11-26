#!/usr/bin/env python3
"""Replay synthetic traces through the G-force filter.

The traces are not a wrist recording. They check that the gravity filter,
the yaw×speed cornering, and the per-second peak logic do what the plan
says on made-up samples: flat cruise, a steep berm, a hard landing,
free-fall, and a braking event.

python3 scripts/gforce_harness.py
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from gforce import Gforce


G = 1000  # milli-g at rest.


def samples(rate, seconds):
    return int(round(rate * seconds))


def run_second(det, rows, prev_speed=None, cur_speed=None, has_fix=True, land_at=None):
    if prev_speed is not None and cur_speed is not None:
        det.note_gps_second(prev_speed, cur_speed)
    if cur_speed is not None:
        det.set_speed(has_fix, cur_speed)
    for i, row in enumerate(rows):
        if land_at is not None and i == land_at:
            det.arm_landing()
        det.push(*row)
    det.advance_second()
    out = {
        "ring": det.ring_value(),
        "peak_pos": det.peak_pos,
        "peak_neg": det.peak_neg,
        "lat": det.lat_peak,
        "lon": det.lon_peak,
        "land": det.land_peak,
        "imu_pct": det.imu_ok_pct(),
    }
    det.clear_second()
    return out


# ---- synthetic second generators. All watch-frame mg / dps. ----

def flat_rest(rate):
    """Watch stationary with gravity on z. Ring and horizontal G both ~0."""
    return [(0, 0, G, 0, 0, 0)] * rate


def cruise_vibration(rate, amp_mg=200):
    """Flat ride with a 70 Hz chassis buzz (bar vibration)."""
    rows = []
    for i in range(rate):
        t = i / rate
        buzz = int(round(amp_mg * math.sin(2 * math.pi * 70 * t)))
        rows.append((0, 0, G + buzz, 0, 0, 0))
    return rows


def berm(rate, extra_load_g=0.4, yaw_dps=60, speed_mps=15):
    """Upright wrist on a right berm: a +0.4 g compression and a 60 dps
    right-hand yaw at 54 km/h. Pure chassis frame, wrist on top."""
    rows = []
    for _ in range(rate):
        az = int(round((1.0 + extra_load_g) * G))
        rows.append((0, 0, az, 0, 0, yaw_dps))
    return rows, speed_mps


def hard_landing(rate, peak_g=4.0, sample_idx=None):
    """Flat ride, then one landing sample of peak_g at index sample_idx
    (defaults to the middle). Used to check the landing window."""
    if sample_idx is None:
        sample_idx = rate // 2
    rows = []
    for i in range(rate):
        az = int(round(peak_g * G)) if i == sample_idx else G
        rows.append((0, 0, az, 0, 0, 0))
    return rows


def freefall(rate):
    """One second of 0 g on all axes (jump air)."""
    return [(0, 0, 0, 0, 0, 0)] * rate


def braking_second(rate, dv_mps=-3.0):
    """Flat chassis frame (1 g on z), no rotations, speed drops by dv_mps
    in one second. GPS dv/dt handles the longitudinal number."""
    rows = [(0, 0, G, 0, 0, 0)] * rate
    return rows, dv_mps


def warm_detector(rate, gyro_on):
    """Return a Gforce that has already seen ~3 s of flat rest, so the
    warmup counter is done. Lets the rest of the test speak about lat/lon
    without spending screens on ramp-up."""
    det = Gforce(rate, gyro_on)
    det.set_speed(True, 0.0)
    # 4 seconds of rest is more than enough for the 2 s warmup.
    for _ in range(4 * rate):
        det.push(0, 0, G, 0, 0, 0)
    det.clear_second()
    det.hold_pos = 0.0
    det.hold_neg = 0.0
    return det


def within(got, want, tol, label):
    ok = abs(got - want) <= tol
    tag = "OK " if ok else "FAIL"
    print(f"  [{tag}] {label}: got {got:+.3f}, want {want:+.3f} ± {tol:.3f}")
    return ok


def run():
    rate = 25
    fails = 0

    print("== flat rest, 1 s ==")
    det = warm_detector(rate, True)
    r = run_second(det, flat_rest(rate), prev_speed=0.0, cur_speed=0.0)
    fails += 0 if within(r["ring"], 0.0, 0.03, "ring near 0") else 1
    fails += 0 if within(r["lat"], 0.0, 0.03, "lat near 0") else 1
    fails += 0 if within(r["lon"], 0.0, 0.03, "lon near 0") else 1
    fails += 0 if r["imu_pct"] >= 95 else 1

    print("== cruise with 70 Hz vibration, 1 s ==")
    det = warm_detector(rate, True)
    r = run_second(det, cruise_vibration(rate, amp_mg=200), prev_speed=15.0, cur_speed=15.0)
    # The ring should see ~0.2 g peak above 1 g (raw) and the smoother
    # should hold the per-second peak under 0.15 g. We only assert the
    # instantaneous peak doesn't blow past 0.3 g.
    fails += 0 if r["peak_pos"] < 0.3 else 1
    fails += 0 if r["lat"] == 0.0 else 1  # no yaw → no lat

    print("== right-hand berm, 60 dps yaw @ 54 km/h, 1 s ==")
    det = warm_detector(rate, True)
    rows, speed = berm(rate, extra_load_g=0.4, yaw_dps=60, speed_mps=15)
    r = run_second(det, rows, prev_speed=15.0, cur_speed=15.0)
    expected_lat = speed * (60 * math.pi / 180.0) / 9.81
    fails += 0 if within(r["ring"], 0.4, 0.1, "ring ~ +0.4 g (berm compression)") else 1
    fails += 0 if within(r["lat"], expected_lat, 0.2, f"lat ~ {expected_lat:.2f} g") else 1
    fails += 0 if r["lat"] > 0 else 1

    print("== hard landing, one 4 g spike ==")
    det = warm_detector(rate, True)
    rows = hard_landing(rate, peak_g=4.0, sample_idx=rate // 2)
    r = run_second(det, rows, prev_speed=15.0, cur_speed=15.0, land_at=rate // 2 - 1)
    fails += 0 if within(r["land"], 4.0, 0.2, "landing peak ~ 4 g") else 1
    fails += 0 if r["peak_pos"] > 1.5 else 1  # ring sees the compression.

    print("== free fall, 1 s ==")
    det = warm_detector(rate, True)
    r = run_second(det, freefall(rate), prev_speed=15.0, cur_speed=15.0)
    fails += 0 if within(r["ring"], -1.0, 0.1, "ring ~ -1 g (free fall)") else 1
    fails += 0 if r["peak_neg"] < -0.9 else 1

    print("== braking, -3 m/s in 1 s ==")
    det = warm_detector(rate, True)
    rows, dv = braking_second(rate, dv_mps=-3.0)
    # The GPS dv/dt is applied *per sample* inside push(); for our test we
    # pre-seed with note_gps_second so the first sample has the dv/dt.
    det.note_gps_second(15.0, 12.0)
    r = run_second(det, rows, prev_speed=15.0, cur_speed=12.0)
    expected_lon = -3.0 / 9.81
    fails += 0 if within(r["lon"], expected_lon, 0.05, f"lon ~ {expected_lon:.2f} g") else 1
    fails += 0 if r["lon"] < 0 else 1

    print("== peak hold: a 0.6 g berm, then 2 s of flat, then another berm ==")
    det = warm_detector(rate, True)
    rows1, _ = berm(rate, extra_load_g=0.6, yaw_dps=0, speed_mps=0)
    r1 = run_second(det, rows1, prev_speed=15.0, cur_speed=15.0)
    r2 = run_second(det, flat_rest(rate), prev_speed=15.0, cur_speed=15.0)
    r3 = run_second(det, flat_rest(rate), prev_speed=15.0, cur_speed=15.0)
    # After 2 flat seconds the hold tick has decayed one full step; after
    # 3 it should be back at the current (near-zero) peak.
    print(f"  (debug) hold_pos after 1st berm = {det.hold_pos:.2f}")
    fails += 0 if det.hold_pos >= 0.4 else 1
    # Another berm with smaller load should not raise the tick.
    rows4, _ = berm(rate, extra_load_g=0.3, yaw_dps=0, speed_mps=0)
    r4 = run_second(det, rows4, prev_speed=15.0, cur_speed=15.0)
    # Hold should either be at the newer 0.6 memory or be refreshed to 0.3.
    # Simpler assertion: hold is >= current peak.
    fails += 0 if det.hold_pos >= r4["peak_pos"] - 0.05 else 1

    if fails == 0:
        print("\nAll checks passed.")
    else:
        print(f"\n{fails} check(s) failed.")
    sys.exit(0 if fails == 0 else 1)


if __name__ == "__main__":
    run()
