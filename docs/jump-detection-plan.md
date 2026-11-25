# Jump count and air time

Proposal only. Nothing in this document is implemented.

Read against GitHub `drvillo/mxride` `main` at `106b0cc`, plus the release-build change on top of it (app 1.0.4). That tree is the same ride app: one `RideSession`, three pages, FIT developer fields `max_speed` (id 0, session) and `lap_max_speed` (id 1, lap). `Sensor` is imported and used only for `Sensor.getInfo().heartRate`. Positioning is `enableLocationEvents` at the continuous rate. There is no accelerometer listener.

The owner's real watch is a fēnix 6. An earlier draft of this plan treated the 125964-byte `.prg` as 5108 bytes short of a 131072-byte cap. That reading is wrong. The compiler's 131072 is code plus data (plus a few bytes of permissions and exceptions). The symbol table that fills an unstripped `.prg` is not part of the check, and fēnix 6 has no `prg_limit` in the SDK device list, so the file length is not checked. A release build of this tree (`-r -O 2`) is 23308 bytes on disk, with 11519 bytes of code and 1848 bytes of data, 13367 total, 10.2% of 131072. About 118 KB of code and data is still free. fēnix 7 on the same flags is 17852 bytes on disk, 8675 code and 2026 data, 10701 of 786432.

## What changed in this revision

The 5 KB budget was the reason for several cuts. Those cuts are reopened. The ones that stay closed stay closed for a sensor or physics reason.

| Decision | Then | Now |
| --- | --- | --- |
| Gyroscope | Off, unless a later test proved it was needed | On, when `getMaxSampleRateForSensorType(:gyroscope)` is at least 25. It is a rotation check beside the accelerometer, not a Kalman filter. |
| Higher-rate filtering | Avoided, because a Hoolan-style detector was assumed not to fit | Use the rate the watch returns. A short boxcar is worth it at 50–100 Hz. At 25 Hz a longer filter does not un-alias the engine. |
| Heavier classifier | A four-integer state machine only | Same state machine, plus a score from duration, minimum magnitude, landing peak, gyro peak, and speed. No model file and no on-device training. |
| Barometer | Not a trigger | Still not a trigger and still not a timer. On an air longer than about 1.5 s, a 1 Hz altitude step is a confidence flag only. |
| Jump height | Out | Still out. `g t² / 8` is a few lines and would be the wrong shape for a motocross jump. Size was never the real objection. |
| Per-jump FIT | Session totals only, last 16 air times in RAM | Session and lap totals, one record field so the jump shows up on the activity timeline, and a session array of the last 32 air times. Not one field per jump. |
| Fourth page, 300 ms floor, speed gate, no second font | Kept | Kept. None of these were about the 5 KB. |

## Recommendation

Ship one accelerometer state machine, with the gyroscope as a second vote on watches that actually provide it.

- Count a jump only while the session is recording.
- Store that jump's air time.
- Store, per session and per lap, the count, the sum of air time, and the longest air time.
- Also write the air time onto the FIT record for the second the jump ended, and keep the last 32 air times in a session array.
- Show count, last air time, total, and longest on a new fourth page. Leave the 240/260/280 layout of pages 1–3 alone.
- Call `getMaxSampleRateForSensorType` for `:accelerometer` and `:gyroscope` when the recording starts. `getMaxSampleRate` can change across `onActive` / `onInactive`, so do not cache it at app launch. Request that rate. Do not hard-code 100, and do not request the magnetometer.
- Ignore events shorter than 300 ms unless the gyro confirmation is present, in which case the floor can drop to 250 ms. Whoops under that stay out of scope.
- Do not show a jump height.

The first code change, before any threshold is frozen, is a probe on the real fēnix 6: print both max rates, and log one second of magnitude and gyro magnitude across a known jump. The simulator has reported 25 Hz on hardware that can do more, and it will not reproduce handlebar vibration.

## What the watches actually expose

High-rate motion is `Sensor.registerSensorDataListener`. Axes are milli-g (1000 = 1 g). Gyro axes are degrees per second. The listener period is an integer number of seconds, maximum 4. The callback receives `period × sampleRate` samples. At 25 Hz and a period of 1, that is one batch of 25 samples per second. There is no smaller period. A jump that crosses the batch boundary has to be carried in a few integers.

`Sensor.getInfo()` and `enableSensorEvents` are a different path. Garmin documents that those events are 1 Hz. One sample a second cannot time a 0.4 s jump. The 1 Hz timer already in `MxRideApp` stays the UI timer. It is not the detector.

`AccelerometerData.power` is documented as "vector power" in milli-g, without a formula. Pitch and roll are optional and call `atan2`. Do not request power, pitch, or roll. Timestamps on the sample arrays are API 5.1.1. fēnix 6 is Connect IQ 3.4, so those arrays are null there. Time a jump by sample count divided by the rate you were actually given. On a newer watch, timestamps are worth enabling once both sensors are on, because the fēnix 8 firmware note below shows the two sensors can drift.

Gyroscope samples are API 3.3.0. The Connect IQ device list for `GyroscopeData` includes the fēnix 6 family, 7 family, 8 family, fēnix E, and 9 family. The fēnix 6 product spec also lists a gyroscope, an accelerometer, and a barometric altimeter. Listing a type is not a sample rate.

### Rates

| Stream | What is known | What to request |
| --- | --- | --- |
| Accelerometer | 25 Hz is the rate every one of these watches can be asked for. SDK 6.3.0 added 50 and 100 Hz on some hardware. A 2023 fēnix 7 Pro report of "max rate is 25 Hz" was answered by Garmin as a simulator device-config bug, with the claim that the real watch should still accept the higher rate. A forum post the same year said a fēnix 6 beta had gained 100 Hz. Neither is a measurement from this owner's watch. A fēnix 8 47 mm on firmware 23.39 delivered exactly 100 Hz accel and gyro; firmware 24.x delivered about 103 Hz accel and 102.7 Hz gyro. | `getMaxSampleRateForSensorType(:accelerometer)` at the start of the recording. Use that number. |
| Gyroscope | Same API, symbol `:gyroscope`. Hoolan requires 100 Hz accel and gyro and marks the fēnix 6 Pro family as GPS-only, jumps pending. They mark fēnix 7, 8, and E as jump-capable. fēnix 9 is not on that list. That is their support matrix, not a rate. | Same getter. Enable it when the result is at least 25. If it returns 0 or the symbol is missing, run accel-only. |
| Magnetometer | Up to 50 Hz in the 6.3.0 notes | Leave it off. Heading already comes from GPS. |
| Barometer / altitude | The fēnix 6 manual says the watch collects pressure continuously for its own altimeter. Connect IQ exposes altitude through the 1 Hz `Sensor.Info` path, already filtered. | Not a timer. See the confidence flag below. |
| GPS | `Position.enableLocationEvents(LOCATION_CONTINUOUS)`. The API example is once per second. | Plan on 1 Hz. SatIQ does not raise the callback rate. The app already allows a ride with no fix. |

### fēnix 8 firmware 24.x, if both sensors are on

A kite session on a fēnix 8 47 mm, firmware 24.2, requested 100 Hz for both sensors. The accelerometer ran about 0.5 samples/s faster than the gyroscope. The listener still handed the app equal counts, so accel samples fell behind, and about once every 3 minutes it threw away ~1 s of accelerometer data (21 drops in 71 minutes, 2100 samples). Firmware 23.x on the same watch, and a Forerunner 255 worn in the same session, stayed at exactly 100 Hz with no drops. A fēnix 8 Pro and an Enduro 3 on 24.x showed the same kind of split.

If MX Ride turns both sensors on, pair sample `i` of accel with sample `i` of gyro only inside the callback that delivered them. Do not assume the pairing survives to the next callback. If a batch is short, or the two lengths disagree, end an in-progress jump as incomplete and do not invent the missing samples. This is a firmware bug to code around, not a reason to leave the gyro off.

### Batch size, CPU, heap

Maximum batch is 4 s times the rate. Use a period of 1 so the count on screen is at most a second late. Process the batch and throw it away. Do not keep the raw stream. A moto can be thousands of seconds.

CPU: at 100 Hz the callback sees 100 accel triples and 100 gyro triples. A 3-to-5-sample boxcar, a sum of squares, and a few compares is a few thousand integer operations, once a second. That is the budget. No `sqrt` in the hot path, no FFT, no allocation. Clamp each axis to ±8000 milli-g before squaring so a hard landing cannot overflow a 32-bit integer. The fēnix 6 profile has a watchdog counter of 120000; the callback should return well inside whatever that unit is, which a straight-line pass over one second of samples will.

Heap is not the 131072. `compiler.json` publishes that number as the code-and-data limit and does not publish a separate object-heap size. The rule that replaces the old byte budget: reuse one scratch buffer, do not copy the sample arrays, and keep a ring of 64 air times plus the counters. That is small. Retaining milli-g samples for a whole moto is the thing that would blow the heap.

Hoolan's note that the Instinct 3 Solar gives apps 124 KB, and that their detector does not fit there, is about that product's code limit and about the amount of math they do. It is not a limit on this app. A score and a short filter fit in the fēnix 6 headroom. Porting an unpublished filter bank line for line is still a bad idea, because we cannot see it and we do not have their training rides.

## Detector

Magnitude, not a single axis. On the bars the watch rotates. A vertical axis in the watch frame is not vertical on the bike.

Use the sum of squares. 1 g is 1000² = 1,000,000.

At 25 Hz the smoother is a 3-sample boxcar, about 120 ms. At 50–100 Hz use a 5-sample boxcar (50–100 ms at 100 Hz, 100–200 ms at 50 Hz) on the magnitude, then the same thresholds. The higher-rate smoother is what knocks down engine buzz that is actually above the new Nyquist. It does nothing for vibration that has already aliased.

Starting points, to be rewritten after the probe, not treated as measured constants:

| Gate | Value | Why |
| --- | --- | --- |
| Enter air | smoothed sum of squares under 0.45 g (450² = 202500) for 3 samples at 25 Hz, or 5 samples at 100 Hz | True freefall is 0 g. 0.45 g leaves room for leftover vibration. |
| Soft enter, gyro only | smoothed sum of squares under 0.70 g, and gyro magnitude over a small rotation threshold, for the same run of samples | Recovers jumps where the engine keeps the accel from going fully quiet, but the bike clearly rotated off the lip. Off when the gyro is off. |
| Leave air | smoothed sum of squares over 0.80 g | Back on the bike, or at least no longer in freefall. |
| Minimum air | 300 ms without gyro. 250 ms if the gyro pulse fired | One or two low samples are a bump. The 300 ms line is still the whoop cut. |
| Landing flag | any accel axis beyond ±2000 milli-g within 200 ms after leaving air | A real landing is a spike. Do not require it. A one-wheel or soft landing often has a weak spike. The spike keeps an under-400 ms event that otherwise fails the duration floor. |
| Debounce | 300 ms after leaving air before a new jump can start | Stops one landing from being counted twice. |
| Speed | if a fix exists and speed is under 8 km/h, drop the event | Kills pit-lane arm waves and a bike idling on the stand. If there is no fix, still count. The app already starts without GPS. |
| Score | duration, minimum magnitude, landing peak, gyro peak (0 if gyro is off), speed | A jump needs the duration floor and either a deep magnitude hole or the soft-enter path. The score is recorded with the jump so a bad threshold can be moved after the video test without re-logging raw IMU. It is not a second detector. |

State across batches: in-air or not, samples in this air, samples since last air, minimum magnitude, peak gyro, landing peak. A handful of integers.

### What the bike does to the signal

During a real jump the bike and the rider are in freefall, so a sensor bolted to the unsprung mass goes quiet. The watch is on the wrist, and the wrist is on the grip.

- The engine does not shut up in the air. A single-cylinder four-stroke fires once every two revolutions, about 70 Hz at 8000 rpm. At 25 Hz that folds into 0–12.5 Hz, the same band as freefall, and no smoother can separate them. At 100 Hz the same firing rate folds to about 30 Hz, and a short low-pass can cut it. That is the accuracy gain from the higher rate. It is not free computation for its own sake. Energy that still folds into the bottom 10 Hz is not removed.
- The gyroscope measures rotation, not the piston. Engine buzz that does not rock the watch stays off the gyro. A lip is a slow pitch-rate pulse, a few hertz, visible at 25 Hz. That is why gyro helps the false-jump rate even on a 25 Hz watch, and why it does not tighten the air-time number much: the edges are still read from the accelerometer.
- Whoops are often not air. The wheel loads and unloads. Some are real 100–250 ms jumps. The 300 ms floor drops most of them on purpose. Gyro does not make a 150 ms whoop a clean event at 25 Hz.
- Braking bumps and square-edge hits are spikes, not a sustained hole in the magnitude. The minimum duration rejects them. A spike without a quiet gap must not count.
- Landing on one wheel, or the rider weighting the outside bar, moves the "back to 1 g" moment relative to the tire touching dirt. Air time then disagrees with a video of the wheel by the time the suspension and the arms take to settle. That error is about 30–80 ms and it does not shrink when the sample rate goes from 25 to 100. Call that the floor on air-time error.
- A whip or a scrub is still air. Gyro describes the rotation. The magnitude already says it was air.
- Baro and GPS do not time the jump. GPS speed is the "are we riding" gate. A 1 Hz altitude point cannot place takeoff inside a 0.5 s window. On an air that lasts past about 1.5 s, if altitude at the end of the air is higher than at the start, mark the jump high-confidence. Do not move the start or end sample because of it. A 2 m tabletop sits inside altimeter lag and ordinary baro noise, so the flag will often stay off on normal MX jumps. That is acceptable. It is not a height.

Do not compute jump height. Height from air time assumes a symmetric ballistic hop (`g t² / 8`). A motocross jump is not that: takeoff and landing are at different heights, and the watch air time is already biased by the arms. Extra code does not fix the formula.

## FIT

MX Ride is a watch-app, so it owns the recording. `ActivityRecording.Session.createField` documents the cap as 256 bytes per message for an app, and 32 bytes per message for a data field. The 32-byte cap and the "16 fields across every data field in the activity" forum limit are for data fields sharing one activity. They are not this app's cap. A string field is illegal on `MESG_TYPE_RECORD`. Record messages are written at most once a second.

Byte widths are the FIT base types: uint16 is 2, uint32 and float are 4. Existing fields are one session float and one lap float.

| Field | Id | Message | Type | Why |
| --- | --- | --- | --- | --- |
| `max_speed` | 0 | session | float | Already shipped. Leave it. |
| `lap_max_speed` | 1 | lap | float | Already shipped. Leave it. |
| `jump_count` | 2 | session, and a lap twin | uint16 | The number. |
| `jump_air_ms` | 3 | session, and a lap twin | uint32 | Sum of air time. |
| `jump_longest_ms` | 4 | session, and a lap twin | uint16 | Longest air. A uint16 holds 65 s, which is more than any MX jump. |
| `jump_last_ms` | 5 | record | uint16 | Written on the second a jump ends, 0 otherwise. This is the per-jump mark Garmin Connect can draw on the timeline. Two jumps in one second collapse to one record; the session count is the source of truth. |
| `jump_recent_ms` | 6 | session | uint16, `:count => 32` | The last 32 air times, once, at the end of the session. About 64 bytes of the 256-byte session budget. Connect may not graph an array. The record field is the one riders will see. |

That is on the order of 80 bytes of session payload, a similar lap payload, and 2 bytes on each record, against 256 per message. Do not create one field per jump. Do not write a developer field onto every sample of a raw IMU stream.

If `createField` throws, drop the array first, then the lap twins, and keep the three session totals plus the record mark. The page can live on the RAM ring alone.

## Prior art

These numbers are what the papers and vendors measured on their mount, with their sensor. They are not MX-wrist results. The gap between a boot or a board and a watch on a vibrating grip is the reason the estimates in the next section are wider and less confident. None of this changed in the revision. The richer detector is an attempt to close part of that gap, not a claim that the gap is gone.

| Source | Mount and rate | What they reported |
| --- | --- | --- |
| Harding, Toohey, Hahn, James, Griffith. Lower-back accelerometer, halfpipe snowboarding. 92 aerials, mean air 1.28 s ± 0.13 s. [PDF](https://research-repository.griffith.edu.au/server/api/core/bitstreams/62e3ff4c-9f3e-59ec-9f4d-6003962ff3d3/content) | Lower back, not a wrist | 100% of the 92 airs detected. Mean bias −0.03 s. 94.6% of air times within ±0.15 s of video. Bias grew with longer airs (about +0.05 s at 1.0 s, −0.10 s at 1.6 s). |
| Sadi, Klukas. Head-mounted MEMS, skiing / snowboarding / biking. [Sports Technology 2013](https://doi.org/10.1080/19346182.2013.817058), [UBC thesis](https://doi.org/10.14288/1.0072682) | Head / goggles (Recon) | Thesis: 92% of snowboard jumps detected, against 60% for the Recon algorithm then in the goggles. Air-time mean error 0.033 s (4.8%), versus 0.111 s (8.4%) and 0.538 s (39.7%) for two commercial algorithms. Their own requirement was ±0.1 s. |
| PLOS One 2024, ski-boot IMU. [journal.pone.0307255](https://doi.org/10.1371/journal.pone.0307255) | Both boots. IMU internally fast, delivered at 54 Hz. Video at 25 Hz. 15 big-air, 34 medium (≥500 ms), 18 small (<500 ms) | 100% of big air, 94% of medium, 44% of small. The settings that caught the most jumps also invented the most. Small n, two recreational skiers for the in-run jumps. |
| Fuzzy-logic detector behind AlpineReplay. [IEEE 2014](https://doi.org/10.1109/cies.2014.7011841) | Accelerometer on the athlete or the board, snowboarding and ski jumping | 92% of visually identified snowboard jumps, 8% of detections were false. Ski jumping: 100% detection, no false positives. They report 6,370,971 jumps marked by the app from 2011 to 2014. No wrist-on-motorcycle test. |
| WOO 4.0, board sensor vs watch vs wetsuit. [The WOO Way (PDF)](https://a.storyblok.com/f/120582/x/56f3f4257e/thewooway13.pdf), [what each device measures](https://docs.woosports.com/docs/disciplines-hardware) | Board at the water, versus a watch on the wrist. Their bad watch example is a fēnix 7 | On one jump the board said 2.70 s and the watch said 6.24 s (3.54 s, about 131% apart). A second jump was 2.65 s vs 4.11 s. WOO's position is that a wrist estimate is not comparable to a board measurement because takeoff and landing are read from arm motion. They do not run that estimator on Garmin at all; a Garmin in their system is GPS only, with the WOO sensor doing the jump. |
| Two WOO units on one kiteboard. [We Test Kites, 2015](https://www.wetestkites.com/2015/04/05/review-woo-sports-tracking-of-jump-height-and-air-time-part-1/) | Two board sensors, same board, rough session, 22 paired jumps over 4 m | Max height disagreed by 1.2 m on a 7.8–9 m reading (about 15%). Max air time disagreed by 1.5 s on a 5.7 s reading (about 25%), and it was not even the same jump. Dedicated hardware is not automatically tight. |
| Hoolan, Connect IQ jump tracking. [Compatibility list](https://www.hoolan.app/garmin/garmin-compatibility) | Watch, and they require 100 Hz accel and gyro | fēnix 7, 8, and E are listed as jumps plus GPS. fēnix 6 Pro family is GPS only, jumps pending. They do not publish a detection rate or an air-time error. Instinct 3 Solar (124 KB app limit) cannot run their detector. |
| Slopes | Phone / watch ski app | Their [accuracy note](https://slopes.helpscoutdocs.com/article/10-how-accurate-are-the-live-stats) covers distance, vertical, and speed. It does not publish jump-count or air-time error. |
| Carv | Boot IMU | Public write-ups are about edge angle and pitch, not a validated air-time error. |
| Trace, Snocru | Snow trackers that have advertised jumps | No accuracy report found that can be cited. |
| Garmin Jumpmaster | On the fēnix 6 | Parachute release-point math. Not an air-time counter. Do not build on it. |
| Alpinestars Tech-Air, AIM, RaceBox | MX products with IMUs or fast GPS | Tech-Air is a crash airbag. AIM logs G and laps. RaceBox is a GNSS lap timer (25 Hz GPS on the Mini). None of them publish a wrist-style jump-air-time error, and none of them is this sensor. |

The pattern in the studies: on a boot, helmet, or lower back, jumps longer than about half a second are detected most of the time, and air time is good to a few hundredths of a second when the mount is quiet and the rate is high. Under half a second, even a boot sensor at 54 Hz fell to 44% in the only study that split the data that way. A watch on a kiteboard grip, in the only head-to-head found, was off by seconds.

## Expected accuracy

Planning ranges, not measurements. Confidence is how likely a video test is to land inside the range. "Low" means the number is an extrapolation and the test can move it. The 25 Hz accel-only column is the previous plan. The other two columns are what the gyro score and the higher rate should change. They move the count more than they move the air time.

| Question | 25 Hz, accel only | 25 Hz, accel + gyro score | 100 Hz, accel + gyro, 5-sample boxcar | Confidence |
| --- | --- | --- | --- | --- |
| Detection of jumps with true air ≥ 500 ms (tabletop, double, step-up), wrist on the bars | 70–90%. Boot and head studies sit at 92–100% for this class. The discount is the grip. | 75–92%. The gyro keeps dips that never go fully quiet but do rotate off the lip. It does not create a quiet gap the accelerometer never saw. | 85–95%. This is the case the filter can actually clean, if the watch returns 100. | Low to medium. No MX-wrist number exists. The steps between columns are the argument above, not a new study. |
| False jumps on a rough trail, with the duration floor and the speed gate | About 1 every 2–10 minutes. Without those gates, whoops and braking bumps can look like a jump several times a minute. | About 1 every 5–15 minutes. Gyro is doing the work here: a bump rarely has the slow pitch-rate pulse of a lip. | About 1 every 10–20 minutes. The filter removes buzz the 25 Hz path had to threshold through. | Low |
| Minimum jump that is even possible to see | About 200 ms (5 samples). Reliable detection starts nearer 400–500 ms. Whoops under 300 ms stay out of scope. | Same timing. Gyro mostly deletes false short events. It does not make a 150 ms whoop visible. The floor can drop from 300 ms to 250 ms only when the gyro pulse fired. | Reliable detection nearer 250–350 ms. Sample quantum is 10 ms. Whoops under 250 ms stay out of scope. | Medium for the 25 Hz floor. Low for the 100 Hz improvement. |
| Air-time error on a detected jump ≥ 500 ms | Typical absolute error 80–200 ms. Quantum is 40 ms. The 120 ms smoother blurs both edges. Harding's lower-back bias was 30 ms, on a quieter mount and a longer air. WOO's fēnix 7 wrist comparison was multi-second on kite jumps; that is the bad tail, not the MX median, and it is the published wrist result. | 80–180 ms. Gyro does not decide the edge. A slightly cleaner enter/leave is the whole gain. | 40–120 ms. Quantum is 10 ms. About 30–80 ms of the remainder is arms and suspension, and the rate does not remove it. Do not expect the ski-helmet 33 ms figure. | Low to medium |
| Bias direction | Short jumps read short, because the threshold eats both edges. Soft or one-wheel landings read long if the spike is late and the magnitude stays low while the rider's arms recover. | Same direction. | Same direction, smaller threshold blur. The one-wheel bias stays. | Medium |
| Jump height from air time, at any rate | Do not estimate. | Do not estimate. | Do not estimate. | High that `g t² / 8` would be misleading |

What moves the error, in order:

1. Whether the watch returns 25 Hz or 100 Hz. This is the split that matters. Query it. Do not assume the fēnix 6 is stuck at 25, and do not assume a fēnix 8 on firmware 24.x delivers aligned 100 Hz pairs.
2. Engine and chassis vibration. At 25 Hz it aliases into the freefall band. At 100 Hz a short boxcar can cut the part that is actually above ~15 Hz.
3. How hard the rider hangs on the bars, and whether the landing is one wheel. This is the 30–80 ms floor.
4. The 300 ms product cut. It deletes false jumps and real small jumps. Gyro lets that cut move to 250 ms only when a rotation pulse is present.
5. GPS dropout. The detector still runs. It loses the "not in the pits" gate, so false jumps rise when the bike is slow and the fix is gone.
6. A dropped accel batch on fēnix 8 firmware 24.x. Treat it as a gap. Counting across the gap would invent a jump or stretch an air time by a second.

## Battery

Garmin does not publish a milliamp cost for the Connect IQ accelerometer. A fēnix 6 GPS activity is already on the order of a day and a half in their GPS mode (the series spec is up to 36 hours of GPS). That activity is already paying for GNSS and optical heart rate, which dominate.

25 Hz accelerometer on top of a recording that is already open should be a small fraction of that drain, because the watch already runs the accelerometer for gestures. 100 Hz accelerometer plus 100 Hz gyroscope is the heavier option and is now the default on a watch that returns those rates, because that is where the air-time error actually moves. It is still only registered in `PHASE_RECORDING`, then unregistered on pause and on save or discard.

Check before shipping: one moto at the watch's max rate, one at 25 Hz with gyro off, same track, note the battery percent. If the max-rate ride is more than a few percent worse, drop the rate before dropping the feature.

## Will it fit on the fēnix 6

Yes. The release build uses 13367 bytes of the 131072 code-and-data limit. The detector, the score, the fourth page, the ring, and the FIT fields are a few KB on top of that, not a hundred. Resources and the symbol table are not part of this number. Do not add a font. Do not keep the raw stream.

The code is the same algorithm on every device. The only per-device branch is the two integers `getMaxSampleRateForSensorType` returns, and whether the gyro block runs. A second implementation for the fēnix 6 would cost more than it saves, and there is no longer a 5 KB reason to keep the 6 on a worse detector.

If a later build gets near the limit, cut in this order: the session array of recent air times, the lap twins, the fourth page (put `J` and `AIR` on the stats page instead). Do not cut the detector to save the page. Do not raise `minSdkVersion`.

fēnix 6 Pro, 7, 8, E, and 9 have a larger code-and-data limit (1.25 MB on the 6 Pro family, 768 KB on the 7 and the newer parts). They run the same code at whatever rate they report.

## How to build it, after this plan is approved

1. Probe build. When a recording starts, read both max rates and show them for one session (`A25 G25`, or whatever the watch returns). Log the smoothed magnitude and the gyro magnitude for a single known jump. Delete the probe UI before the feature ships.
2. Tune offline. One video at 120 fps of 10 jumps that are clearly over 0.5 s, 10 whoops or braking bumps, two minutes of trail with no intentional jump, and 30 s of shaking the bars in the pits. Sync the video to the watch with the existing GPS-ready vibration, or with a clap on a visible clock. Score the wheel leaving the ground and the wheel touching, not the rider's body.
3. Ship the state machine with the gates above, gyro on only if the probe returned at least 25. Move the numbers from the video. Do not ship the first constants.
4. Acceptance, on that same video set, before it is called done:
   - At least 80% of the ≥0.5 s jumps counted. If the probe returned 100 Hz, the bar is 90%.
   - No more than one false jump per two minutes of the no-jump trail. If gyro is on, no more than one per five minutes.
   - Median absolute air-time error ≤ 150 ms at 25 Hz, and ≤ 100 ms if the probe returned 100 Hz, on the jumps that were counted.
   - Zero jumps while shaking the bars at under 8 km/h with a GPS fix.
   - Release fēnix 6 code + data stays under 131072. It is 13367 before this feature. fēnix 6 Pro and fēnix 7 still build. Public manifest stays in lockstep with the beta manifest, app id unchanged.
5. Do not add jump height in this version. Do not lower the whoop floor below 250 ms to chase a count.

## Sources

- Connect IQ `Toybox.Sensor`, including `registerSensorDataListener`, the 1 Hz `enableSensorEvents` path, and `getMaxSampleRate` / `getMaxSampleRateForSensorType`: https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor.html
- High-frequency sensors article (period max 4 s, batch = period × rate): https://developer.garmin.com/connect-iq/articles/core-topics/Sensors.html
- `AccelerometerData`, milli-g, power / pitch / roll: https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor/AccelerometerData.html
- `GyroscopeData`, deg/s, API 3.3.0, device list includes fēnix 6 through 9 and fēnix E: https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor/GyroscopeData.html
- `ActivityRecording.Session.createField`, 256 bytes per message for an app, 32 for a data field, no strings on record messages: https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording/Session.html
- `Toybox.Position`. The continuous-location example is once per second: https://developer.garmin.com/connect-iq/api-docs/Toybox/Position.html
- Garmin employee on period vs rate (period is seconds, max 4; at the time the max rate cited was 25 Hz): https://forums.garmin.com/developer/connect-iq/i/bug-reports/fr945-accelerometer-data-only-available-once-per-second
- SDK 6.3.0, 100 Hz accel / gyro on some devices, magnetometer to 50 Hz: https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/connect-iq-6-3-0-sdk-release
- fēnix 7 Pro reported capped at 25 Hz in the simulator; Garmin's reply was that the real device should still accept the higher rate: https://forums.garmin.com/developer/connect-iq/i/bug-reports/6-3-0-sdk-higher-rate-support-for-accelerometer-magnetometer-and-gyroscope and https://forums.garmin.com/developer/connect-iq/i/bug-reports/ciq-6-3-accelerometer-sim-rates
- fēnix 8 firmware 24.x delivering ~103 Hz and dropping about a second of accelerometer data when both sensors are on: https://forums.garmin.com/cfs-file/__key/telligent-ideas/badb36f5-638c-4c04-82b9-767d7c8d965c/0285.2026_2D00_11_2D00_24_2D00_fenix8_2D00_fw24_2D00_sensor_2D00_listener.pdf
- fēnix 6 sensors (gyro, accelerometer, barometric altimeter) and the manual note that pressure is collected continuously: https://www.garmin.com.my/products/discontinued/fenix-6-sapphire-nylon/ and https://www8.garmin.com/manuals/webhelp/fenix6-6ssport/EN-US/GUID-0FFD6812-6604-4D97-BC0F-56194CB12EB5.html
- Hoolan watch list and the 124 KB Instinct 3 Solar note: https://www.hoolan.app/garmin/garmin-compatibility
- Harding et al., lower-back air time vs video: https://research-repository.griffith.edu.au/server/api/core/bitstreams/62e3ff4c-9f3e-59ec-9f4d-6003962ff3d3/content
- Sadi and Klukas, head-mounted air time: https://doi.org/10.1080/19346182.2013.817058 and https://doi.org/10.14288/1.0072682
- Ski-boot jump detector, PLOS One 2024: https://doi.org/10.1371/journal.pone.0307255
- Fuzzy jump detector / AlpineReplay: https://doi.org/10.1109/cies.2014.7011841
- WOO, board vs watch: https://a.storyblok.com/f/120582/x/56f3f4257e/thewooway13.pdf and https://docs.woosports.com/docs/disciplines-hardware
- Two WOO sensors on one board: https://www.wetestkites.com/2015/04/05/review-woo-sports-tracking-of-jump-height-and-air-time-part-1/
- Slopes live-stat accuracy (not jumps): https://slopes.helpscoutdocs.com/article/10-how-accurate-are-the-live-stats

I used the wrong sensors article URL. The search result was https://developer.garmin.com/connect-iq/articles/core-topics/Sensors.html — I wrote a shortened wrong URL. Fix that.

Also I should double-check the four-stroke firing frequency claim so I don't state a wrong number as fact.

A four-stroke fires once every two revolutions. At 11000 rpm: 11000/60 = 183.3 revolutions per second, firing at half that = 91.7 Hz. At 6000 rpm: 50 Hz firing. So "faster than 25 Hz" is true. "11000 rpm is about 183 Hz for a single, and a four-stroke fires half that" — a single-cylinder four-stroke fires once per two revolutions, so 91 Hz at 11000 rpm. A twin fires twice per two revolutions (once per revolution) if it's an even fire... this is getting messy and I might be wrong for V-twins.

I should simplify that sentence. I said "11000 rpm is about 183 Hz for a single, and a four-stroke fires half that" which is confusing because a single four-stroke IS the half. Let me fix to: "A four-stroke single at 8000 rpm fires about 67 times a second. That is above the 25 Hz Nyquist and still mostly above a 100 Hz sampler's ability to see the firing cleanly, but a lot of the lower buzz and the chassis shake moves out of the freefall band."

8000/60/2 = 66.7 Hz. Yes for a single. A parallel twin four-stroke often fires once per revolution (two cylinders, each every two revs, evenly spaced) = 133 Hz at 8000 rpm. MX bikes are usually single-cylinder four-strokes. I'll say single-cylinder four-stroke, ~67 Hz at 8000 rpm, which aliases at 25 Hz and is inside a 100 Hz sample rate's Nyquist (50 Hz) — WAIT 67 Hz is ABOVE the 50 Hz Nyquist of a 100 Hz sampler. So it STILL aliases at 100 Hz!

Nyquist at 100 Hz is 50 Hz. 67 Hz aliases to 100-67 = 33 Hz. Still not removed by a 5-sample boxcar which cuts well below that... A 5-sample boxcar at 100 Hz has a first null at 20 Hz. It attenuates high frequencies but a 33 Hz alias is only partly reduced.

Hmm, I need to be more honest. The benefit of 100 Hz is:
- The sample quantum is 10 ms instead of 40 ms
- Vibration energy between ~12 Hz and ~50 Hz that was aliased into the 0–12 Hz band at 25 Hz is now represented at its real frequency and a low-pass can attenuate it
- Energy above 50 Hz still aliases, but aliases to 50–100 Hz folded, and a low-pass can still attenuate those aliases IF the anti-alias... wait NO. Once sampled, an alias at 33 Hz (from 67 Hz) is indistinguishable from a real 33 Hz signal. A low-pass with cutoff 10 Hz WOULD attenuate a 33 Hz alias. Yes! A boxcar/low-pass after sampling removes both real high frequencies and aliases that landed above the cutoff. The problem at 25 Hz is aliases that land INSIDE the cutoff (0–5 Hz), which a low-pass cannot remove.

At 100 Hz, a 67 Hz tone aliases to 33 Hz, which a 10 Hz low-pass removes. A tone that aliases into 0–10 Hz would be something near 100 Hz, 200 Hz, etc. 67 Hz does NOT alias into the freefall band at 100 Hz. Good.

So my sentence should say: at 25 Hz a ~70 Hz firing rate folds into the same band as freefall and no filter can separate them. At 100 Hz that firing rate folds to around 30 Hz, and a short low-pass can cut it. That is the real gain.

I'll fix the sensors URL and that paragraph.

Also I wrote "developer.garmin.com/articles/core-topics/sensors" which is wrong. Fix to the connect-iq path.

Let me also verify four-stroke single firing: yes, one combustion per two crank revolutions. 8000 rpm / 60 / 2 = 66.7 Hz. I'll use that.

I'll patch those two spots.