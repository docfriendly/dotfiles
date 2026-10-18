# Hilfsfunktionen fuer "weiche" Bootstrap-Schritte: Fehler protokollieren statt
# den ganzen Apply abzubrechen. Einbinden per template-Aufruf "softstep.sh"
# (Aktion mit doppelten geschweiften Klammern, siehe run_after_75).
# Harte Abhaengigkeiten (Preflight, Build-Pakete, Homebrew) bleiben fail-fast.
#
#   WARN_SRC=<name>      vor dem ersten warn/note setzen (Quelle im Log)
#   warn "Text"          Fehler/Problem: ~/.cache/chezmoi-warnungen.log + stderr
#   note "Text"          Hinweis fuer den Menschen: ~/.cache/chezmoi-hinweise.log
#   stamp_ok  <n> <key>  0, wenn der Schritt mit diesem key schon gelang
#   stamp_set <n> <key>  Erfolg merken (erst nach Erfolg, nie nach warn!)
#
# Wiederholung: weiche Schritte laufen als run_after bei JEDEM Apply, ueberspringen
# sich aber ueber den Stempel (~/.cache/chezmoi-stamps/<n>), solange <key> (z.B. ein
# Hash der Eingabedatei) gleich bleibt und der Schritt zuletzt gelang. Ein
# warn setzt keinen Stempel, der naechste Apply versucht es deshalb erneut.
# Run_once taugt dafuer nicht: Exit 0 gilt dort als erledigt, nie wiederholt.
# Die Logs zeigt run_after_99-summary am Ende des Apply und leert sie.
CHEZMOI_CACHE="$HOME/.cache"
CHEZMOI_STAMPS="$CHEZMOI_CACHE/chezmoi-stamps"
warn() {
  mkdir -p "$CHEZMOI_CACHE"
  printf '%s  [%s] %s\n' "$(date '+%F %T')" "${WARN_SRC:-?}" "$*" >> "$CHEZMOI_CACHE/chezmoi-warnungen.log"
  echo "WARNUNG [${WARN_SRC:-?}]: $*" >&2
}
note() {
  mkdir -p "$CHEZMOI_CACHE"
  printf '%s\n' "$*" >> "$CHEZMOI_CACHE/chezmoi-hinweise.log"
}
stamp_ok() { [ -f "$CHEZMOI_STAMPS/$1" ] && [ "$(cat "$CHEZMOI_STAMPS/$1")" = "$2" ]; }
stamp_set() { mkdir -p "$CHEZMOI_STAMPS"; printf '%s' "$2" > "$CHEZMOI_STAMPS/$1"; }
