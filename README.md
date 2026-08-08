# dotfiles

Persönliche Konfiguration, verwaltet mit [chezmoi](https://chezmoi.io).

## Neue Maschine aufsetzen

**Schritt 0, vor allem anderen:** Hostname explizit setzen, nicht dem
Installer/DHCP überlassen. `.chezmoidata.yaml` und der Vault-Scripts-
Mechanismus (siehe unten) sind über den Hostnamen verzweigt – ein falsch
geschriebener oder vom Installer generierter Hostname (`x220`,
`x230`, ...) führt sonst dazu, dass die falschen (oder gar keine)
maschinenspezifischen Werte greifen:

```bash
sudo hostnamectl set-hostname x220
```

Danach dieser eine Befehl: installiert chezmoi selbst (Standalone-Binary,
**keine** Homebrew-Abhängigkeit), klont dieses Repo und wendet es sofort an:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <github-user>
```

Das löst automatisch die komplette Kette aus:

1. `run_once_before_10-install-homebrew.sh.tmpl` – installiert Homebrew
   (macOS: `/opt/homebrew`, Linux: `/home/linuxbrew/.linuxbrew`)
2. `run_once_before_15-install-age.sh.tmpl` – installiert `age` per
   Homebrew (für Passphrase-verschlüsselte `encrypted_`-Dateien, siehe
   [Verschlüsselte Dateien](#verschlüsselte-dateien-age) unten; muss vor
   der Dateiverarbeitung im nächsten Schritt bereitstehen)
3. Dotfiles werden geschrieben (`.bashrc`, `.bash_aliases`, `.Brewfile`,
   `.tool-versions`, ...) – bei `encrypted_`-Dateien fragt chezmoi an
   dieser Stelle interaktiv nach der age-Passphrase
4. `run_once_after_10-install-brew-bundle.sh.tmpl` – installiert alle
   Pakete aus `~/.Brewfile` (starship, zoxide, asdf, ripgrep, fzf, ...)
   und richtet die fzf-Shell-Integration nicht-interaktiv ein
5. `run_once_after_20-install-asdf-tools.sh.tmpl` – registriert die
   asdf-Plugins und installiert alle Versionen aus `.tool-versions`
6. `run_once_after_30-install-tmux-plugins.sh.tmpl` – klont TPM (Tmux
   Plugin Manager) und installiert alle in `.tmux.conf` deklarierten
   Plugins nicht-interaktiv
7. `run_once_after_35-install-nomachine.sh.tmpl` – nur unter Linux
   (macOS läuft über den `cask "nomachine"` im Brewfile, siehe Schritt 4):
   lädt das gepinnte `.deb` von NoMachine herunter und installiert es per
   `sudo apt-get install` – fragt dabei einmalig interaktiv nach dem
   sudo-Passwort. Gibt kein apt/nala-Paket, daher direkter Download;
   Version steht fest im Skript, da NoMachine keine stabile "latest"-URL
   anbietet (siehe Kommentar im Skript zum Aktualisieren)
8. `run_after_50-symlink-vault-scripts.sh.tmpl` – verlinkt private
   Scripte aus dem Syncthing-Vault nach `~/.local/bin`, siehe
   [Vault-Scripts & Custom Pages](#vault-scripts--custom-pages-syncthing)
   unten

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

## Vault-Scripts & Custom Pages (Syncthing)

`~/Sync/vault` ist ein per Syncthing zwischen den Maschinen synchronisierter
Ordner (kein Git, siehe [TODO_syncthing.md](TODO_syncthing.md) für den
größeren Plan dahinter) – dorthin gehört alles, was privat bleiben soll
(potenziell auch nach dem geplanten öffentlichen Mirror dieses Repos) oder
das nicht auf jeder Maschine identisch sein soll.

**Private Scripte** (`~/Sync/vault/script/<hostname>/`, z.B. `script/x220/`):
Für jede bekannte Maschine ein eigener Ordner, plus `script/common/` für
Scripte, die auf mehreren/allen Maschinen verfügbar sein sollen, aber
trotzdem nicht ins (ggf. später öffentliche) Git-Repo gehören.
`run_after_50-symlink-vault-scripts.sh.tmpl` verlinkt bei jedem
`chezmoi apply` automatisch alle Dateien aus `script/<hostname>/` und
`script/common/` nach `~/.local/bin/` – neues Script in den passenden
Ordner legen, `chezmoi apply`, fertig, kein Repo-Commit nötig. Das Skript
räumt auch verwaiste Symlinks auf, wenn ein Script im Vault gelöscht wird.

Soll ein Script stattdessen auf **allen** Maschinen identisch und
versioniert sein, ist der vault-Mechanismus der falsche Ort – dafür ganz
normal eine `executable_dot_local/bin/<name>`-Datei im Repo anlegen (per
`chezmoi add`). Für eine feste Teilmenge von Maschinen: ebenso eine normale
Repo-Datei, aber per `.chezmoiignore`-Template auf den nicht gewünschten
Hostnamen ausschließen.

**Custom tealdeer-Pages** (`~/Sync/vault/tealdeer/pages/`): wird per
nativem chezmoi-`symlink_`-Eintrag (`dot_local/share/tealdeer/symlink_pages.tmpl`)
nach `~/.local/share/tealdeer/pages` verlinkt. Auch hier kein
Reihenfolge-Problem mit Syncthing: Der Symlink kann angelegt werden, bevor
der Ordner durch Syncthing befüllt ist – er zeigt dann kurz ins Leere und
heilt sich von selbst, sobald die Dateien ankommen.

Beide Mechanismen hängen am Hostnamen und nutzen denselben Guard wie
`dot_config/tmux/tmux.conf.tmpl`: ein unbekannter Hostname lässt
`chezmoi apply` bewusst fehlschlagen statt still eine leere/falsche
Maschine anzunehmen (siehe [Maschinenspezifische Werte](#maschinenspezifische-werte)
unten).

## Verschlüsselte Dateien (age)

`.chezmoi.toml.tmpl` setzt `encryption = "age"` mit `[age] passphrase = true`
– Passphrase-Modus, nicht Keypair-Modus. Der Unterschied: Keypair-Modus
bräuchte eine private Schlüsseldatei, die selbst wieder sicher auf jede
neue Maschine transportiert werden müsste (Henne-Ei-Problem). Bei
Passphrase-Modus gibt es keine Schlüsseldatei – nur ein Passwort, das man
sich merkt und bei Bedarf interaktiv eingibt.

chezmois eingebautes age unterstützt **keine** Passphrasen (nur Keypair),
daher braucht dieser Modus zwingend das externe `age`-Kommando im
`$PATH` – siehe Schritt 2 oben. `encrypted_`-Dateien werden damit direkt
im Repo verschlüsselt versioniert; die Passphrase wird abgefragt, sobald
chezmoi eine solche Datei anwenden oder anzeigen muss (`apply`, `diff`,
`status`).

Aktuell verwaltet dieses Repo noch keine `encrypted_`-Dateien – der
Mechanismus ist vorbereitet, aber ungenutzt.

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
