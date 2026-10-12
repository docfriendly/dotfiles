#!/bin/bash
# Picture-in-Picture: Prefix+P zeigt/versteckt ein Popup mit einem Live-Blick
# auf ein ANDERES tmux-Fenster. Tasten im Popup gehen direkt ans Zielfenster
# (kein Read-only-Modus mehr; fruehere Prefix+u-Sperre wurde am 12.10.2026
# abgeschafft, siehe Popup-Keymap in tmux.conf). Details/Bau-Protokoll:
# ~/Sync/vault/SECOND_BRAIN/tmux-config-popup/BERICHT_tmux-config-popup.md
#
# Zielfenster-Ermittlung (in dieser Reihenfolge):
#   1. gemerkte Verknuepfung: Fenster-Option @pip_target am aktuellen Fenster
#   2. Namenskonvention: gleichnamiges Fenster in Session "SSH"
#   3. Picker (choose-tree): Auswahl wird danach unter (1) gemerkt
#
# Aufruf ohne Argumente = normaler Toggle (Prefix+P).
# Aufruf mit --remember <cur_win> <chosen_win> = interner Callback des Pickers.
# Aufruf mit --zoom-toggle = interner Callback von Prefix+Z im Popup (kippt
#   zwischen 50x60% und Vollbild, siehe Schleife in show_popup).
# Aufruf mit --unlink = Verknuepfung des aktuellen Fensters bewusst loesen (Prefix+Alt+P).
#   Setzt @pip_target auf den Sentinel-Wert "$UNLINKED", damit Stufe 2
#   (Namenskonvention) beim naechsten Prefix+P NICHT automatisch wieder
#   verknuepft -- sonst wuerde ein gleichnamiges SSH-Fenster die Trennung
#   sofort rueckgaengig machen, noch bevor der Picker drankommt.
#
# Im Popup (Keymap Tabellen pip/pip_prefix in tmux.conf):
#   Prefix+Z  zwischen 50x60% und Vollbild wechseln (--zoom-toggle)
#   Prefix+P  Popup schliessen (Toggle), Prefix+d ebenso
#   Prefix+[  copy-mode im Zielfenster (Scrollback)

PIP_SESSION=_pip
UNLINKED="__unlinked__"
SCRIPT="$0"

show_popup() {
  local target="$1"
  tmux new-session -d -s "$PIP_SESSION"
  tmux link-window -k -s "$target" -t "$PIP_SESSION:0"
  # Eigene Key-Table nur fuer den Popup-Client (Bindings: tmux.conf, Tabellen
  # pip/pip_prefix) -- so wirkt Prefix+Z nur hier und nicht im normalen Fenster.
  # prefix/prefix2 None: sonst faengt der fest verdrahtete Prefix-Mechanismus
  # (globale Prefix-Table) die Taste ab, bevor die Tabelle "pip" greift.
  tmux set-option -t "$PIP_SESSION" key-table pip
  tmux set-option -t "$PIP_SESSION" prefix None
  tmux set-option -t "$PIP_SESSION" prefix2 None

  # Hinweiszeile: eine einzige farbige Zeile am oberen Rand der Pane (pane-
  # border-status top) mit den Popup-Kommandos. Der eigentliche tmux-
  # Statusbalken (unten) bleibt unangetastet. Das Zoom-Label liest die
  # globale Option @pip_zoom (siehe Schleife unten).
  tmux set-option -t "$PIP_SESSION" pane-border-status top
  tmux set-option -t "$PIP_SESSION" pane-border-format \
    "#[bg=colour108#,fg=black] PiP  |  Prefix+Z #{?#{==:#{@pip_zoom},1},Verkleinern,Vollbild}  |  Prefix+P/d Exit "

  # Zoom (Prefix+Z im Popup): ein display-popup laesst sich nach dem Oeffnen
  # nicht in der Groesse aendern. Deshalb ist Prefix+Z per
  # "detach-client -E" an --zoom-toggle gebunden: das kippt @pip_zoom,
  # setzt @pip_zoom_req und beendet damit das Popup. Diese Schleife sieht das
  # Flag und oeffnet dasselbe Ziel erneut in der anderen Groesse. Prefix+d /
  # Prefix+P setzen kein Flag -> Schleife endet, PiP ist zu.
  local client_w client_h popup_w popup_h popup_x pct_w pct_h
  client_w="$(tmux display-message -p '#{client_width}')"
  client_h="$(tmux display-message -p '#{client_height}')"
  tmux set-option -g @pip_zoom 0
  tmux set-option -gu @pip_zoom_req 2>/dev/null

  while :; do
    if [ "$(tmux show-options -gqv @pip_zoom)" = 1 ]; then
      pct_w=100; pct_h=100
    else
      pct_w=50;  pct_h=60
    fi

    # Feste, selbst berechnete Popup-Groesse statt tmux' eigener Prozent-
    # Berechnung ("-w 50% -h 60%"): das verlinkte Fenster behaelt sonst seine
    # zuletzt bekannte Groesse aus seiner Heimat-Session (z.B. SSH) bei, auch
    # wenn die stark von der Popup-Groesse abweicht -- ein frisch angehaengter
    # Client erzwingt trotz window-size=latest KEIN sofortiges Resize (mehrfach
    # empirisch geprueft, siehe tmux-config-popup/BERICHT_*.md). Ohne Fix zeigt
    # das Popup dann nur einen kleinen, oben links verankerten Ausschnitt mit
    # totem Rand drumherum, statt den Inhalt formatfuellend darzustellen.
    popup_w=$(( client_w * pct_w / 100 ))
    popup_h=$(( client_h * pct_h / 100 ))
    tmux resize-window -t "$PIP_SESSION:0" -x "$popup_w" -y "$popup_h"

    # -x R (statt einer Zahl) fuer die Popup-Position ist hier absichtlich
    # NICHT verwendet: sobald pane-border-status auf der Zielsession aktiv ist
    # (s.o.), berechnet tmux 3.7b die "R"-Position falsch und verankert das
    # Popup stattdessen links oben (Spalte 1) -- reproduzierbar leer getestet,
    # verschwindet mit einer explizit berechneten Spaltenzahl. Deshalb hier
    # der rechte Rand von Hand ausgerechnet statt tmux' eigener "R"-Symbolik.
    popup_x=$(( client_w - popup_w ))
    tmux display-popup -w "$popup_w" -h "$popup_h" -x "$popup_x" -y 0 -T "PiP: $target" -E \
      "tmux attach-session -t $PIP_SESSION"

    [ "$(tmux show-options -gqv @pip_zoom_req)" = 1 ] || break
    tmux set-option -gu @pip_zoom_req
    # Zwischenzeitlich per Prefix+P geschlossen (Session weg) -> nicht neu oeffnen.
    tmux has-session -t "$PIP_SESSION" 2>/dev/null || break
  done

  # resize-window setzt window-size als Nebeneffekt IMMER auf "manual" (auch
  # bei -A/-a) -- ohne Rueckbau bliebe das Zielfenster in seiner Heimat-
  # Session (z.B. SSH) dauerhaft auf die kleine Popup-Groesse eingefroren.
  # -A holt zuerst die Groesse der (jetzt einzigen) Heimat-Session zurueck,
  # das anschliessende Zuruecksetzen der Option macht das Fenster wieder
  # normal auto-groessenfaehig fuer kuenftige Attaches.
  tmux resize-window -t "$target" -A 2>/dev/null
  tmux set-window-option -t "$target" -u window-size 2>/dev/null

  # pane-border-status/-format sind Fenster-Optionen, keine Session-Optionen.
  # link-window haengt KEINE Kopie des Fensters in _pip ein, sondern denselben
  # Fenster-Objektverweis wie in der Heimat-Session -- das oben gesetzte
  # pane-border-status landet also direkt auf dem echten Fenster und bliebe
  # ohne diesen Rueckbau dauerhaft auch ausserhalb des Popups sichtbar.
  tmux set-window-option -t "$target" -u pane-border-status 2>/dev/null
  tmux set-window-option -t "$target" -u pane-border-format 2>/dev/null

  tmux kill-session -t "$PIP_SESSION" 2>/dev/null
}

if [ "$1" = "--remember" ]; then
  cur_win="$2"
  chosen="$3"
  tmux set-option -w -t "$cur_win" @pip_target "$chosen"
  show_popup "$chosen"
  exit 0
fi

if [ "$1" = "--zoom-toggle" ]; then
  if [ "$(tmux show-options -gqv @pip_zoom)" = 1 ]; then new=0; else new=1; fi
  tmux set-option -g @pip_zoom "$new"
  tmux set-option -g @pip_zoom_req 1
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
