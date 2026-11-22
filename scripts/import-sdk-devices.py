#!/usr/bin/env python3
"""Write compiler.json for devices the SDK lists but the device pack does not ship.

The Connect IQ SDK manager will not download device configurations without a
Garmin developer login. SDK 9.3.0 still ships the device list inside
monkeybrains.jar (devices.xml). This writes only compiler.json, and only when
the folder has no official device image. It never copies another device's .bin.
"""

import json
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

IDS = [
    "fenix843mm",
    "fenix847mm",
    "fenix8pro47mm",
    "fenix8solar47mm",
    "fenix8solar51mm",
    "fenixe",
    "fenix943mm",
    "fenix947mm",
    "fenix9pro43mm",
    "fenix9pro47mm",
    "fenix9pro51mm",
    "fenix9prosolar47mm",
    "fenix9prosolar51mm",
]

TYPE_MAP = {
    "audio-content-provider-app": "audioContentProvider",
    "background": "background",
    "datafield": "datafield",
    "glance": "glance",
    "watch-app": "watchApp",
    "watchface": "watchFace",
    "widget": "widget",
}


def sdk_jar():
    home = Path.home() / ".Garmin" / "ConnectIQ" / "Sdks"
    jars = sorted(home.glob("connectiq-sdk-*/bin/monkeybrains.jar"))
    if not jars:
        sys.exit("no Connect IQ SDK jar under ~/.Garmin/ConnectIQ/Sdks")
    return jars[-1]


def profile(dev):
    res = dev.find("resolution")
    icon = dev.find("launcher_icon")
    apps = []
    for app in dev.find("app_types"):
        apps.append({
            "memoryLimit": int(app.get("memory_limit")),
            "type": TYPE_MAP.get(app.get("id"), app.get("id")),
        })
    parts = []
    for part in dev.find("part_numbers"):
        langs = []
        languages = part.find("languages")
        if languages is not None:
            for lang in languages:
                langs.append({"code": lang.text, "fontSet": lang.get("font_set")})
        row = {
            "connectIQVersion": part.get("connectIQVersion"),
            "languages": langs,
            "number": part.get("number"),
        }
        if part.get("firmwareVersion") is not None:
            row["firmwareVersion"] = int(part.get("firmwareVersion"))
        parts.append(row)
    bpp = int((dev.findtext("bpp") or "16").strip())
    pixel = (dev.findtext("pixel_format") or ("RGB565" if bpp >= 16 else "ARGB2222")).strip()
    return {
        "appTypes": apps,
        "bitsPerPixel": bpp,
        "deviceFamily": dev.get("family"),
        "deviceGroup": dev.get("grouping"),
        "deviceId": dev.get("id"),
        "displayName": dev.get("name"),
        "displayType": (dev.findtext("displayType") or "amoled").strip(),
        "launcherIcon": {"height": int(icon.get("height")), "width": int(icon.get("width"))},
        "orientation": 0,
        "partNumbers": parts,
        "pixelFormat": pixel,
        "resolution": {"height": int(res.get("height")), "width": int(res.get("width"))},
        "webDocDeviceGroup": dev.get("web_doc_grouping"),
        "worldWidePartNumber": dev.get("part_number"),
    }


def main():
    jar = sdk_jar()
    with zipfile.ZipFile(jar) as zf:
        xml = zf.read("com/garmin/monkeybrains/devices/devices.xml")
    root = ET.fromstring(xml)
    devices = Path.home() / ".Garmin" / "ConnectIQ" / "Devices"
    wanted = set(IDS)
    found = 0
    for dev in root.iter("device"):
        did = dev.get("id")
        if did not in wanted:
            continue
        dest = devices / did
        if (dest / (did + ".bin")).exists():
            print("keep official", did)
            found += 1
            continue
        existing = dest / "compiler.json"
        if existing.exists() and '"deviceVersion"' in existing.read_text():
            print("keep official", did)
            found += 1
            continue
        dest.mkdir(parents=True, exist_ok=True)
        (dest / "compiler.json").write_text(json.dumps(profile(dev), indent=2) + "\n")
        print("wrote", did)
        found += 1
    missing = wanted - {dev.get("id") for dev in root.iter("device")}
    if missing:
        sys.exit("SDK device list is missing: " + ", ".join(sorted(missing)))
    if found != len(IDS):
        sys.exit("expected %d devices, wrote %d" % (len(IDS), found))


if __name__ == "__main__":
    main()
