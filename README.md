# MX Ride

Watch app for motocross and desert riding on the fēnix 7 family. The big number is speed in km/h. Under it: heading, altitude, heart rate, timer, and distance. DOWN opens max speed, total ascent, and the lap timer.

![Ride page on fēnix 7, GPS playback](sim/fenix7-ride.png)

![Stats page on fēnix 7, GPS playback](sim/fenix7-stats.png)

## Build

Connect IQ SDK 9.3.0. `monkeyc` must be on `PATH`, or set `CIQ_SDK` to the SDK root. Device definitions for the eight fēnix 7 products go in `~/.Garmin/ConnectIQ/Devices`.

The SDK zip does not need a Garmin login. The SDK manager's device download does. These binaries were built with the device files from [berryk/Garmin-watchface `devices-v1.0.0`](https://github.com/berryk/Garmin-watchface/releases/download/devices-v1.0.0/connectiq-devices.zip). Unpack it so these folders sit next to each other:

`fenix7` `fenix7s` `fenix7x` `fenix7pro` `fenix7spro` `fenix7xpro` `fenix7pronowifi` `fenix7xpronowifi`

```
./scripts/build.sh
```

Outputs:

- `bin/mxride-fenix7.prg`
- `bin/mxride-fenix7s.prg`
- `bin/mxride-fenix7x.prg`
- `bin/mxride-fenix7pro.prg`
- `bin/mxride-fenix7spro.prg`
- `bin/mxride-fenix7xpro.prg`
- `bin/mxride-fenix7pronowifi.prg`
- `bin/mxride-fenix7xpronowifi.prg`
- `bin/mxride.iq`

The first run mints `bin/developer_key.der` with openssl when that file is missing. The key and `bin/developer_key.pem` are gitignored. The `.prg` files already in `bin/` were signed with a key that is not in this repo. To rebuild those same signatures, put your own `developer_key.der` in `bin/` before running the script. A different key is a different signature: remove the old sideload from the watch before installing the new one.

## Sideload

Plug the watch in over USB. Copy the `.prg` that matches the product into `GARMIN/APPS` on the watch drive. Eject, then start MX Ride from the app list.

`bin/mxride.iq` is the package for Garmin Express or the store. USB sideload uses the `.prg`.

## Buttons

Physical buttons. Touch is not the control.

| Button | Action |
| --- | --- |
| START, short | Ready: start. Recording: pause. Paused: resume. Save screen: accept the highlighted choice. |
| START, long, or MENU | Pause if a session is recording, then open SAVE / DISCARD. |
| UP / DOWN | Switch the two pages. On the save screen, move the highlight. |
| BACK | Recording or paused: lap. Save screen: back to paused. Ready: leave the app. |

Page 1 is speed in km/h, heading in degrees plus a cardinal and a needle, `A` for altitude in meters, `H` for heart rate, then the timer and distance in km.

Page 2 is `MAX` speed, `UP` for total ascent in meters, the current lap time, and the lap count.

Missing GPS or heart rate draws `--`. Speed stays `--` until there is a fix. A zero is not used as a stand-in.

## What is recorded

The session is sport motorcycling, subsport motocross, name Motocross. The FIT gets the GPS track, speed, distance, elevation, ascent, timer, laps, heart rate when the watch has a reading, and the device's own calorie figure. Two developer fields, both in km/h: `max_speed` on the session, `lap_max_speed` on each lap.

GPS uses SatIQ when the watch supports that configuration, otherwise a continuous single-band fix. It does not pin multi-band max accuracy. `createSession` does not expose the recording interval, so 1 Hz versus smart recording stays with the device. The calorie number is the device algorithm. On a motorcycling activity that can be a poor estimate, because the bike is doing the work.

## Fonts

The official Connect IQ font pack returned HTTP 401 without a Garmin developer login. Asking the simulator for a missing system font crashes the app. MX Ride ships its own bitmap fonts in `resources/fonts`: a large 7-segment digit face and a smaller label face. `scripts/gen_fonts.py` regenerates both. Labels stay uppercase. That face has no lowercase and no degree sign.

## Simulator

`sim/desert-loop.gpx` is a two-minute rectangle at 50 km/h. With that file playing on the fēnix 7 simulator, the ride page showed 50 km/h, heading north, a running timer, and 0.1 km. The stats page showed a max of 50 and `UP 2`. That 2 m is the simulator's own ascent from a bad altitude series, not the climb in the file. The same run reported altitude near -450 m and no heart rate. This simulator did not apply the file's elevation or its heart-rate extension. The app drew the numbers the simulator supplied.

The save and discard screen, the lap button, and the written FIT file were not opened in that run. The timer and distance moved, which is the session recording. The other seven prgs were compiled in the same build and not loaded in the simulator, so the 240 and 280 faces were not screenshotted. The non-sapphire simulator profile does not advertise SatIQ, so that run used a continuous fix.
