"""Reference G-force math. source/Gforce.mc is the same filter and gates.

Keep the constants and the push/advance steps in lockstep with the Monkey C
file. Floats are in g (1 g = 9.81 m/s^2). Gyro is in deg/s.
"""

import math


DEG2RAD = math.pi / 180.0
G_MS2 = 9.81
WARMUP_FACTOR = 2  # seconds of near-rest samples before trusting gravity.


class Gforce:
    def __init__(self, rate, gyro_on):
        self.rate = rate if rate > 0 else 25
        self.gyro_on = gyro_on
        self.dt = 1.0 / self.rate
        self.tau = 2.0 if gyro_on else 3.0
        self.window = 5 if rate >= 50 else 3
        self.box = [0.0] * 5
        self.box_i = 0
        self.box_n = 0
        self.box_sum = 0.0
        self.gx = 0.0
        self.gy = 0.0
        self.gz = 1.0
        self.has_fix = False
        self.speed_mps = 0.0
        self.gps_dvdt_g = 0.0
        self.peak_pos = 0.0
        self.peak_neg = 0.0
        self.lat_peak = 0.0
        self.lon_peak = 0.0
        self.combined_peak = 0.0
        self.hold_pos = 0.0
        self.hold_pos_ms = 0
        self.hold_neg = 0.0
        self.hold_neg_ms = 0
        self.land_peak = 0.0
        self.land_last = 0.0
        self.land_window = max(1, (500 * self.rate) // 1000)
        self.land_left = 0
        self.land_live = False
        self.land_show_ms = 0
        self.imu_ok = 0
        self.imu_total = 0
        self.warmup_left = self.rate * WARMUP_FACTOR

    def set_speed(self, has_fix, speed_mps):
        self.has_fix = has_fix
        self.speed_mps = speed_mps

    def note_gps_second(self, prev_speed_mps, cur_speed_mps):
        self.gps_dvdt_g = (cur_speed_mps - prev_speed_mps) / G_MS2

    def arm_landing(self):
        self.land_left = self.land_window
        self.land_live = True
        self.land_last = 0.0

    def push(self, ax_mg, ay_mg, az_mg, gx_dps, gy_dps, gz_dps):
        self.imu_total += 1
        ax = ax_mg / 1000.0
        ay = ay_mg / 1000.0
        az = az_mg / 1000.0
        mag2 = max(1e-6, ax * ax + ay * ay + az * az)
        mag = math.sqrt(mag2)
        sm = self._smooth(mag2)
        sm_mag = math.sqrt(sm)
        if self.gyro_on:
            wx = gx_dps * DEG2RAD * self.dt
            wy = gy_dps * DEG2RAD * self.dt
            wz = gz_dps * DEG2RAD * self.dt
            ngx = self.gx - (wy * self.gz - wz * self.gy)
            ngy = self.gy - (wz * self.gx - wx * self.gz)
            ngz = self.gz - (wx * self.gy - wy * self.gx)
            self.gx, self.gy, self.gz = ngx, ngy, ngz
        if 0.7 < mag < 1.3:
            alpha = min(1.0, self.dt / self.tau)
            self.gx = (1.0 - alpha) * self.gx + alpha * (ax / mag)
            self.gy = (1.0 - alpha) * self.gy + alpha * (ay / mag)
            self.gz = (1.0 - alpha) * self.gz + alpha * (az / mag)
            if self.warmup_left > 0:
                self.warmup_left -= 1
            self.imu_ok += 1
        g2 = self.gx ** 2 + self.gy ** 2 + self.gz ** 2
        if g2 < 1e-6:
            self.gx, self.gy, self.gz = 0.0, 0.0, 1.0
            g2 = 1.0
        gnorm = math.sqrt(g2)
        self.gx /= gnorm
        self.gy /= gnorm
        self.gz /= gnorm
        dot = ax * self.gx + ay * self.gy + az * self.gz
        ring = dot - 1.0
        ring_sm = sm_mag - 1.0
        pos_candidate = max(ring, ring_sm)
        neg_candidate = min(ring, ring_sm)
        if pos_candidate > self.peak_pos:
            self.peak_pos = pos_candidate
        if neg_candidate < self.peak_neg:
            self.peak_neg = neg_candidate
        if self.land_live:
            if mag > self.land_last:
                self.land_last = mag
            self.land_left -= 1
            if self.land_left <= 0:
                self.land_live = False
                if self.land_last > self.land_peak:
                    self.land_peak = self.land_last
                self.land_show_ms = 3000
        linx = ax - dot * self.gx
        liny = ay - dot * self.gy
        linz = az - dot * self.gz
        horiz = math.sqrt(max(1e-6, linx * linx + liny * liny + linz * linz))
        lat = 0.0
        if self.warmup_left <= 0 and self.gyro_on and self.has_fix and self.speed_mps >= 2.8:
            yaw = (gx_dps * DEG2RAD * self.gx +
                   gy_dps * DEG2RAD * self.gy +
                   gz_dps * DEG2RAD * self.gz)
            lat = self.speed_mps * yaw / G_MS2
        lon = self.gps_dvdt_g if self.warmup_left <= 0 else 0.0
        if abs(lat) > abs(self.lat_peak):
            self.lat_peak = lat
        if abs(lon) > abs(self.lon_peak):
            self.lon_peak = lon
        if horiz > self.combined_peak:
            self.combined_peak = horiz

    def advance_second(self):
        if self.peak_pos > self.hold_pos:
            self.hold_pos = self.peak_pos
            self.hold_pos_ms = 3000
        elif self.hold_pos_ms > 0:
            self.hold_pos_ms -= 1000
            if self.hold_pos_ms <= 0:
                self.hold_pos = self.peak_pos
                self.hold_pos_ms = 0
        if self.peak_neg < self.hold_neg:
            self.hold_neg = self.peak_neg
            self.hold_neg_ms = 3000
        elif self.hold_neg_ms > 0:
            self.hold_neg_ms -= 1000
            if self.hold_neg_ms <= 0:
                self.hold_neg = self.peak_neg
                self.hold_neg_ms = 0
        if self.land_show_ms > 0:
            self.land_show_ms = max(0, self.land_show_ms - 1000)

    def clear_second(self):
        self.peak_pos = 0.0
        self.peak_neg = 0.0
        self.lat_peak = 0.0
        self.lon_peak = 0.0
        self.combined_peak = 0.0

    def ring_value(self):
        if -self.peak_neg > self.peak_pos:
            return self.peak_neg
        return self.peak_pos

    def imu_ok_pct(self):
        if self.imu_total <= 0:
            return 0
        pct = (self.imu_ok * 100) // self.imu_total
        return max(0, min(100, pct))

    def _smooth(self, v):
        if self.box_n < self.window:
            self.box[self.box_n] = v
            self.box_n += 1
            self.box_sum += v
            return self.box_sum / self.box_n
        old = self.box[self.box_i]
        self.box[self.box_i] = v
        self.box_i = (self.box_i + 1) % self.window
        self.box_sum += v - old
        return self.box_sum / self.window
