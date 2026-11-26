#!/usr/bin/env python3
"""Phase-0 sensor diagnostic report.

Reads a FIT file saved by an MX Ride diagnostic build (DIAG_ENABLED = true in
source/Diag.mc) and prints the questions the phase-0 ride is supposed to
answer:

  - configured vs delivered accel / gyro / GPS rate
  - per-axis min and max in mg / dps, with a saturation / sign-wrap verdict
  - distribution of total |a|, with suggested float and landing thresholds
  - gyro magnitude distribution
  - sample counts, batch counts, record-second counts

The developer-field layout comes from source/Diag.mc and from the pre-existing
jump fields in source/RideSession.mc. All diagnostic ids live at >= 10, so the
script also runs on a FIT written by an older build (it will just report
"no diagnostic fields" for the parts that are missing).

Usage:
    python3 scripts/phase0_fit_report.py path/to/ride.fit [more.fit ...]

Dependency:
    pip install fitparse      # pure-Python FIT parser
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Any, Iterable

try:
    import fitparse  # type: ignore
except ImportError:
    sys.stderr.write(
        "fitparse not installed. Run:\n    pip install fitparse\n"
    )
    sys.exit(1)


# Keep these in lockstep with source/Diag.mc.
RECORD_FIELDS = {
    5:  ("jump_last_ms",  "ms",   "u16"),
    10: ("diag_samples",  "count","u16"),
    11: ("diag_gps",      "count","u8"),
    12: ("diag_a_peak",   "mg",   "u16"),
    13: ("diag_a_min",    "mg",   "u16"),
    14: ("diag_g_peak",   "dps",  "u16"),
    15: ("diag_flags",    "mask", "u8"),
}

SESSION_FIELDS = {
    0:  ("max_speed",              "km/h",  "f32"),
    2:  ("jump_count",             "count", "u16"),
    3:  ("jump_air_ms",            "ms",    "u32"),
    4:  ("jump_longest_ms",        "ms",    "u16"),
    6:  ("jump_recent_ms",         "ms",    "u16[]"),
    20: ("diag_accel_rate_cfg",    "Hz",    "u8"),
    21: ("diag_gyro_rate_cfg",     "Hz",    "u8"),
    22: ("diag_accel_rate_actual", "Hz",    "f32"),
    23: ("diag_gyro_rate_actual",  "Hz",    "f32"),
    24: ("diag_gps_rate_actual",   "Hz",    "f32"),
    25: ("diag_batches_total",     "count", "u32"),
    26: ("diag_record_seconds",    "s",     "u32"),
    27: ("diag_ax_lo", "mg", "s16"),
    28: ("diag_ax_hi", "mg", "s16"),
    29: ("diag_ay_lo", "mg", "s16"),
    30: ("diag_ay_hi", "mg", "s16"),
    31: ("diag_az_lo", "mg", "s16"),
    32: ("diag_az_hi", "mg", "s16"),
    33: ("diag_gx_lo", "dps", "s16"),
    34: ("diag_gx_hi", "dps", "s16"),
    35: ("diag_gy_lo", "dps", "s16"),
    36: ("diag_gy_hi", "dps", "s16"),
    37: ("diag_gz_lo", "dps", "s16"),
    38: ("diag_gz_hi", "dps", "s16"),
    39: ("diag_accel_clip", "count", "u32"),
    40: ("diag_accel_wrap", "count", "u32"),
    41: ("diag_gyro_clip",  "count", "u32"),
    42: ("diag_a_hist",     "count", "u16[]"),
    43: ("diag_g_hist",     "count", "u16[]"),
}

LAP_FIELDS = {
    1: ("lap_max_speed",    "km/h",  "f32"),
    7: ("jump_count",       "count", "u16"),
    8: ("jump_air_ms",      "ms",    "u32"),
    9: ("jump_longest_ms",  "ms",    "u16"),
}

HIST_BIN_MG = 500
GYRO_BIN_DPS = 250

FLAG_ACCEL_CLIP = 0x01
FLAG_ACCEL_WRAP = 0x02
FLAG_GYRO_CLIP  = 0x04
FLAG_SHORT_BATCH = 0x08
FLAG_NO_BATCH   = 0x10


def iter_dev_fields(message: Any) -> Iterable[tuple[int | None, str, Any]]:
    """Yield (developer field id, name, value) pairs from a fitparse message."""
    for f in message.fields:
        if not getattr(f, "is_dev", False):
            continue
        dev = getattr(f, "field", None)
        if dev is None:
            continue
        yield (getattr(dev, "field_definition_number", None), f.name, f.value)


def collect(path: Path) -> dict[str, Any]:
    fit = fitparse.FitFile(str(path))
    records: list[dict[int, Any]] = []
    sessions: list[dict[int, Any]] = []
    laps: list[dict[int, Any]] = []
    file_id: dict[str, Any] = {}
    plain_records = 0
    for msg in fit.get_messages():
        mt = msg.name
        if mt == "record":
            plain_records += 1
            row: dict[int, Any] = {}
            for fid, _name, value in iter_dev_fields(msg):
                if fid is not None:
                    row[fid] = value
            records.append(row)
        elif mt == "session":
            row = {}
            for fid, _name, value in iter_dev_fields(msg):
                if fid is not None:
                    row[fid] = value
            sessions.append(row)
        elif mt == "lap":
            row = {}
            for fid, _name, value in iter_dev_fields(msg):
                if fid is not None:
                    row[fid] = value
            laps.append(row)
        elif mt == "file_id":
            for f in msg.fields:
                file_id[f.name] = f.value
    return {
        "file_id": file_id,
        "records": records,
        "sessions": sessions,
        "laps": laps,
        "plain_records": plain_records,
    }


def fmt_pct(a: float, b: float) -> str:
    if b <= 0:
        return "n/a"
    return "%.1f%%" % (100.0 * a / b)


def _get(row: dict[int, Any], fid: int, default: Any = None) -> Any:
    if fid not in row:
        return default
    return row[fid]


def _to_list(v: Any) -> list[int]:
    if v is None:
        return []
    if isinstance(v, (list, tuple)):
        return list(v)
    return [v]


def rates_block(session: dict[int, Any], record_seconds: int, records_n: int) -> str:
    out: list[str] = []
    accel_cfg = _get(session, 20)
    gyro_cfg = _get(session, 21)
    accel_act = _get(session, 22)
    gyro_act = _get(session, 23)
    gps_act = _get(session, 24)
    batches = _get(session, 25)
    rec_sec = _get(session, 26)
    out.append("Configured rates (reported by the watch):")
    out.append("  accel: %s Hz" % ("?" if accel_cfg is None else accel_cfg))
    out.append("  gyro : %s Hz" % ("?" if gyro_cfg is None else gyro_cfg))
    out.append("Actually delivered (samples per recorded second):")
    out.append("  accel: %s Hz" % ("?" if accel_act is None else "%.2f" % accel_act))
    out.append("  gyro : %s Hz" % ("?" if gyro_act is None else "%.2f" % gyro_act))
    out.append("  GPS  : %s Hz" % ("?" if gps_act is None else "%.3f" % gps_act))
    out.append("Record-type messages in the FIT:   %d" % records_n)
    out.append("Sensor batches reported by diag:   %s" % ("?" if batches is None else batches))
    out.append("Record seconds reported by diag:   %s" % ("?" if rec_sec is None else rec_sec))
    if accel_cfg and accel_act is not None and accel_cfg > 0:
        out.append("Accel delivery / configured ratio:  %s" % fmt_pct(accel_act, accel_cfg))
    if gyro_cfg and gyro_act is not None and gyro_cfg > 0:
        out.append("Gyro  delivery / configured ratio:  %s" % fmt_pct(gyro_act, gyro_cfg))
    return "\n".join(out)


def axes_block(session: dict[int, Any]) -> str:
    def row(name: str, lo_id: int, hi_id: int, unit: str, cap: int) -> str:
        lo = _get(session, lo_id)
        hi = _get(session, hi_id)
        if lo is None and hi is None:
            return "  %-7s   -    -    -" % name
        verdict = ""
        if lo is not None and hi is not None:
            if abs(lo) >= cap or abs(hi) >= cap:
                verdict = "  (saturated at cap %d %s)" % (cap, unit)
            span = max(abs(lo), abs(hi))
            verdict += "  span %d %s" % (span, unit)
        return "  %-7s %8s %8s %s" % (name, lo, hi, verdict)
    lines = ["Per-axis extremes seen during the whole ride:"]
    lines.append("  axis       min       max")
    lines.append(row("accel X", 27, 28, "mg", 7500))
    lines.append(row("accel Y", 29, 30, "mg", 7500))
    lines.append(row("accel Z", 31, 32, "mg", 7500))
    lines.append(row("gyro X", 33, 34, "dps", 1800))
    lines.append(row("gyro Y", 35, 36, "dps", 1800))
    lines.append(row("gyro Z", 37, 38, "dps", 1800))
    a_clip = _get(session, 39)
    a_wrap = _get(session, 40)
    g_clip = _get(session, 41)
    lines.append("")
    lines.append("Saturation / wrap counts (session totals):")
    lines.append("  accel near-cap samples (|axis| >= 7500 mg):  %s" % a_clip)
    lines.append("  accel sign-wrap events (flip across cap):    %s" % a_wrap)
    lines.append("  gyro  near-cap samples (|axis| >= 1800 dps): %s" % g_clip)
    verdicts: list[str] = []
    if isinstance(a_clip, int) and a_clip > 0:
        verdicts.append("Accel is being capped. Real range exceeds the sensor's cap.")
    if isinstance(a_wrap, int) and a_wrap > 0:
        verdicts.append("Accel SIGN WRAP detected -- raw values roll over past the cap, not clip.")
    if isinstance(g_clip, int) and g_clip > 0:
        verdicts.append("Gyro is being capped. Real range exceeds the sensor's cap.")
    if not verdicts:
        verdicts.append("No saturation or wrap events seen with the current ride.")
    lines.append("")
    lines.append("Verdicts:")
    for v in verdicts:
        lines.append("  - " + v)
    return "\n".join(lines)


def hist_block(session: dict[int, Any]) -> str:
    bins = _to_list(_get(session, 42))
    lines = ["Distribution of total |a| (0.5 g bins, last bin is overflow):"]
    if not bins:
        lines.append("  (no a_hist field in FIT)")
    else:
        total = sum(b for b in bins if b is not None)
        max_bin = max((b for b in bins if b is not None), default=0)
        bar_w = 40
        running = 0
        sub_g_bin = 0
        thresh_bin = 0
        for i, count in enumerate(bins):
            if count is None:
                count = 0
            lo = i * HIST_BIN_MG / 1000.0
            hi = (i + 1) * HIST_BIN_MG / 1000.0
            label = "%4.1f..%4.1f g" % (lo, hi)
            if i == len(bins) - 1:
                label = "%4.1f g+     " % lo
            bar = "#" * int(round(bar_w * (count / max_bin))) if max_bin else ""
            lines.append(
                "  %s  %8d  %-6s  %s"
                % (label, count, fmt_pct(count, total), bar)
            )
            running += count
            if lo < 0.45 and running > 0.01 * total:
                # cumulative low-g samples
                sub_g_bin = max(sub_g_bin, i)
            if lo >= 2.0 and count > 0 and thresh_bin == 0:
                thresh_bin = i
        p99_sum = 0
        p99_bin = len(bins) - 1
        for i in range(len(bins) - 1, -1, -1):
            p99_sum += bins[i] or 0
            if p99_sum >= 0.01 * total:
                p99_bin = i
                break
        lo = bins[0] or 0
        verdict: list[str] = []
        verdict.append(
            "  float gate (jump detector enters at |a| < 0.45 g): %s of all samples are under 0.45 g"
            % fmt_pct(lo, total)
        )
        verdict.append(
            "  landing (jump detector leaves at |a| > 0.80 g): heavier bins visible up to bin %d (%.1f g+)"
            % (p99_bin, p99_bin * HIST_BIN_MG / 1000.0)
        )
        lines.append("")
        lines.extend(verdict)
    return "\n".join(lines)


def gyro_hist_block(session: dict[int, Any]) -> str:
    bins = _to_list(_get(session, 43))
    lines = ["Distribution of total |gyro| (250 dps bins, last is overflow):"]
    if not bins:
        lines.append("  (no g_hist field in FIT)")
        return "\n".join(lines)
    total = sum(b for b in bins if b is not None)
    max_bin = max((b for b in bins if b is not None), default=0)
    bar_w = 40
    for i, count in enumerate(bins):
        if count is None:
            count = 0
        lo = i * GYRO_BIN_DPS
        hi = (i + 1) * GYRO_BIN_DPS
        label = "%4d..%4d dps" % (lo, hi)
        if i == len(bins) - 1:
            label = "%4d dps+     " % lo
        bar = "#" * int(round(bar_w * (count / max_bin))) if max_bin else ""
        lines.append(
            "  %s  %8d  %-6s  %s"
            % (label, count, fmt_pct(count, total), bar)
        )
    return "\n".join(lines)


def records_block(records: list[dict[int, Any]]) -> str:
    if not records:
        return "Per-record diag fields: (no record messages)"
    sample_counts = [r.get(10) for r in records if r.get(10) is not None]
    gps_counts = [r.get(11) for r in records if r.get(11) is not None]
    a_peaks = [r.get(12) for r in records if r.get(12) is not None]
    a_mins = [r.get(13) for r in records if r.get(13) is not None]
    g_peaks = [r.get(14) for r in records if r.get(14) is not None]
    flags = [r.get(15, 0) or 0 for r in records]
    lines = ["Per-record diag summary (%d records):" % len(records)]
    if sample_counts:
        lines.append(
            "  accel samples / record: min %d, median %d, max %d, mean %.1f"
            % (
                min(sample_counts),
                sorted(sample_counts)[len(sample_counts) // 2],
                max(sample_counts),
                sum(sample_counts) / len(sample_counts),
            )
        )
    if gps_counts:
        lines.append(
            "  GPS updates / record:   min %d, median %d, max %d, mean %.2f"
            % (
                min(gps_counts),
                sorted(gps_counts)[len(gps_counts) // 2],
                max(gps_counts),
                sum(gps_counts) / len(gps_counts),
            )
        )
    if a_peaks:
        lines.append(
            "  peak |a| / record (mg): min %d, median %d, max %d"
            % (min(a_peaks), sorted(a_peaks)[len(a_peaks) // 2], max(a_peaks))
        )
    if a_mins:
        lines.append(
            "  min  |a| / record (mg): min %d, median %d, max %d"
            % (min(a_mins), sorted(a_mins)[len(a_mins) // 2], max(a_mins))
        )
    if g_peaks:
        lines.append(
            "  peak |gyro| / record (dps): min %d, median %d, max %d"
            % (min(g_peaks), sorted(g_peaks)[len(g_peaks) // 2], max(g_peaks))
        )
    lines.append("  flag-seconds counts:")
    masks = {
        FLAG_ACCEL_CLIP: "accel near-cap (bit 0)",
        FLAG_ACCEL_WRAP: "accel sign wrap (bit 1)",
        FLAG_GYRO_CLIP:  "gyro near-cap  (bit 2)",
        FLAG_SHORT_BATCH:"short sensor batch (bit 3)",
        FLAG_NO_BATCH:   "no sensor batch that second (bit 4)",
    }
    for bit, name in masks.items():
        c = sum(1 for f in flags if f & bit)
        lines.append("    %-32s %d of %d (%s)" % (name, c, len(flags), fmt_pct(c, len(flags))))
    return "\n".join(lines)


def jump_block(session: dict[int, Any]) -> str:
    lines = ["Jump fields (recap, same as 1.0.5):"]
    lines.append("  jump_count       : %s" % _get(session, 2))
    lines.append("  jump_air_ms      : %s" % _get(session, 3))
    lines.append("  jump_longest_ms  : %s" % _get(session, 4))
    recent = _to_list(_get(session, 6))
    nz = [r for r in recent if r]
    if nz:
        lines.append("  jump_recent_ms   : %s" % ", ".join(str(r) for r in nz))
    lines.append("  max_speed (km/h) : %s" % _get(session, 0))
    return "\n".join(lines)


def report(path: Path) -> None:
    data = collect(path)
    sessions = data["sessions"]
    records = data["records"]
    laps = data["laps"]
    print("=" * 72)
    print("FIT: %s" % path)
    if data["file_id"]:
        print("file_id: %s" % {
            k: v for k, v in data["file_id"].items() if k in ("time_created", "type", "manufacturer", "product_name", "serial_number")
        })
    print("Record messages: %d" % data["plain_records"])
    print("Sessions:        %d" % len(sessions))
    print("Laps:            %d" % len(laps))
    print()
    if not sessions:
        print("(no session message -- ride may have been discarded)")
        return
    session = sessions[0]
    rec_sec = _get(session, 26) or len(records)
    print(rates_block(session, rec_sec, len(records)))
    print()
    print(axes_block(session))
    print()
    print(hist_block(session))
    print()
    print(gyro_hist_block(session))
    print()
    print(records_block(records))
    print()
    print(jump_block(session))
    if laps:
        print()
        print("Laps: %d" % len(laps))
        for i, lap in enumerate(laps, 1):
            print(
                "  lap %d: max %s km/h, %s jumps, air %s ms, longest %s ms"
                % (
                    i,
                    _get(lap, 1),
                    _get(lap, 7),
                    _get(lap, 8),
                    _get(lap, 9),
                )
            )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("fit", nargs="+", type=Path, help="one or more .fit files")
    args = ap.parse_args()
    for f in args.fit:
        if not f.exists():
            print("missing: %s" % f, file=sys.stderr)
            continue
        report(f)
    return 0


if __name__ == "__main__":
    sys.exit(main())
