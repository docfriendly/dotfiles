# dotfiles

Persönliche Konfiguration, verwaltet mit [chezmoi](https://chezmoi.io).

## Neue Maschine aufsetzen

Dieser eine Befehl installiert chezmoi selbst (Standalone-Binary, **keine**
Homebrew-Abhängigkeit), klont dieses Repo und wendet es sofort an:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <github-user>
```

Das löst automatisch die komplette Kette aus:

1. `run_once_before_10-install-homebrew.sh.tmpl` – installiert Homebrew
   (macOS: `/opt/homebrew`, Linux: `/home/linuxbrew/.linuxbrew`)
2. `run_once_before_20-install-starship-zoxide.sh.tmpl` – installiert
   starship & zoxide via brew
3. Dotfiles werden geschrieben (`.bashrc`, `.bash_aliases`, `.tool-versions`, ...)
4. `run_once_after_10-install-asdf-tools.sh.tmpl` – installiert asdf,
   registriert die Plugins und installiert alle Versionen aus `.tool-versions`

Chezmoi selbst landet dabei in `~/.local/bin/chezmoi` – dieser Pfad ist
bereits am Ende der `.bashrc` in `PATH` eingetragen.

Falls auf der Maschine schon Homebrew existiert, geht's alternativ auch mit
`brew install chezmoi && chezmoi init --apply <github-user>`.
