#!/usr/bin/env bash
# Reapply the calc-history patch (+ "keep last query" setting) to a
# freshly installed Ulauncher. Run as the normal desktop user (needs
# sudo for the package files, not as root). See ../ULAUNCHER.md for
# background/history of this patch.
#
# Usage: ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALC_DIR="/usr/lib/python3/dist-packages/ulauncher/search/calc"
SETTINGS="$HOME/.config/ulauncher/settings.json"

if [ ! -d "$CALC_DIR" ]; then
    echo "Kein Ulauncher unter $CALC_DIR gefunden. Erst 'ulauncher' installieren." >&2
    exit 1
fi

echo "== 1/4: Originale sichern (falls noch nicht geschehen) =="
for f in CalcMode.py CalcResultItem.py; do
    if [ ! -f "$CALC_DIR/$f.orig" ]; then
        sudo cp "$CALC_DIR/$f" "$CALC_DIR/$f.orig"
        echo "  Backup angelegt: $f.orig"
    else
        echo "  Backup existiert schon: $f.orig"
    fi
done

echo "== 2/4: Patch-Dateien installieren =="
sudo cp "$SCRIPT_DIR/CalcHistory.py" "$CALC_DIR/CalcHistory.py"
sudo cp "$SCRIPT_DIR/CalcResultItem.py" "$CALC_DIR/CalcResultItem.py"
sudo cp "$SCRIPT_DIR/CalcMode.py" "$CALC_DIR/CalcMode.py"
sudo rm -rf "$CALC_DIR/__pycache__"
python3 -m py_compile "$CALC_DIR/CalcHistory.py" "$CALC_DIR/CalcResultItem.py" "$CALC_DIR/CalcMode.py"
echo "  installiert, Syntax geprüft"

echo "== 3/4: 'Eingabe beim Schließen behalten' aktivieren =="
if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$SETTINGS.bak"
    python3 - "$SETTINGS" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
data['clear-previous-query'] = False
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=4)
PYEOF
    echo "  clear-previous-query = false gesetzt (Backup: settings.json.bak)"
else
    echo "  $SETTINGS existiert noch nicht (Ulauncher noch nie gestartet)."
    echo "  Bitte Ulauncher einmal starten, dann dieses Skript erneut laufen lassen,"
    echo "  oder die Einstellung 'Keep previous query on show' manuell in den"
    echo "  Preferences deaktivieren."
fi

echo "== 4/4: Ulauncher neu starten =="
pkill -f 'bin/ulauncher' 2>/dev/null || true
sleep 1
nohup ulauncher -v > /tmp/ulauncher-verbose.log 2>&1 &
disown
echo "  neu gestartet (Log: /tmp/ulauncher-verbose.log)"

echo
echo "Fertig. Test: '2+2' eingeben -> Ergebnis + History-Zeilen sollten erscheinen."
