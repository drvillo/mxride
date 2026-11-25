"""Reference jump detector. source/JumpDetector.mc is the same state machine.

Keep the constants and the push/abort steps in lockstep with the Monkey C file.
Numbers are milli-g and degrees per second. Sum of squares, no sqrt.
"""

CLAMP_MG = 8000
CLAMP_DPS = 2000
ENTER_SQ = 450 * 450
SOFT_SQ = 700 * 700
LEAVE_SQ = 800 * 800
LAND_AXIS = 2000
GYRO_PULSE_SQ = 80 * 80
FLOOR_MS = 300
FLOOR_GYRO_MS = 250
SPIKE_KEEP_MIN_MS = 200
SPIKE_KEEP_MAX_MS = 400
DEBOUNCE_MS = 300
LAND_WINDOW_MS = 200
SPEED_MIN_KMH = 8


def _clamp(value, limit):
    if value > limit:
        return limit
    if value < -limit:
        return -limit
    return value


class JumpDetector:
    def __init__(self, rate, gyro_on):
        self.rate = rate if rate > 0 else 1
        self.gyro_on = gyro_on
        self.window = 5 if rate >= 50 else 3
        self.need = self.window
        self.box = [0, 0, 0, 0, 0]
        self.box_i = 0
        self.box_n = 0
        self.box_sum = 0
        self.state = 0  # 0 ground, 1 air, 2 landing
        self.quiet = 0
        self.soft = 0
        self.air_samples = 0
        self.since_samples = (DEBOUNCE_MS * self.rate) // 1000
        self.debounce_samples = max(1, (DEBOUNCE_MS * self.rate) // 1000)
        self.land_samples = 0
        self.land_need = max(1, (LAND_WINDOW_MS * self.rate) // 1000)
        self.land_flag = False
        self.gyro_pulse = False
        self.min_ss = 2000000000
        self.peak_gyro = 0
        self.peak_axis = 0
        self.has_fix = False
        self.kmh = 0
        self.count = 0
        self.total_ms = 0
        self.longest_ms = 0
        self.last_ms = 0
        self.last_score = 0
        self.lap_count = 0
        self.lap_air_ms = 0
        self.lap_longest_ms = 0
        self.recent = [0] * 32
        self.recent_n = 0
        self.record_ms = 0
        self.events = []

    def set_speed(self, has_fix, kmh):
        self.has_fix = has_fix
        self.kmh = kmh

    def _smooth(self, ss):
        if self.box_n < self.window:
            self.box[self.box_n] = ss
            self.box_n += 1
            self.box_sum += ss
            return self.box_sum // self.box_n
        old = self.box[self.box_i]
        self.box[self.box_i] = ss
        self.box_i = (self.box_i + 1) % self.window
        self.box_sum += ss - old
        return self.box_sum // self.window

    def abort(self):
        self.state = 0
        self.quiet = 0
        self.soft = 0
        self.since_samples = 0
        self.box_n = 0
        self.box_sum = 0
        self.box_i = 0

    def _remember(self, ms):
        if self.recent_n < 32:
            self.recent[self.recent_n] = ms
            self.recent_n += 1
            return
        for i in range(31):
            self.recent[i] = self.recent[i + 1]
        self.recent[31] = ms

    def _finish(self):
        ms = (self.air_samples * 1000) // self.rate
        floor = FLOOR_GYRO_MS if self.gyro_pulse else FLOOR_MS
        ok = ms >= floor or (self.land_flag and SPIKE_KEEP_MIN_MS <= ms < SPIKE_KEEP_MAX_MS)
        if self.has_fix and self.kmh < SPEED_MIN_KMH:
            ok = False
        if not ok:
            return False
        score = 0
        if self.min_ss < ENTER_SQ:
            score += 2
        if self.gyro_pulse:
            score += 2
        if self.land_flag:
            score += 1
        if (not self.has_fix) or self.kmh >= SPEED_MIN_KMH:
            score += 1
        if ms >= 500:
            score += 2
        self.count += 1
        self.total_ms += ms
        if ms > self.longest_ms:
            self.longest_ms = ms
        self.last_ms = ms
        self.last_score = score
        self.lap_count += 1
        self.lap_air_ms += ms
        if ms > self.lap_longest_ms:
            self.lap_longest_ms = ms
        self._remember(ms)
        self.record_ms = ms
        self.events.append((ms, score))
        return True

    def push(self, ax, ay, az, gx, gy, gz):
        ax = _clamp(ax, CLAMP_MG)
        ay = _clamp(ay, CLAMP_MG)
        az = _clamp(az, CLAMP_MG)
        ss = ax * ax + ay * ay + az * az
        sm = self._smooth(ss)
        gss = 0
        if self.gyro_on:
            gx = _clamp(gx, CLAMP_DPS)
            gy = _clamp(gy, CLAMP_DPS)
            gz = _clamp(gz, CLAMP_DPS)
            gss = gx * gx + gy * gy + gz * gz
        axis = ax
        if ay > axis:
            axis = ay
        if az > axis:
            axis = az
        if -ax > axis:
            axis = -ax
        if -ay > axis:
            axis = -ay
        if -az > axis:
            axis = -az
        accepted = False
        if self.state == 0:
            if self.since_samples < self.debounce_samples:
                self.since_samples += 1
                self.quiet = 0
                self.soft = 0
            elif sm < ENTER_SQ:
                self.quiet += 1
                self.soft = 0
            elif self.gyro_on and sm < SOFT_SQ and gss >= GYRO_PULSE_SQ:
                self.soft += 1
                self.quiet = 0
            else:
                self.quiet = 0
                self.soft = 0
            if self.state == 0 and (self.quiet >= self.need or self.soft >= self.need):
                self.state = 1
                self.air_samples = self.need
                self.gyro_pulse = self.soft >= self.need
                self.min_ss = sm
                self.peak_gyro = gss
                self.peak_axis = axis
                self.land_flag = axis >= LAND_AXIS
                self.quiet = 0
                self.soft = 0
        elif self.state == 1:
            if gss >= GYRO_PULSE_SQ:
                self.gyro_pulse = True
            if sm < self.min_ss:
                self.min_ss = sm
            if axis > self.peak_axis:
                self.peak_axis = axis
            if axis >= LAND_AXIS:
                self.land_flag = True
            if sm > LEAVE_SQ:
                self.state = 2
                self.land_samples = 0
            else:
                self.air_samples += 1
        else:
            if axis >= LAND_AXIS:
                self.land_flag = True
            self.land_samples += 1
            if self.land_samples >= self.land_need:
                accepted = self._finish()
                self.state = 0
                self.since_samples = 0
                self.quiet = 0
                self.soft = 0
        return accepted

    def reset_lap(self):
        self.lap_count = 0
        self.lap_air_ms = 0
        self.lap_longest_ms = 0

    def take_record(self):
        ms = self.record_ms
        self.record_ms = 0
        return ms
