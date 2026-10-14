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
# Aufruf mit --unlink-popup = Prefix+P im Popup: Ausgangsfenster (@pip_origin)
#   entkoppeln, Popup schliessen.
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
#   Prefix+P  Zuordnung loesen UND Popup schliessen (--unlink-popup); das
#             naechste Prefix+P im Ausgangsfenster startet den Picker neu
#   Prefix+d  Popup nur schliessen, Zuordnung bleibt
#   Prefix+[  copy-mode im Zielfenster (Scrollback)
#
# Gespeicherte Ziele sind Namen ("SSH:server"), keine Indizes: ueberleben
# Umsortieren und Ersetzen des Fensters. Existiert/eindeutig? -> valid_target;
# sonst Rueckfall auf Namenskonvention bzw. Picker (auch fuer Alt-Werte wie
# "=SSH:2." aus dem Picker frueherer Staende).

PIP_SESSION=_pip
UNLINKED="__unlinked__"
SCRIPT="$0"

# normalize <target>: Picker liefert "=SSH:2." (Index) -> "Session:Fenstername".
# Namen mit ":" oder "." sind als tmux-Ziel mehrdeutig -> dann Fenster-ID (@N).
normalize() {
  local n id
  n="$(tmux display-message -p -t "$1" '#{session_name}:#{window_name}' 2>/dev/null)"
  id="$(tmux display-message -p -t "$1" '#{window_id}' 2>/dev/null)"
  [ -n "$n" ] || { printf '%s' "$1"; return; }
  case "${n#*:}" in *[:.]*) printf '%s' "$id" ;; *) printf '%s' "$n" ;; esac
}

# valid_target <target>: Fenster-ID existiert bzw. "Session:Name" trifft genau
# EIN Fenster (exakter Name). Alt-Werte mit Index/"="/"." gelten als ungueltig.
valid_target() {
  local t="$1" sess name
  [ -n "$t" ] || return 1
  case "$t" in
    @*) tmux display-message -p -t "$t" '#{window_id}' >/dev/null 2>&1; return ;;
    *:*) ;;
    *) return 1 ;;
  esac
  sess="${t%%:*}"; name="${t#*:}"
  [ "$(tmux list-windows -t "=$sess" -F '#{window_name}' 2>/dev/null | grep -cxF -- "$name")" -eq 1 ]
}

show_popup() {
  local target="$1" origin="$2"
  # Ausgangsfenster merken, damit Prefix+P im Popup (--unlink-popup) es loesen kann.
  tmux set-option -g @pip_origin "$origin"
  tmux set-option -gu @pip_unlinked 2>/dev/null
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
    "#[bg=colour108#,fg=black] PiP  |  Prefix+Z #{?#{==:#{@pip_zoom},1},Verkleinern,Vollbild}  |  Prefix+P Zuordnung loesen  |  Prefix+d Exit "

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

  # Per Prefix+P im Popup entkoppelt? Meldung hier, vom aeusseren Skript aus: der
  # Popup-Client ist beim Ausloesen schon weg.
  if [ "$(tmux show-options -gqv @pip_unlinked)" = 1 ]; then
    tmux set-option -gu @pip_unlinked
    tmux display-message -d 3000 "PiP-Zuordnung geloest -- naechstes Prefix+P startet den Picker"
  fi
  tmux set-option -gu @pip_origin 2>/dev/null

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
  chosen="$(normalize "$3")"
  tmux set-option -w -t "$cur_win" @pip_target "$chosen"
  show_popup "$chosen" "$cur_win"
  exit 0
fi

if [ "$1" = "--unlink-popup" ]; then
  origin="$(tmux show-options -gqv @pip_origin)"
  if [ -n "$origin" ]; then
    tmux set-option -w -t "$origin" @pip_target "$UNLINKED"
    tmux set-option -g @pip_unlinked 1
  fi
  tmux kill-session -t "$PIP_SESSION" 2>/dev/null
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
# Gespeichertes Ziel weg/mehrdeutig/Alt-Format -> wie "nichts gemerkt" behandeln
# (Stufe 2, dann Picker). Der Sentinel UNLINKED bleibt unberuehrt.
if [ -n "$TARGET" ] && [ "$TARGET" != "$UNLINKED" ] && ! valid_target "$TARGET"; then
  TARGET=""
fi

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

show_popup "$TARGET" "$CUR_WIN"
# Exit-Status bewusst 0: wurde das Popup per Prefix+P aus dem Popup heraus
# geschlossen (kill-session durch die zweite Skriptinstanz), schlaegt das
# abschliessende kill-session in show_popup fehl -> tmux meldete sonst
# "...tmux-pip-toggle.sh returned 1".
exit 0
