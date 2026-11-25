#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${CIQ_SDK:-$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-9.3.0}"
MONKEYC="$SDK/bin/monkeyc"
KEY="$ROOT/bin/developer_key.der"
MODE="beta"
RELEASE=1
GENERATE_KEY=0
PEM="$ROOT/bin/developer_key.pem"

for arg in "$@"; do
	case "$arg" in
		--public) MODE="public" ;;
		--debug) RELEASE=0 ;;
		--generate-key) GENERATE_KEY=1 ;;
		*)
			printf 'usage: %s [--public] [--debug] [--generate-key]\n' "$0" >&2
			exit 1
			;;
	esac
done

# Release strips the symbol table (-r) and runs the fast optimizer (-O 2).
# --debug keeps the previous unstripped, default-optimization build.
MONKEYC_FLAGS=(-w -l 2)
if [[ "$RELEASE" -eq 1 ]]; then
	MONKEYC_FLAGS+=(-r -O 2)
fi

if [[ ! -x "$MONKEYC" ]]; then
	printf 'monkeyc not found at %s\n' "$MONKEYC" >&2
	printf 'Set CIQ_SDK to a Connect IQ SDK root that contains bin/monkeyc.\n' >&2
	exit 1
fi

mkdir -p "$ROOT/bin"

# Never mint a key as a side effect of building. A missing key is an error.
# --generate-key creates bin/developer_key.pem and bin/developer_key.der, and
# refuses if either file is already there.
if [[ "$GENERATE_KEY" -eq 1 ]]; then
	if [[ -e "$KEY" || -e "$PEM" ]]; then
		printf 'refusing to overwrite an existing developer key\n' >&2
		exit 1
	fi
	openssl genrsa -out "$PEM" 4096
	openssl pkcs8 -topk8 -inform PEM -outform DER -in "$PEM" -out "$KEY" -nocrypt
fi

if [[ ! -f "$KEY" ]]; then
	printf 'developer key not found: %s\n' "$KEY" >&2
	printf 'Copy the existing key to that path. This script does not create one unless you pass --generate-key.\n' >&2
	exit 1
fi

python3 "$ROOT/scripts/gen_fonts.py"
python3 "$ROOT/scripts/import-sdk-devices.py"

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
	"$MONKEYC" -e -f "$ROOT/monkey-public.jungle" -o "$ROOT/bin/mxride-public.iq" -y "$KEY" "${MONKEYC_FLAGS[@]}"
	printf 'built %s\n' "$ROOT/bin/mxride-public.iq"
	exit 0
fi

for device in "${devices[@]}"; do
	"$MONKEYC" -f "$ROOT/monkey.jungle" -o "$ROOT/bin/mxride-${device}.prg" -y "$KEY" -d "$device" "${MONKEYC_FLAGS[@]}"
done

"$MONKEYC" -e -f "$ROOT/monkey.jungle" -o "$ROOT/bin/mxride.iq" -y "$KEY" "${MONKEYC_FLAGS[@]}"
printf 'built %s\n' "$ROOT/bin"
