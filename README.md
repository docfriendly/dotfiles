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
2. Dotfiles werden geschrieben (`.bashrc`, `.bash_aliases`, `.Brewfile`,
   `.tool-versions`, ...)
3. `run_once_after_10-install-brew-bundle.sh.tmpl` – installiert alle
   Pakete aus `~/.Brewfile` (starship, zoxide, asdf, ripgrep, fzf, ...)
   und richtet die fzf-Shell-Integration nicht-interaktiv ein
4. `run_once_after_20-install-asdf-tools.sh.tmpl` – registriert die
   asdf-Plugins und installiert alle Versionen aus `.tool-versions`
5. `run_once_after_30-install-tmux-plugins.sh.tmpl` – klont TPM (Tmux
   Plugin Manager) und installiert alle in `.tmux.conf` deklarierten
   Plugins nicht-interaktiv

Chezmoi selbst landet dabei in `~/.local/bin/chezmoi` – dieser Pfad ist
bereits am Ende der `.bashrc` in `PATH` eingetragen.

Falls auf der Maschine schon Homebrew existiert, geht's alternativ auch mit
`brew install chezmoi && chezmoi init --apply <github-user>`.

## Maschinenspezifische Werte

`.chezmoi.toml.tmpl` fragt bei `chezmoi init` interaktiv nach Git-`name`
und `email` (landet maschinenlokal in `~/.config/chezmoi/chezmoi.toml`,
nie im Repo).

`.chezmoidata.yaml` enthält eine zentrale, versionierte Tabelle für Werte,
die pro bekannter Maschine fest unterschiedlich sein sollen (z.B.
`.tmux.conf`s Statusleisten-Farbe), verzweigt über `.chezmoi.hostname`.
Kommt eine neue Maschine mit unbekanntem Hostnamen dazu, bricht
`chezmoi apply` dort absichtlich mit einer Fehlermeldung ab – erst einen
Eintrag unter `machines.<hostname>` in `.chezmoidata.yaml` ergänzen,
dann erneut anwenden.
