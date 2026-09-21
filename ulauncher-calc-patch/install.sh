#!/usr/bin/env bash
# Ulauncher installieren (falls fehlend) und patchen:
#   - Calc-Patch (CalcMode/CalcHistory/CalcResultItem, nur Ulauncher 5.15.x)
#   - Ctrl+A / Ctrl+E (emacs-style Zeilenanfang/-ende), per Einfuegen in die
#     installierte UlauncherWindow.py, nicht als Vollkopie -> versionsrobust
#   - "Eingabe beim Schliessen behalten"
# Run als normaler Desktop-User (braucht sudo fuer die Paketdateien, nicht als
# root). Hintergrund/History: ../ULAUNCHER.md.
#
# Usage: ./install.sh [--no-restart]
#   --no-restart  Ulauncher nicht neu starten (fuer chezmoi apply, oft ohne
#                 DISPLAY/Desktop-Sitzung); nur Hinweis ausgeben.
set -euo pipefail

RESTART=1
[ "${1:-}" = "--no-restart" ] && RESTART=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UL_DIR="/usr/lib/python3/dist-packages/ulauncher"
CALC_DIR="$UL_DIR/search/calc"
WINDOW_DIR="$UL_DIR/ui/windows"
SETTINGS="$HOME/.config/ulauncher/settings.json"

# Fest gepinnte Version fuer Neuinstallationen. Prueft immer die SHA256.
# Quellen: GitHub-Release (auch ohne VPN erreichbar), Ersatz: Forgejo Generic
# Package (nur per VPN). Version hier + SHA256 zusammen aendern.
PIN_VERSION="5.15.15"
PIN_SHA256="a78826a5121e9614ec4b76d58ae421a85c11bf4639067467133df72d1340c6b4"
PIN_DEB="ulauncher_${PIN_VERSION}_all.deb"
PIN_URL_GITHUB="https://github.com/Ulauncher/Ulauncher/releases/download/${PIN_VERSION}/${PIN_DEB}"
PIN_URL_FORGEJO="http://forgejo.tipi.lan:8195/api/packages/harry/generic/ulauncher/${PIN_VERSION}/${PIN_DEB}"

MARKER="emacs-style line navigation"

echo "== 0/4: Ulauncher installieren (falls fehlend) =="
if dpkg -s ulauncher >/dev/null 2>&1; then
    echo "  bereits installiert: $(dpkg-query -W -f='${Version}' ulauncher)"
else
    TMPDEB="$(mktemp --suffix=.deb)"
    trap 'rm -f "$TMPDEB"' EXIT
    fetched=0
    for url in "$PIN_URL_GITHUB" "$PIN_URL_FORGEJO"; do
        echo "  lade $url"
        if curl -fsSL --max-time 60 -o "$TMPDEB" "$url" \
           && echo "$PIN_SHA256  $TMPDEB" | sha256sum -c --status; then
            fetched=1
            break
        fi
        echo "  fehlgeschlagen oder SHA256 falsch, naechste Quelle..." >&2
    done
    if [ "$fetched" != 1 ]; then
        echo "Konnte $PIN_DEB aus keiner Quelle mit passender SHA256 laden." >&2
        exit 1
    fi
    if command -v nala >/dev/null 2>&1; then
        sudo nala install -y "$TMPDEB"
    else
        sudo apt-get install -y "$TMPDEB"
    fi
    echo "  installiert: $(dpkg-query -W -f='${Version}' ulauncher)"
fi

VERSION="$(dpkg-query -W -f='${Version}' ulauncher)"
if [ ! -d "$CALC_DIR" ] || [ ! -f "$WINDOW_DIR/UlauncherWindow.py" ]; then
    echo "Ulauncher-Dateien unter $UL_DIR nicht gefunden." >&2
    exit 1
fi

echo "== 1/4: Originale sichern (falls noch nicht geschehen) =="
backup() {
    if [ ! -f "$1.orig" ]; then
        sudo cp "$1" "$1.orig"
        echo "  Backup angelegt: $(basename "$1").orig"
    else
        echo "  Backup existiert schon: $(basename "$1").orig"
    fi
}
if [[ "$VERSION" == 5.15.* ]]; then
    backup "$CALC_DIR/CalcMode.py"
    backup "$CALC_DIR/CalcResultItem.py"
fi
# .orig nur vom unveraenderten Original (ohne unseren Marker) anlegen
if ! grep -q "$MARKER" "$WINDOW_DIR/UlauncherWindow.py"; then
    backup "$WINDOW_DIR/UlauncherWindow.py"
fi

echo "== 2/4: Patches installieren =="
if [[ "$VERSION" == 5.15.* ]]; then
    sudo cp "$SCRIPT_DIR/CalcHistory.py" "$CALC_DIR/CalcHistory.py"
    sudo cp "$SCRIPT_DIR/CalcResultItem.py" "$CALC_DIR/CalcResultItem.py"
    sudo cp "$SCRIPT_DIR/CalcMode.py" "$CALC_DIR/CalcMode.py"
    sudo rm -rf "$CALC_DIR/__pycache__"
    python3 -m py_compile "$CALC_DIR/CalcHistory.py" "$CALC_DIR/CalcResultItem.py" "$CALC_DIR/CalcMode.py"
    echo "  Calc-Patch installiert, Syntax geprueft"
else
    echo "  Ulauncher $VERSION ist nicht 5.15.x: Calc-Patch uebersprungen"
    echo "  (ab 5.16 hat Upstream einen eigenen, umgebauten Taschenrechner; unsere"
    echo "  CalcMode.py wuerde ihn kaputtmachen)."
fi

# Ctrl+A / Ctrl+E: sechs Zeilen hinter dem Ctrl+,-Zweig einfuegen.
# Auf Arbeitskopie, dann sudo cp; idempotent (Marker) und bricht ohne
# Aenderung ab, falls der Anker in dieser Version fehlt.
if grep -q "$MARKER" "$WINDOW_DIR/UlauncherWindow.py"; then
    echo "  Ctrl+A/E-Patch bereits vorhanden"
else
    WORK="$(mktemp --suffix=.py)"
    cp "$WINDOW_DIR/UlauncherWindow.py" "$WORK"
    python3 - "$WORK" "$MARKER" <<'PYEOF'
import re
import sys

path, marker = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    src = f.read()
anchor = re.compile(
    r"(        elif ctrl and keyname == 'comma':\n"
    r"            self\.activate_preferences\(\)\n)")
if len(anchor.findall(src)) != 1:
    sys.exit("Anker (Ctrl+,-Zweig) nicht eindeutig gefunden - "
             "andere Ulauncher-Version? Keine Aenderung.")
block = (
    "\n"
    f"        # {marker}, in every search mode\n"
    "        elif ctrl and keyname == 'a':\n"
    "            self.input.set_position(0)\n"
    "            return True\n"
    "        elif ctrl and keyname == 'e':\n"
    "            self.input.set_position(-1)\n"
    "            return True\n")
with open(path, 'w', encoding='utf-8') as f:
    f.write(anchor.sub(lambda m: m.group(1) + block, src))
PYEOF
    python3 -m py_compile "$WORK"
    sudo cp "$WORK" "$WINDOW_DIR/UlauncherWindow.py"
    rm -f "$WORK"
    sudo rm -rf "$WINDOW_DIR/__pycache__"
    echo "  Ctrl+A/E-Patch eingefuegt, Syntax geprueft"
fi

echo "== 3/4: 'Eingabe beim Schliessen behalten' aktivieren =="
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
if [ "$RESTART" = 1 ]; then
    pkill -f 'bin/ulauncher' 2>/dev/null || true
    sleep 1
    nohup ulauncher -v > /tmp/ulauncher-verbose.log 2>&1 &
    disown
    echo "  neu gestartet (Log: /tmp/ulauncher-verbose.log)"
else
    echo "  --no-restart: Ulauncher bitte selbst neu starten, damit der Patch greift."
fi

echo
echo "Fertig. Test: '2+2' eingeben -> Ergebnis + History-Zeilen sollten erscheinen;"
echo "Ctrl+A/Ctrl+E springen an Zeilenanfang/-ende."
