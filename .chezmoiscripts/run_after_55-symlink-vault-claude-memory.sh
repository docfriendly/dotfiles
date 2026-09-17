#!/bin/bash
set -eufo pipefail

# ══════════════════════════════════════════════════════════════════
# CLAUDE-CODE MEMORY INS VAULT AUSLAGERN
# (läuft bei JEDEM Apply, analog zu run_after_45/50: Claude Code legt in
#  ~/.claude/projects/<projekt>/memory/ bei Bedarf neue, rein lokale
#  Verzeichnisse an - das ist der einzige Ort, an dem der
#  projektübergreifende Kontext-/Feedback-Speicher liegt, komplett
#  unversioniert und ungesichert. Anders als bei den Vault->Live-Symlinks
#  oben (SSH, Scripts) ist hier die LIVE-Seite die Quelle der Wahrheit:
#  Claude Code schreibt direkt dorthin, der Vault ist reines Backup.
#  Deshalb Richtung umgekehrt: beim ersten Auftauchen eines echten (noch
#  nicht verlinkten) memory/-Ordners dessen Inhalt einmalig nach
#  ~/Sync/vault/claude/memory/<projekt>/ verschieben und live durch einen
#  Symlink dorthin ersetzen - danach schreibt Claude Code direkt in den
#  Vault, Syncthing sichert laufend ohne dass `chezmoi apply` erneut
#  laufen muss. `find -type d` matcht nach der Migration nicht mehr (der
#  Pfad ist dann ein Symlink, `-type l`), macht den Lauf also von selbst
#  idempotent.
# ══════════════════════════════════════════════════════════════════

VAULT_MEMORY_ROOT="$HOME/Sync/vault/claude/memory"
mkdir -p "$VAULT_MEMORY_ROOT"

find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -type d -name memory -print0 2>/dev/null \
  | while IFS= read -r -d '' memdir; do
      project="$(basename "$(dirname "$memdir")")"
      vault_target="$VAULT_MEMORY_ROOT/$project"
      if [ -e "$vault_target" ]; then
        # Sollte nach der Migration nicht mehr vorkommen (live waere dann
        # ein Symlink, kein -type d mehr) - im Zweifel nichts anfassen,
        # lieber auffallen als Daten stillschweigend zu ueberschreiben.
        echo "run_after_55: $vault_target existiert bereits, aber $memdir ist noch ein echtes Verzeichnis - uebersprungen" >&2
        continue
      fi
      mv "$memdir" "$vault_target"
      ln -s "$vault_target" "$memdir"
    done
