#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${CIQ_SDK:-$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-9.3.0}"
MONKEYC="$SDK/bin/monkeyc"
KEY="$ROOT/bin/developer_key.der"

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

for device in "${devices[@]}"; do
	"$MONKEYC" -f "$ROOT/monkey.jungle" -o "$ROOT/bin/mxride-${device}.prg" -y "$KEY" -d "$device" -w -l 2
done

"$MONKEYC" -e -f "$ROOT/monkey.jungle" -o "$ROOT/bin/mxride.iq" -y "$KEY" -w -l 2
printf 'built %s\n' "$ROOT/bin"
