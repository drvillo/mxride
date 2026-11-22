#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${CIQ_SDK:-$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-9.3.0}"
MONKEYC="$SDK/bin/monkeyc"
KEY="$ROOT/bin/developer_key.der"
MODE="beta"

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--public" ) ]]; then
	printf 'usage: %s [--public]\n' "$0" >&2
	exit 1
fi
if [[ "${1:-}" == "--public" ]]; then
	MODE="public"
fi

if [[ ! -x "$MONKEYC" ]]; then
	printf 'monkeyc not found at %s\n' "$MONKEYC" >&2
	printf 'Set CIQ_SDK to a Connect IQ SDK root that contains bin/monkeyc.\n' >&2
	exit 1
fi

mkdir -p "$ROOT/bin"
python3 "$ROOT/scripts/gen_fonts.py"
python3 "$ROOT/scripts/import-sdk-devices.py"

if [[ ! -f "$KEY" ]]; then
	openssl genrsa -out "$ROOT/bin/developer_key.pem" 4096
	openssl pkcs8 -topk8 -inform PEM -outform DER -in "$ROOT/bin/developer_key.pem" -out "$KEY" -nocrypt
fi

# The public listing is a second app. Same devices and version, different id.
# Fail if the two manifests drift apart by anything other than that id.
python3 - "$ROOT/manifest.xml" "$ROOT/manifest-public.xml" << 'PY'
import re
import sys
from pathlib import Path

def body(path):
    text = Path(path).read_text()
    return re.sub(r'id="[0-9A-Fa-f]{32}"', 'id="APP"', text, count=1)

beta, public = sys.argv[1:]
if body(beta) != body(public):
    sys.exit("manifest-public.xml differs from manifest.xml by more than the app id")
beta_id = re.search(r'id="([0-9A-Fa-f]{32})"', Path(beta).read_text()).group(1)
public_id = re.search(r'id="([0-9A-Fa-f]{32})"', Path(public).read_text()).group(1)
if beta_id == public_id:
    sys.exit("public app id matches the beta app id")
PY

devices=(
	fenix6
	fenix6s
	fenix6pro
	fenix6spro
	fenix6xpro
	fenix7
	fenix7s
	fenix7x
	fenix7pro
	fenix7spro
	fenix7xpro
	fenix7pronowifi
	fenix7xpronowifi
	fenix843mm
	fenix847mm
	fenix8pro47mm
	fenix8solar47mm
	fenix8solar51mm
	fenixe
	fenix943mm
	fenix947mm
	fenix9pro43mm
	fenix9pro47mm
	fenix9pro51mm
	fenix9prosolar47mm
	fenix9prosolar51mm
)

if [[ "$MODE" == "public" ]]; then
	"$MONKEYC" -e -f "$ROOT/monkey-public.jungle" -o "$ROOT/bin/mxride-public.iq" -y "$KEY" -w -l 2
	printf 'built %s\n' "$ROOT/bin/mxride-public.iq"
	exit 0
fi

for device in "${devices[@]}"; do
	"$MONKEYC" -f "$ROOT/monkey.jungle" -o "$ROOT/bin/mxride-${device}.prg" -y "$KEY" -d "$device" -w -l 2
done

"$MONKEYC" -e -f "$ROOT/monkey.jungle" -o "$ROOT/bin/mxride.iq" -y "$KEY" -w -l 2
printf 'built %s\n' "$ROOT/bin"
