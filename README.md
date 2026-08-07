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

## Config-Speicherorte

Manche Configs liegen bewusst nicht am klassischen Ort, sondern unter dem
XDG-Standardpfad `~/.config/`:

- Git: `~/.config/git/config` (statt `~/.gitconfig`, git ≥ 1.7.12)
- tmux: `~/.config/tmux/tmux.conf` (statt `~/.tmux.conf`, tmux ≥ 3.1) –
  auch die TPM-Plugins landen dort, unter `~/.config/tmux/plugins/`
  (per `set-environment -g TMUX_PLUGIN_MANAGER_PATH` in der Config)

`.chezmoiremove` sorgt dafür, dass die alten Pfade (`~/.gitconfig`,
`~/.tmux.conf`) auf bereits eingerichteten Maschinen aktiv entfernt
werden, falls sie noch existieren. Auf einer echten Neuinstallation
existieren sie ohnehin nicht, dort greift das schlicht ins Leere.

## Nützliche Befehle

```bash
chezmoi diff                        # zeigt anstehende Änderungen, ohne sie anzuwenden
chezmoi apply --dry-run --verbose   # simuliert den kompletten Apply inkl. Skript-Reihenfolge
chezmoi state data                  # zeigt den kompletten lokalen State (siehe unten)
```

Der lokale State liegt in `~/.config/chezmoi/chezmoistate.boltdb`
(maschinenspezifisch, nicht im Repo). Darin merkt sich chezmoi u.a. pro
`run_once_`-Skript den SHA256-Hash seines gerenderten Inhalts plus
Zeitpunkt der letzten Ausführung (`scriptState`-Bucket) – ändert sich der
Skriptinhalt nicht, wird es bei künftigen `apply`-Läufen dauerhaft
übersprungen, auch wenn es intern idempotent ist.

## Bekannte Stolpersteine

**tmux-Plugins schlagen mit `unknown variable: TMUX_PLUGIN_MANAGER_PATH` fehl**

Passiert nur, wenn auf der Maschine schon ein tmux-Server läuft, *bevor*
`run_once_after_30-install-tmux-plugins.sh.tmpl` zum ersten Mal ausgeführt
wird (z.B. bei einer bestehenden Maschine, nicht bei einer echten
Neuinstallation). Ein laufender tmux-Server liest seine Config nur beim
eigenen Start – das `set-environment -g TMUX_PLUGIN_MANAGER_PATH ...` aus
`tmux.conf` landet dann nie im Server, und TPM findet die Variable nicht.

Fix: Config in den laufenden Server nachladen, danach `chezmoi apply`
erneut ausführen (das Skript ist idempotent, TPM wird nicht erneut
geklont):

```bash
tmux source-file ~/.config/tmux/tmux.conf
chezmoi apply
```

Auf einer frischen Maschine ohne laufenden tmux-Server tritt das Problem
nicht auf, da der Server beim allerersten Start automatisch die aktuelle
Config liest.

**PS: `chmod ... operation not permitted` unter `~/.config/...`**

Kommt vor, wenn irgendein Ordner unter `~/.config` versehentlich (meist
durch einen früheren `sudo`-Aufruf) `root:root` statt `harry:harry`
gehört – als normaler User darf man Rechte an Dateien, die einem nicht
selbst gehören, nicht per `chmod` ändern, auch nicht innerhalb des
eigenen Home-Verzeichnisses. Prüfen mit `stat <pfad>`, Fix:

```bash
sudo chown -R harry:harry <betroffener-ordner>
```

Danach `chezmoi apply` erneut ausführen.

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
