#!/bin/bash
# Aufgerufen aus iphone-mode.sh heraus (window-status-format /
# @window-status-format-row2, per #(...) mit #{window_id} als Argument) --
# tmux fuehrt das bei jedem Status-Redraw neu aus (status-interval, siehe
# tmux.conf.tmpl). Liest fuer JEDE Pane des uebergebenen Fensters (nicht nur
# die aktive -- ein Fenster kann mehrere Panes haben, s. Fund 21.09.2026,
# AGENTS:7) die von claude-pane-status-hook geschriebene Statusdatei und
# gibt bei busy/wartet den passenden #[bg=...]-Praefix aus, sonst nichts.
# Busy hat Vorrang vor wartet, falls mehrere Claude-Panes im selben Fenster
# unterschiedliche Zustaende haben.
#
# pane_current_command==claude-Guard: verhindert, dass eine nach Absturz
# (kein SessionEnd-Hook gefeuert) oder nach tmux-resurrect-Neustart noch
# herumliegende Statusdatei faelschlich Farbe zeigt, obwohl in der Pane gar
# kein Claude Code mehr laeuft (gleiches Problem wie in
# claude-tmux-resurrect-resume).
win="$1"
[ -n "$win" ] || exit 0

STATE_DIR="$HOME/.cache/claude-tmux-status"
state=none

while IFS=' ' read -r pane_id cmd; do
	[ "$cmd" = claude ] || continue
	f="$STATE_DIR/${pane_id#%}"
	[ -f "$f" ] || continue
	s=$(<"$f")
	if [ "$s" = busy ]; then
		state=busy
		break
	elif [ "$s" = waiting ] && [ "$state" != busy ]; then
		state=waiting
	fi
done < <(tmux list-panes -t "$win" -F '#{pane_id} #{pane_current_command}' 2>/dev/null)

case "$state" in
	busy) printf '#[bg=colour208,fg=black]' ;;
	waiting) printf '#[bg=colour46,fg=black]' ;;
esac
