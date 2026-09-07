#!/bin/bash
# Picture-in-Picture: Prefix+P zeigt/versteckt ein Popup mit einem read-only
# Live-Blick auf ein ANDERES tmux-Fenster. Details/Bau-Protokoll:
# ~/Sync/vault/SECOND_BRAIN/tmux-config-popup/BERICHT_tmux-config-popup.md
#
# Zielfenster-Ermittlung (in dieser Reihenfolge):
#   1. gemerkte Verknuepfung: Fenster-Option @pip_target am aktuellen Fenster
#   2. Namenskonvention: gleichnamiges Fenster in Session "SSH"
#   3. Picker (choose-tree): Auswahl wird danach unter (1) gemerkt
#
# Aufruf ohne Argumente = normaler Toggle (Prefix+P).
# Aufruf mit --remember <cur_win> <chosen_win> = interner Callback des Pickers.
# Aufruf mit --unlink = Verknuepfung des aktuellen Fensters bewusst loesen (Prefix+Alt+P).
#   Setzt @pip_target auf den Sentinel-Wert "$UNLINKED", damit Stufe 2
#   (Namenskonvention) beim naechsten Prefix+P NICHT automatisch wieder
#   verknuepft -- sonst wuerde ein gleichnamiges SSH-Fenster die Trennung
#   sofort rueckgaengig machen, noch bevor der Picker drankommt.
#
# Read/Write innerhalb des Popups: Prefix+u ist NICHT hier implementiert,
# sondern direkt in tmux.conf an "switch-client -r" gebunden -- ein
# run-shell-Wrapper (auch mit korrekter interner Logik) wird von einem
# read-only-Client kategorisch abgelehnt ("Client is read only"), nur an
# detach-client/switch-client gebundene Tasten funktionieren dort (man tmux,
# Abschnitt attach-session). Siehe BERICHT fuer die volle Herleitung.

PIP_SESSION=_pip
UNLINKED="__unlinked__"
SCRIPT="$0"

show_popup() {
  local target="$1"
  tmux new-session -d -s "$PIP_SESSION"
  tmux link-window -k -s "$target" -t "$PIP_SESSION:0"

  # Feste, selbst berechnete Popup-Groesse statt tmux' eigener Prozent-
  # Berechnung ("-w 50% -h 60%"): das verlinkte Fenster behaelt sonst seine
  # zuletzt bekannte Groesse aus seiner Heimat-Session (z.B. SSH) bei, auch
  # wenn die stark von der Popup-Groesse abweicht -- ein frisch angehaengter
  # Client erzwingt trotz window-size=latest KEIN sofortiges Resize (mehrfach
  # empirisch geprueft, siehe tmux-config-popup/BERICHT_*.md). Ohne Fix zeigt
  # das Popup dann nur einen kleinen, oben links verankerten Ausschnitt mit
  # totem Rand drumherum, statt den Inhalt formatfuellend darzustellen.
  local client_w client_h popup_w popup_h popup_x
  client_w="$(tmux display-message -p '#{client_width}')"
  client_h="$(tmux display-message -p '#{client_height}')"
  popup_w=$(( client_w * 50 / 100 ))
  popup_h=$(( client_h * 60 / 100 ))
  tmux resize-window -t "$PIP_SESSION:0" -x "$popup_w" -y "$popup_h"

  # Read/Write-Statusanzeige: eine einzige farbige Zeile am oberen Rand der
  # Pane (pane-border-status top), traegt Zustand + beide Kommandos. Der
  # eigentliche tmux-Statusbalken (unten) bleibt unangetastet.
  tmux set-option -t "$PIP_SESSION" pane-border-status top
  tmux set-option -t "$PIP_SESSION" pane-border-format \
    "#{?client_readonly,#[bg=red#,fg=white] LESEN  |  Prefix+u Schreiben  |  Prefix+d Exit ,#[bg=green#,fg=black] SCHREIBEN  |  Prefix+u Lesen  |  Prefix+d Exit }"

  # -x R (statt einer Zahl) fuer die Popup-Position ist hier absichtlich
  # NICHT verwendet: sobald pane-border-status auf der Zielsession aktiv ist
  # (s.o.), berechnet tmux 3.7b die "R"-Position falsch und verankert das
  # Popup stattdessen links oben (Spalte 1) -- reproduzierbar leer getestet,
  # verschwindet mit einer explizit berechneten Spaltenzahl. Deshalb hier
  # der rechte Rand von Hand ausgerechnet statt tmux' eigener "R"-Symbolik.
  popup_x=$(( client_w - popup_w ))
  tmux display-popup -w "$popup_w" -h "$popup_h" -x "$popup_x" -y 0 -T "PiP: $target" -E \
    "tmux attach-session -r -t $PIP_SESSION"

  # resize-window setzt window-size als Nebeneffekt IMMER auf "manual" (auch
  # bei -A/-a) -- ohne Rueckbau bliebe das Zielfenster in seiner Heimat-
  # Session (z.B. SSH) dauerhaft auf die kleine Popup-Groesse eingefroren.
  # -A holt zuerst die Groesse der (jetzt einzigen) Heimat-Session zurueck,
  # das anschliessende Zuruecksetzen der Option macht das Fenster wieder
  # normal auto-groessenfaehig fuer kuenftige Attaches.
  tmux resize-window -t "$target" -A 2>/dev/null
  tmux set-window-option -t "$target" -u window-size 2>/dev/null
  tmux kill-session -t "$PIP_SESSION" 2>/dev/null
}

if [ "$1" = "--remember" ]; then
  cur_win="$2"
  chosen="$3"
  tmux set-option -w -t "$cur_win" @pip_target "$chosen"
  show_popup "$chosen"
  exit 0
fi

if [ "$1" = "--unlink" ]; then
  cur_win="$(tmux display-message -p '#{session_name}:#{window_index}')"
  tmux set-option -w -t "$cur_win" @pip_target "$UNLINKED"
  tmux display-message "PiP-Verknuepfung aufgehoben -- naechstes Prefix+P startet den Picker neu"
  exit 0
fi

# Toggle: PiP schon offen -> einfach schliessen.
if tmux has-session -t "$PIP_SESSION" 2>/dev/null; then
  tmux kill-session -t "$PIP_SESSION"
  exit 0
fi

CUR_WIN="$(tmux display-message -p '#{session_name}:#{window_index}')"
TARGET="$(tmux show-options -wv -t "$CUR_WIN" @pip_target 2>/dev/null)"

# Bewusst getrennt (Prefix+Alt+P) -> Stufe 2 (Namenskonvention) NICHT versuchen,
# sonst wuerde ein gleichnamiges SSH-Fenster sofort wieder automatisch
# verknuepfen. Direkt zu Stufe 3 (Picker).
if [ "$TARGET" = "$UNLINKED" ]; then
  TARGET=""
  tmux choose-tree -Zw "run-shell \"$SCRIPT --remember '$CUR_WIN' '%%'\""
  exit 0
fi

# 2. Namenskonvention: gleichnamiges Fenster in Session SSH
if [ -z "$TARGET" ]; then
  CUR_NAME="$(tmux display-message -p '#{window_name}')"
  if tmux list-windows -t SSH -F '#{window_name}' 2>/dev/null | grep -qx "$CUR_NAME"; then
    TARGET="SSH:$CUR_NAME"
    tmux set-option -w -t "$CUR_WIN" @pip_target "$TARGET"
  fi
fi

# 3. Picker, falls weder gemerkt noch per Konvention gefunden
if [ -z "$TARGET" ]; then
  tmux choose-tree -Zw "run-shell \"$SCRIPT --remember '$CUR_WIN' '%%'\""
  exit 0
fi

show_popup "$TARGET"
