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
cd ~ && sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply docfriendly
```

Zwei Stolpersteine, beide auf ihht aufgefallen:

- **`cd ~` ist nötig:** Der Installer legt `./bin/chezmoi` im *aktuellen*
  Verzeichnis an. In `/home` o. ä. scheitert er mit
  `install: cannot change permissions of 'bin'`.
- **Echte Login-Shell des Ziel-Users:** Nach `su harry` (ohne `-`) bleibt
  `$HOME` beim alten User, chezmoi bricht dann mit
  `open /home/<alter-user>/.config/chezmoi: permission denied` ab oder
  schreibt ins falsche Home. Also direkt als der Ziel-User einloggen oder
  `su - harry` benutzen; vorher `echo $HOME` prüfen.
- **Build-Pakete vorher installieren (Debian/MX):** asdf kompiliert Python
  und Ruby aus dem Quelltext. Ohne die `-dev`-Pakete wird Python still ohne
  `ssl` & Co. gebaut, Ruby bricht ab (`fiddle`/libffi, `psych`/libyaml):

  ```bash
  sudo apt install build-essential libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev libffi-dev libyaml-dev liblzma-dev \
    libncurses-dev tk-dev uuid-dev libgdbm-dev xz-utils curl git
  ```

- **`/tmp` kann ein kleines tmpfs sein:** Fehlgeschlagene `python-build`/
  `ruby-build`-Läufe lassen ihr Build-Verzeichnis liegen. Auf einem Host mit
  2 GB tmpfs war `/tmp` nach zwei Fehlversuchen voll, danach scheiterte sogar
  der Download (`curl: (23) Failure writing output`). Das asdf-Skript baut
  deshalb unter `~/.cache/asdf-build`. Reste auf alten Hosts:
  `rm -rf /tmp/*-build.*` und `df -h /tmp` prüfen.

Wer den Verlauf mitschneiden will (Fehlersuche, Dokumentation), startet den
Einzeiler unter `script`; das protokolliert die komplette Terminalausgabe:

```bash
cd ~ && script -q -c 'sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply docfriendly' \
  ~/bootstrap-$(hostname)-$(date +%F).log
```

`docfriendly` ist ein öffentlicher **Lese-Mirror** auf GitHub (Push-Mirror,
automatisch synchronisiert vom primären, privaten Forgejo-Repo unter
`forgejo.tipi.lan:8195/harry/dotfiles`, nur per VPN erreichbar). Der Mirror
existiert nur, damit dieser Bootstrap-Einzeiler auch auf einer brandneuen
Maschine ohne VPN-Zugang funktioniert – täglich gearbeitet (Commits,
`git push`) wird weiterhin gegen den Forgejo-Remote, niemals direkt gegen
GitHub.

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
4. **Alle `sudo`-Skripte zuerst, die langen Skripte zuletzt** (seit
   09.10.2026): Das sudo-Passwort wird früh abgefragt (`sudo -v` im
   Preflight, `run_once_before_02`), danach kann man sich zurücklehnen.
   chezmoi bricht beim ersten Fehler ab – kurze, fehleranfällige
   Installer (Downloads, apt) laufen deshalb vor dem stundenlangen
   Kompilieren. Reihenfolge der `after`-Skripte: 15, 35–44, 46, 51–53
   (sudo/apt/Downloads), dann 70 (Brew-Bundle), 72 (asdf), 74 (tmux),
   75 (nvim). Das sudo-Ticket läuft nach 15 min ab; deshalb darf nach
   den sudo-Skripten kein weiteres sudo mehr kommen.
5. `run_after_35-install-nomachine.sh.tmpl` – nur unter Linux (läuft bei
   jedem Apply, idempotent):
   installiert **NoMachine 9** aus einem `.deb` im Vault
   (`~/Sync/vault/script/common/vendor/nomachine_9.*_amd64.deb`, per
   `sudo apt-get install`). Kein Download: NoMachine 10 (seit 30.07.2026)
   hat den kostenlosen Server abgeschafft (Abo oder 14-Tage-Evaluierung),
   die 9.x-Pakete bietet die Download-Seite nicht mehr an. Das Skript
   lehnt Pakete mit Version != 9.x ab und endet ohne `.deb` mit Hinweis
   und Exit 0. Quelle des `.deb`: der Drittanbieter-Mirror
   `mikorist/nomachine-free-9` (9.8.2, SHA256 im Skriptkommentar; Skripte und
   fast alle Dateien gegen das offizielle 9.10.3 geprüft). **`dpkg-repack`
   taugt nicht** (nur ein 29-KB-Stub, die Nutzlast kennt dpkg nicht). Direkt
   nach der Installation ruft das Skript `nxupdatecli --upgrade` auf; der
   Updater (kein `.deb`, er ersetzt Dateien in `/usr/NX`) macht daraus das
   offizielle 9.10.x (ihht: 68 Dateien, ~3 min, Internet nötig). Vor einer
   Neuinstallation müssen `nomachine` **und** `nomachine-personal-edition`
   per `dpkg --purge` samt `rm -rf /usr/NX /etc/NX /var/NX` entfernt sein; das
   Skript bricht bei Resten mit Bereinigungsbefehl ab. Auf macOS gilt weiter
   der `cask "nomachine"` im Brewfile (liefert 10, braucht dort Lizenz bzw.
   Player-Nutzung)
6. `run_onchange_after_70-install-brew-bundle.sh.tmpl` – installiert alle
   Pakete aus `~/.Brewfile` (starship, zoxide, asdf, ripgrep, fzf, ...)
   und richtet die fzf-Shell-Integration nicht-interaktiv ein
7. `run_once_after_72-install-asdf-tools.sh.tmpl` – registriert die
   asdf-Plugins und installiert alle Versionen aus `.tool-versions`
   (kompiliert Python/Ruby, dauert)
   `run_after_74-install-tmux-plugins.sh.tmpl` – klont TPM (Tmux
   Plugin Manager) und installiert alle in `.tmux.conf` deklarierten
   Plugins nicht-interaktiv; `run_after_75-install-nvim-plugins`
   holt die LazyVim-Plugins. Beide sind **weiche Schritte**: Fehler brechen den
   Apply nicht ab, sondern landen im Warnlog; ein Stempel
   (`~/.cache/chezmoi-stamps/`, Hash von `tmux.conf` bzw. `lazy-lock.json`)
   sorgt dafür, dass erst ein erfolgreicher Lauf übersprungen wird. Hilfsfunktionen
   `warn`/`note`/`stamp_ok`/`stamp_set` in `.chezmoitemplates/softstep.sh`;
   `run_after_99-summary` zeigt am Ende alle Warnungen und Hinweise und leert
   die Logs. (Grund: auf praxis-eiffel brach 75 am 18.10.2026 mit einem
   Mason-Race ab, `run_once` hätte das nie wiederholt.) `tree-sitter-cli` kommt
   aus dem Brewfile, damit LazyVim nicht auf Mason ausweicht.
   `run_after_77-syncthing-device-id` startet Syncthing auf einem frischen Host
   einmal, liest die Geräte-ID und zeigt sie im Abschlussblock, solange der Host
   noch mit niemandem gekoppelt ist. Der Autostart-Cron ist
   `run_onchange_after_76` (nach dem Brew-Bundle, sonst fehlt `syncthing`).
8. `run_once_after_42-configure-sshd-iphone-acceptenv.sh.tmpl` – nur unter
   Linux: ergänzt `AcceptEnv IPHONE_CLIENT*` in `/etc/ssh/sshd_config` und
   lädt `sshd` neu, siehe [Termius/iPhone: tmux-Statuszeile](#termiusiphone-tmux-statuszeile)
   unten
9. `run_after_45-symlink-vault-ssh.sh.tmpl` – verlinkt private SSH-Keys,
   `config` etc. aus dem Syncthing-Vault nach `~/.ssh`, siehe
   [Vault-Scripts, SSH & Custom Pages](#vault-scripts-ssh--custom-pages-syncthing)
   unten
10. `run_after_50-symlink-vault-scripts.sh.tmpl` – verlinkt private
    Scripte aus dem Syncthing-Vault nach `~/.local/bin`, siehe selbiger
    Abschnitt

Chezmoi selbst landet dabei in `~/.local/bin/chezmoi` – dieser Pfad ist
bereits am Ende der `.bashrc` in `PATH` eingetragen.

Falls auf der Maschine schon Homebrew existiert, geht's alternativ auch mit
`brew install chezmoi && chezmoi init --apply docfriendly`.

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

## XFCE-Panel (MX Linux)

`dot_config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml` sowie die
Plugin-Configs unter `dot_config/xfce4/panel/*.rc` (`docklike-2.rc`,
`netload-14.rc`, `xfce4-timer-plugin-21.rc`) versionieren die persönliche
Taskleisten-Konfiguration.

**Wichtig zum Zeitpunkt, wann Änderungen wirklich greifen:** `xfconfd`
(der Daemon hinter allen `xfce-perchannel-xml`-Dateien, auch `thunar.xml`
und `xfce4-terminal.xml` weiter unten) hat **keinen** Dateisystem-Watcher
auf diese Dateien (geprüft im `xfconfd`-/`libxfconf`-Quellcode, Stand
08/2026 – kein `GFileMonitor`/inotify irgendwo im Daemon). Er liest eine
Channel-Datei nur **einmal** beim ersten Zugriff nach dem eigenen Start
und schreibt sie danach nur noch bei eigenen Property-Changes zurück. Ein
`chezmoi apply` während einer laufenden Session ändert also nur die Datei
auf der Platte – wirksam wird der neue Stand typischerweise erst nach
Neustart der jeweiligen App bzw. von `xfconfd` selbst (Logout/Login oder
`xfce4-panel -r` fürs Panel). Deshalb bei allen drei Dateien: **komplette
Live-Datei versionieren, nicht nur die eine geänderte Property** – sonst
würde beim nächsten `xfconfd`-Neustart der Rest (Farben, Font, Fenster-
Layout, ...) still auf die Defaults zurückfallen, weil er dann schlicht
nicht mehr in der Datei steht, aus der frisch geladen wird.

Zwei Dinge, die bei einer Neuinstallation auf einer **anderen Distro als
MX Linux** zu beachten sind:

- **Drittanbieter-Panel-Plugins selbst installieren.** `docklike`,
  `netload`, `cpugraph`, `xfce4-timer-plugin` und `whiskermenu` sind keine
  Kernbestandteile von xfce4-panel und werden von chezmoi/Homebrew nicht
  automatisch installiert. Fehlen sie, bleibt der jeweilige Panel-Slot
  leer bzw. fehlerhaft – der Rest der Panel funktioniert trotzdem, es
  bricht nichts ab.
- **MX-spezifische Einträge sind kosmetisch tot, nicht fatal.**
  Whiskermenu-Favoriten (`mx-tools.desktop`,
  `mx-packageinstaller.desktop`, ...), das Icon
  `/usr/share/icons/mxfcelogo-rounded.png` sowie die
  `mx-updater`/`apt-notifier.py`-Einträge im Systray existieren auf
  anderen Distros nicht. XFCE ignoriert fehlende `.desktop`-Dateien und
  Icons einfach (Fallback-Icon) – wirkt nur unaufgeräumt, verhindert aber
  kein `chezmoi apply`.

Lohnt sich aktuell nicht vorab zu templaten/bereinigen – erst relevant,
falls regelmäßig zwischen MX und einer anderen Distro gewechselt wird.

### Thunar: kein Hover-Select

`dot_config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml` versioniert die
komplette Live-Datei (siehe Hinweis zu `xfconfd` oben). Die eigentlich
gewollte Änderung ist `misc-single-click` auf `false`: Thunar koppelt
"Single-Click zum Aktivieren" und "beim Hovern automatisch auswählen" an
dieselbe Property; `false` = Doppelklick-Modus, kein Hover-Select –
entspricht dem macOS-Finder-Verhalten. Der Rest der Datei ist Fenster-
größe/letzte Ansicht/Sortierung (Session-Zustand, unkritisch) sowie zwei
weitere bewusste Settings (`misc-recursive-permissions`,
`misc-show-delete-action`), die deshalb bewusst mitversioniert sind statt
weggelassen.

### xfce4-terminal: Drop-down-Fensterränder

`dot_config/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml`
versioniert ebenfalls die komplette Live-Datei (Font, Farbpalette,
Transparenz, ... – hier wäre ein Minimal-Auszug im Gegensatz zu
`thunar.xml` tatsächlich riskant gewesen, siehe Hinweis oben). Die
eigentlich gewollte Änderung ist `dropdown-show-borders` auf `true`. Das
Drop-down-Fenster (auf MX per F4-Shortcut: `xfce4-terminal --drop-down`,
Shortcut selbst noch nicht per chezmoi versioniert) öffnet standardmäßig
**ohne** Fensterdekoration – das ist bei xfce4-terminal fest verdrahtet
und wird von `--show-borders` sowie der allgemeinen Property
`misc-borders-default` (für normale Fenster) ignoriert. Es gibt aber eine
eigene, dropdown-spezifische Property dafür (`dropdown-show-borders`, im
Preferences-Dialog unter dem Reiter "Drop-down" als Checkbox
"Fensterränder anzeigen"), die genau das manuelle Antoggeln nach jedem
Neustart ersetzt.

### Termius/iPhone: tmux-Statuszeile

Termius (iPhone) sendet beim Connecten die Env-Var `IPHONE_CLIENT=true`
(Termius' "Environment Variables"-Feature). tmux übernimmt sie beim
Client-Attach in die Session-Umgebung und schaltet darüber automatisch
auf eine zweizeilige, für den schmalen Touch-Screen optimierte
Statuszeile mit antippbaren Bereichen um (`status-position top`, weil
Termius' eigene UI sonst die unterste Zeile verdeckt). Drei Teile:

- `dot_config/tmux/tmux.conf.tmpl` – `update-environment`, die beiden
  `client-attached`/`client-session-changed`-Hooks sowie die Klick-Bindings
  (`MouseDown1StatusLeft`/`-Right`).
- `dot_config/tmux/executable_iphone-mode.sh.tmpl` – baut bei jedem
  Hook-Aufruf die komplette iPhone-Statuszeile neu zusammen (oder die
  normale, falls `IPHONE_CLIENT` nicht gesetzt ist).
- `dot_bashrc.tmpl`, Abschnitt `TERMIUS-ENV-FIX` – Termius hängt beim
  Senden Leerzeichen an Name/Wert an (`IPHONE_CLIENT   =true `), daher
  hier vor einem etwaigen `tmux attach` trimmen und sauber re-exportieren.
- `.chezmoiscripts/run_once_after_42-configure-sshd-iphone-acceptenv.sh.tmpl`
  – ergänzt serverseitig `AcceptEnv IPHONE_CLIENT*` in `/etc/ssh/sshd_config`
  (Wildcard wegen des Leerzeichen-Paddings; `sshd` lehnt den exakten Namen
  sonst mit `disallowed name` ab) und lädt `sshd` neu.

Details zu Fehlersuche und tmux-Format-Sprache (Padding-Richtung,
Truncation-Marker, warum Breiten-Argumente literale Zahlen sein müssen,
`client-attached` vs. `client-session-changed`, ...) stehen in den
SECOND_BRAIN-Berichten `termius-iphone-tmux-env-var-krimi/` und
`tmux-termius-statuszeile-customizing/`, nicht hier im Repo.

## Ulauncher (Launcher + Patches)

`dot_config/ulauncher/{settings.json,extensions.json,shortcuts.json}`
versioniert die Ulauncher-Einstellungen (Theme, Hotkey, Shortcuts,
Extensions-Liste). Paket und Patches (Punkt 1) laufen automatisch bei
`chezmoi apply`; nur die Extensions (Punkt 2) sind manuell.

**1. Ulauncher-Paket + Patches: automatisch.** Siehe unten
„Automatische Installation und Patches". Kurz: Kein apt/nala-Repo führt
`ulauncher` auf Debian/MX, darum installiert ein Skript ein gepinntes `.deb`
und patcht es.

**2. Extensions.** `extensions.json` beschreibt nur, welche Extensions
gewünscht sind (Commit-Pins) – die eigentlichen Git-Checkouts unter
`~/.local/share/ulauncher/extensions/<id>/` werden von Ulauncher **nicht**
automatisch aus `extensions.json` nachgeladen, wenn der Ordner fehlt (nicht
verifiziert, dass das je automatisch passiert – bislang immer manuell
geklont). Nach einer Neuinstallation daher manuell:

```bash
cd ~/.local/share/ulauncher/extensions
git clone https://github.com/sander76/ulauncher-keepassxc com.github.sander76.ulauncher-keepassxc
git clone https://github.com/ubuntupunk/ulauncher-vim com.github.ubuntupunk.ulauncher-vim
git clone https://github.com/no-faff/ulauncher-calculate-anything com.github.no-faff.ulauncher-calculate-anything
```

(Ordnername muss exakt der jeweiligen `id` aus `extensions.json`
entsprechen.)

### Automatische Installation und Patches

`ulauncher-calc-patch/` im Repo-Root (per `.chezmoiignore` von der
Anwendung nach `$HOME` ausgenommen, wie `README.md` selbst) enthält die
gepatchten `CalcMode.py`/`CalcHistory.py`/`CalcResultItem.py` plus
`install.sh`. Das Skript patcht Dateien unter
`/usr/lib/python3/dist-packages/ulauncher/` – ein System-Paketpfad, den
chezmoi grundsätzlich nicht verwaltet. Deshalb steuert es
`.chezmoiscripts/run_after_53-apply-ulauncher-patch.sh.tmpl`:

- Läuft bei **jedem** `chezmoi apply` (bewusst `run_after_`, nicht
  `run_onchange_`: ein `apt upgrade ulauncher` überschreibt die Patches, ohne
  dass sich das Skript ändert).
- Ruft `install.sh --no-restart` nur auf, wenn Ulauncher fehlt oder ein Patch
  fehlt/abweicht. Sonst kein Output, kein `sudo`.
- `--no-restart`, weil `chezmoi apply` oft ohne `$DISPLAY` läuft; Ulauncher
  dann einmal von Hand neu starten. `install.sh` lässt sich auch direkt
  aufrufen (ohne Flag startet es Ulauncher neu):

```bash
~/.local/share/chezmoi/ulauncher-calc-patch/install.sh
```

Braucht `sudo`.

`install.sh` macht der Reihe nach:

1. **Ulauncher installieren, falls fehlend:** gepinntes `.deb`, aktuell
   **5.15.15** (`PIN_VERSION`/`PIN_SHA256` in `install.sh`). Quellen in dieser
   Reihenfolge, jeweils SHA256-geprüft: GitHub-Release (ohne VPN erreichbar)
   → Forgejo Generic Package
   `forgejo.tipi.lan:8195/api/packages/harry/generic/ulauncher/5.15.15/`
   (nur per VPN, ohne Login lesbar). Installiert per `nala`, sonst
   `apt-get`. Bereits installierte Versionen (z. B. 5.15.7 auf dem x230)
   werden nicht angefasst.
2. **Calc-Patch** (erweiterter Taschenrechner: Funktionen, Konstanten,
   Rechen-History): nur bei **5.15.x**. Ab 5.16 hat Upstream einen eigenen,
   umgebauten Rechner (`CalcCompletionResultItem.py`, Funktionen/Konstanten/
   `%`); unsere `CalcMode.py` würde ihn kaputtmachen, das Skript
   überspringt sie dort.
3. **Ctrl+A / Ctrl+E** (emacs-style Zeilenanfang/-ende, in allen
   Suchmodi): sechs Zeilen werden per Einfügen hinter den `Ctrl+,`-Zweig in
   die installierte `UlauncherWindow.py` geschrieben, keine Vollkopie.
   Idempotent (Marker `emacs-style line navigation`), bricht bei fehlendem
   Anker ohne Änderung ab; getestet auf 5.15.15 und 5.16.2. Nebeneffekt:
   `Ctrl+A` markiert nicht mehr alles.
4. Setzt `clear-previous-query: false` („Eingabe beim Schließen behalten“).

**Neue Version pinnen:** `PIN_VERSION` und `PIN_SHA256` in `install.sh`
ändern und das neue `.deb` in die Forgejo-Registry legen
(`curl -H "Authorization: token …" --upload-file … <URL>`). Der Token
braucht den Scope `package` (Lesen+Schreiben) mit Repository-Zugriff „Alle“;
ein auf einzelne Repos beschränkter Token darf `package` nicht. Nach dem
Upload löschen.

## Neovim (LazyVim)

`dot_config/nvim/` versioniert die [LazyVim](https://www.lazyvim.org/)-Config
direkt im Hauptrepo (kein separates Git-Repo für nvim, dafür ist die
eigene Anpassungstiefe zu gering). Mitversioniert sind u.a.:

- `lazyvim.json` – die aktivierten LazyVim-Extras (`:LazyExtras`); das ist
  aktuell die einzige nennenswerte eigene Anpassung
- `lazy-lock.json` – Plugin-Versions-Pins. Bewusst mitversioniert (nicht
  `.gitignore`t), damit alle Maschinen dieselben Plugin-Commits
  installieren und ein kaputtes Update sich per `git checkout
  lazy-lock.json` + `:Lazy restore` zurückrollen lässt
- `lua/config/*.lua`, `stylua.toml`, `.neoconf.json`

Nicht mitversioniert sind `README.md`, `LICENSE` und `.gitignore` aus
`~/.config/nvim` – das sind Reste des LazyVim-Starter-Templates selbst
(beschreiben das Template, nicht die eigene Config) und bleiben lokal
unmanaged liegen. Neue eigene Plugin-Specs kommen als einzelne Dateien
unter `lua/plugins/*.lua` (das Starter-Beispiel `example.lua` wurde
gelöscht, da es nur totes Beispiel war).

`nvim cd` (Funktion in `dot_bash_aliases`) springt direkt ins
Config-Verzeichnis, Pfad dynamisch von nvim selbst erfragt statt
hartkodiert.

## User-Scripte: welcher Mechanismus?

Für Kommandozeilen-Tools unter `~/.local/bin` bzw. Shell-Funktionen gibt es
vier Ablageorte im Repo, je nach Anwendungsfall:

| Mechanismus | Ablageort | Wann |
|---|---|---|
| **Repo-Script** | `dot_local/bin/executable_<name>` | Eigenständiges Tool, überall identisch, nichts Geheimes/Host-Privates |
| **+ Copy nach `/usr/local/bin`** | zusätzlich `run_onchange_after_*` mit `install -m 755` | Wie oben, aber Skript muss auch per `sudo <name>` direkt aufrufbar sein |
| **Shell-Funktion** | `dot_bash_aliases` (oder `dot_bashrc.tmpl`) | Muss die aktuelle Shell verändern (`cd`, `export`, History lesen) oder ein bestehendes Kommando wrappen |
| **Vault-Symlink** | `~/Sync/vault/script/<hostname\|common>/`, verlinkt von `run_after_50-symlink-vault-scripts.sh.tmpl` | Host-spezifisch/privat, soll nicht ins (ggf. später öffentliche) Repo |
| **+ sysvinit-Autostart** | zusätzlich `run_onchange_after_*` installiert ein LSB-Init-Skript nach `/etc/init.d` + `update-rc.d` | Wie Vault-Symlink, aber muss zusätzlich beim Boot als root laufen (Host mit `machines.<host>.sysvinit: true`) |

**Warum ein Copy statt Symlink nach `/usr/local/bin`?** `sudo` nutzt einen
gehärteten `secure_path` ohne `~/.local/bin` (siehe `/etc/sudoers`) –
`sudo <name>` würde sonst trotz PATH-Eintrag mit "command not found"
scheitern. Ein Symlink nach `/usr/local/bin` würde root stattdessen eine
Datei aus einem user-schreibbaren Verzeichnis ausführen lassen; eine
root:root-Kopie ist sauberer. `run_onchange` (statt `run_once` oder einem
plain `run_after`) triggert nur neu, wenn sich der Skriptinhalt tatsächlich
ändert (Hash-Kommentar im Script, siehe
`run_onchange_after_46-install-atql-system.sh.tmpl`, analog zu
`run_onchange_after_40-refresh-font-cache.sh.tmpl`). Einziger Nutzer für
`/usr/local/bin`: `atql` (`dot_local/bin/executable_atql`) – `forensic-mode`
braucht das nicht, da es nie selbst mit vorangestelltem `sudo` aufgerufen
wird, sondern intern gezielt `sudo usermod`/`gpasswd` nutzt (liegen schon in
`secure_path`).

Der sysvinit-Autostart (`run_onchange_after_51-install-wlan-monitor-init.sh.tmpl`)
nutzt denselben `run_onchange`-Mechanismus für ein anderes Ziel: das
komplette LSB-Init-Skript steckt hier direkt im Template (statt in einer
separaten Datei + Hash-Kommentar wie bei atql), chezmoi erkennt Änderungen
also automatisch am gerenderten Skriptinhalt. Läuft nur auf Maschinen mit
`machines.<host>.sysvinit: true` in `.chezmoidata.yaml` (aktuell x220) und
erst NACH `run_after_50-symlink-vault-scripts.sh.tmpl` (Nummerierung 51),
weil `DAEMON`/`WORKDIR` auf den dortigen Vault-Symlink
(`~/.local/bin/check_connection.sh`) zeigen. Log/State schreibt
`check_connection.sh` bewusst nach `~/.cache/wlan-monitor/` und nicht
skriptpfad-relativ – sonst würde durch den Vault-Symlink ein `log/`-Ordner
zwischen die Binaries in `~/.local/bin` rutschen.

Beispiele aus dem Repo: `atql`/`forensic-mode`/`tmux-save-buffer`
(Repo-Script), die `cd`-Wrapper `chezmoi`/`tealdeer`/`nvim` sowie
`findgrep` und `_track_sudo_use` (Shell-Funktion, alle in
`dot_bash_aliases`), `check_connection.sh` (Vault-Symlink, x230, siehe
nächster Abschnitt; x220 zusätzlich mit sysvinit-Autostart).

## Vault-Scripts, SSH & Custom Pages (Syncthing)

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
versioniert sein, ist der vault-Mechanismus der falsche Ort – siehe
[User-Scripte: welcher Mechanismus?](#user-scripte-welcher-mechanismus)
oben. Für eine feste Teilmenge von Maschinen: ebenso eine normale
Repo-Datei, aber per `.chezmoiignore`-Template auf den nicht gewünschten
Hostnamen ausschließen.

**SSH** (`~/Sync/vault/ssh/<hostname>/`, z.B. `ssh/x220/`): private Keys,
`authorized_keys`, `config` und `known_hosts` gehören nicht ins Git-Repo –
auch nicht age-verschlüsselt, wegen des geplanten öffentlichen Mirrors.
`run_after_45-symlink-vault-ssh.sh.tmpl` verlinkt bei jedem `chezmoi apply`
automatisch alle Dateien aus `ssh/<hostname>/` nach `~/.ssh/` (Modus `700`)
und räumt verwaiste Symlinks auf. Bewusst **kein** `ssh/common/` wie bei den
Vault-Scripten: die Keys sind schon jetzt pro Maschine benannt (z.B.
`x220.forgejo.key`), ein gemeinsamer Ordner würde sie per Syncthing auf
jede andere Maschine replizieren und den Blast Radius bei Kompromittierung
einer einzelnen Maschine unnötig vergrößern. Soll eine `config`-Zeile
(z.B. ein Host-Alias) auf mehreren Maschinen identisch sein, muss sie
aktuell auf jeder Maschine einzeln im jeweiligen `ssh/<hostname>/config`
gepflegt werden.

**gh (GitHub CLI)** (`~/Sync/vault/gh/`): `hosts.yml` enthält den OAuth-Token
im Klartext und gehört deshalb nicht ins Git-Repo, auch nicht
age-verschlüsselt, wegen des öffentlichen Mirrors. `run_after_47-symlink-vault-gh.sh.tmpl`
verlinkt bei jedem `chezmoi apply` automatisch alle Dateien aus
`gh/` nach `~/.config/gh/` und räumt verwaiste Symlinks auf. Anders als bei
SSH bewusst **ein gemeinsamer** Ordner ohne Hostname-Aufteilung: der
gh-Login (`docfriendly`) ist auf allen Maschinen identisch, kein Bedarf für
getrennte Tokens pro Maschine.

**Custom tealdeer-Pages** (`~/Sync/vault/SECOND_BRAIN/CLI-KONSOLENKOMMANDOS-NACHSCHLAGEWERK/tldr/`):
wird per nativem chezmoi-`symlink_`-Eintrag (`dot_local/share/tealdeer/symlink_pages.tmpl`)
nach `~/.local/share/tealdeer/pages` verlinkt. Auch hier kein
Reihenfolge-Problem mit Syncthing: Der Symlink kann angelegt werden, bevor
der Ordner durch Syncthing befüllt ist – er zeigt dann kurz ins Leere und
heilt sich von selbst, sobald die Dateien ankommen.

**Claude-Code-Instruktionen** (`~/Sync/vault/claude/CLAUDE.md`): enthält
persönliche/private Verhaltensregeln für Claude Code, die auch nach dem
öffentlichen Mirror nicht ins Repo sollen. Wird genau wie die
tealdeer-Pages per nativem chezmoi-`symlink_`-Eintrag
(`dot_claude/symlink_CLAUDE.md.tmpl`) nach `~/.claude/CLAUDE.md` verlinkt –
identisch (maschinenunabhängig), kein `<hostname>`-Unterordner nötig.

Alle vier Mechanismen hängen am Hostnamen und nutzen denselben Guard wie
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
`run_once_after_74-install-tmux-plugins.sh.tmpl` zum ersten Mal ausgeführt
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

**Ein Skript bricht ab und der Rest läuft nicht** (chezmoi stoppt beim ersten
Fehler)

Deshalb die Reihenfolge: kurze, fehleranfällige Skripte (Downloads, apt,
`sudo`) zuerst, lange Kompilierung zuletzt (70–75, siehe Bootstrap-Kette).
Ein fehlgeschlagenes `run_once_` gilt nicht als erledigt, läuft beim
nächsten `chezmoi apply` erneut – nach dem Fix reicht
`chezmoi update --apply`. Gelernt beim ihht-Bootstrap (09.10.2026):

- **Gepinnter Download liefert HTML statt Paket**: NoMachines alter Link
  antwortete mit 302 auf die Startseite, `curl -f` merkte nichts, apt:
  „Ungültige Archiv-Signatur“. Der Preflight (`run_once_before_02`)
  prüft deshalb jeden Eintrag unter `downloads:` in `.chezmoidata.yaml`
  (derzeit leer). Neue gepinnte Downloads dort eintragen.
- **NoMachine 10 verlangt Lizenz** („Personal Edition Evaluation“): die
  kostenlose Server-Edition gab es nur bis 9.x. Skript 35 installiert
  deshalb ein 9.x-`.deb` aus dem Vault, nicht mehr aus dem Netz.
- **Template `map has no entry for key`**: `$machine.<schluessel>` bricht auf
  Hosts ab, die den Schlüssel nicht haben. Optionale Schlüssel immer mit
  `index $machine "schluessel"` abfragen (fehlend = false), z.B.
  `sysvinit` (nur x220) in Skript 51.
- **`find`/`grep` unter `pipefail`**: ein fehlendes Verzeichnis ergibt
  Exit 1 und bricht das Skript ab, obwohl nichts zu tun ist (Skript 55 auf
  Hosts ohne `~/.claude/projects`). Vorher mit `[ -d … ] || exit 0` prüfen.
- **`python3 -m py_compile` im Paketpfad**: `__pycache__` unter
  `/usr/lib/python3/dist-packages` gehört root, als User `Errno 13`
  (ulauncher-Patch, Skript 53). Mit `sudo` aufrufen.
- **`lazy-lock.json` lokal geändert**: nvim aktualisiert das Lockfile beim
  Start. `chezmoi apply` fragt dann (`diff/overwrite/…`). `overwrite` nimmt
  die Repo-Version, danach in nvim `:Lazy restore`.
- **Mason bricht beim headless-Install ab** (`erb-lint`, `markdown-toc`,
  `markdownlint-cli2`): nvim beendet sich, bevor Mason fertig ist. Beim
  ersten interaktiven `nvim`-Start installiert Mason nach.

## WireGuard auf den Hosts

`wg-quick` und `wireguard-tools` kommen auf jedem Host aus dem Brewfile
(Linuxbrew), nicht aus apt. Die Peer-Datei `/etc/wireguard/<host>-praxmon.conf`
enthält den Private Key und liegt **nicht** im Repo (öffentlicher Mirror). Sie
kann auch nicht aus dem Syncthing-Vault kommen, weil der Vault den Tunnel
braucht – der erste Peer-Eintrag je Host ist deshalb Handarbeit:

```bash
scp <host>-praxmon.conf <user>@<host>:~/           # /etc/wireguard gehört root
sudo install -m 600 -o root -g root ~/<host>-praxmon.conf /etc/wireguard/
shred -u ~/<host>-praxmon.conf
chezmoi apply                                       # run_after_47 importiert die Datei als NM-Profil
sudo nmcli connection up <host>-praxmon             # einmal aktivieren, danach startet NM sie beim Boot
```

- **Autostart über ein NetworkManager-Profil** (Entscheidung 16.10.2026,
  `run_after_47-configure-wireguard-nm-profile`, nur Hosts mit
  `machines.<host>.wireguard: true`): importiert die Peer-Datei per
  `nmcli connection import type wireguard`, setzt `autoconnect yes` und
  `autoconnect-retries 0` (NM löst den Endpoint nur beim Aktivieren auf;
  ohne WLAN/DNS scheitert der erste Versuch). init-unabhängig (ihht: systemd,
  x220/x230: sysvinit), kein Login nötig. Das Skript aktiviert nicht selbst
  (kollidiert mit laufendem `wg-quick`, kann die SSH-Sitzung abschneiden).
  Per SSH braucht auch `nmcli connection up` `sudo` (`Not authorized to
  control networking`).
- **Entscheidung und Rollback:** siehe Abschnitt „Entscheidung 16.10.2026"
  unten.
- **`AllowedIPs`**: wg-easy liefert `0.0.0.0/0, ::/0` (Vollverkehr). Für
  Hosts, die nur das VPN-Subnetz brauchen (Kiosk), auf dieses Subnetz
  einschränken, sonst läuft der gesamte Verkehr durch den Tunnel.
- **Dateirechte** `600 root:root`; `wg-quick` warnt bei world-readable.
- **`DNS =` in der Peer-Datei**: Mit dem NM-Profil übernimmt NetworkManager
  die Server selbst, `resolvconf` ist nicht nötig. Nur beim Start per
  `wg-quick` von Hand braucht `DNS =` `resolvconf` (und damit unter
  NetworkManager `rc-manager=resolvconf`, sonst bleibt `/etc/resolv.conf` leer
  und es gibt keine Namensauflösung). Ein Host ohne `resolvconf`, bei dem es
  versehentlich installiert wurde: `sudo apt purge resolvconf && sudo nmcli
  general reload`.
- **`nmcli general reload` nimmt nur ein Flag oder keines**: `reload conf
  dns-rc` bricht mit `extra argument 'dns-rc'` ab (nmcli 1.52, ihht
  16.10.2026), und `reload dns-rc` allein reichte nicht. Sofortfix bei
  leerer `/etc/resolv.conf` (z. B. `chezmoi update` findet GitHub nicht):
  `sudo nmcli general reload` ohne Argument.

### Entscheidung 16.10.2026: NM-Profil statt `resolvconf`-Skript

**Vorher** (Commits `5ec6dd5`, `2b3559a`): `run_once_after_48-configure-wireguard-dns`
installierte `resolvconf` und setzte `rc-manager=resolvconf`, der Tunnel lief
per `wg-quick` von Hand. Das Skript hat auf ihht den Apply abgebrochen und DNS
lahmgelegt (siehe oben).

**Jetzt:** Skript 48 ist entfernt, Skript 47 importiert ein NM-Profil mit
`autoconnect`. Gründe: init-unabhängig (kein systemd nötig), startet beim Boot
ohne Login, kein `resolvconf`-Eingriff in `/etc/resolv.conf`, weniger
bewegliche Teile. Getestet auf ihht: Profil aktiv, `github.com` löst auf, x220
antwortet. **Noch nicht getestet:** Reboot ohne manuellen Eingriff.

**Risiken:** NM löst den Endpoint nur beim Aktivieren auf (Wiederholungen über
`autoconnect-retries 0`); das WLAN-Profil des Hosts muss vor dem Login
verbinden (systemweit gespeicherter Schlüssel); `DNS =` aus der Peer-Datei
steht jetzt im NM-Profil, spätere Änderungen daran erfordern erneuten Import
(`sudo nmcli connection delete <host>-praxmon`, Apply).

**Rollback:** Skript 48 wiederherstellen (`git revert` des Entfernen-Commits
oder `git checkout 2b3559a -- .chezmoiscripts/run_once_after_48-configure-wireguard-dns.sh.tmpl`),
Skript 47 löschen; auf dem Host `sudo nmcli connection delete <host>-praxmon`
und den Tunnel wieder von Hand starten (`sudo
/home/linuxbrew/.linuxbrew/bin/wg-quick up <host>-praxmon`). Auf ihht stehen
`resolvconf` und `/etc/NetworkManager/conf.d/rc-manager.conf` noch aus dem
alten Weg; für den Rollback passen sie, für den neuen Weg sind sie überflüssig
(entfernen: `sudo apt purge resolvconf && sudo rm
/etc/NetworkManager/conf.d/rc-manager.conf && sudo nmcli general reload`).

## Syncthing: Autostart und Verbindung über WireGuard

`run_onchange_after_76-install-syncthing-autostart` trägt auf Hosts mit
`machines.<host>.syncthing.autostart: true` eine `@reboot`-Zeile (Markierung `#
syncthing-managed`) in die User-Crontab ein: `syncthing serve --no-browser`
mit Logdatei unter `~/.local/state/syncthing/`. Cron, weil die Hosts
unterschiedliche Init-Systeme haben (x220/x230/t410s sysvinit, ihht systemd)
und der Kiosk als anderer User läuft (XDG-Autostart startete erst beim Login
von `harry`). Ohne `--no-restart`, damit `syncthing cli operations restart`
nicht nur beendet. `"syncthing --no-browser"` gehört deshalb **nicht** mehr
in `resurrectProcesses` (tmux-resurrect würde eine zweite Instanz starten,
die an der Datenbank-Sperre scheitert). Sofortstart ohne Reboot:
`tmux new-session -d -s syncthing 'syncthing serve --no-browser'`.

Verbindung nur über den Tunnel (nicht im Repo, Handarbeit je Host):
- `ufw`: Port 22000/tcp nur auf dem Tunnel-Interface und nur für die Gegenstelle,
  z. B. `sudo ufw allow in on <host>-praxmon from <WG-IP-der-Gegenstelle> to any
  port 22000 proto tcp`.
- Gerät der Gegenstelle mit fester Adresse `tcp://<WG-IP>:22000` eintragen
  (REST `PATCH /rest/config/devices/<id>` oder GUI). Eine veraltete LAN-IP in
  der Adressliste (ihht 17.10.2026) fiel erst beim Test auf.
- Prüfen: `GET /rest/system/connections` zeigt `tcp-server`/`tcp-client` mit
  der `10.8.0.x`-Adresse, nicht `relay`.
- Beweis 17.10.2026: ihht↔x220 ohne `scp`, 100 % Abgleich, Datei kam an.

### Discovery, Relays und feste Adressen (`run_after_56-configure-syncthing`)

Die Schalter stehen pro Host unter `machines.<host>.syncthing`
(`localDiscovery`, `globalDiscovery`, `relays`, `nat`, jeweils true/false).
Das Skript liest sie und setzt sie **per REST** (`PATCH /rest/config/options`),
nur wenn der Ist-Wert abweicht; läuft der Daemon nicht, wartet es auf den
nächsten Apply. `config.xml` wird bewusst nicht versioniert (Geräte, Ordner,
API-Key, GUI-Hash; Syncthing überschreibt sie laufend). Die `syncthing cli`
kennt `nat-enabled` nicht, deshalb REST.

Feste Gegenstellen-Adressen (WireGuard-IPs, **nicht** im öffentlichen Repo)
stehen in `~/Sync/vault/syncthing/<host>/peers`, eine Zeile pro Gerät:
`<Geräte-ID> <Adresse> [<Adresse> …]`, `dynamic` lässt Discovery für dieses
Gerät zu. Unbekannte (noch nicht gekoppelte) Geräte werden übersprungen.
Stand 17.10.2026: ihht = alles aus (nur WireGuard); x220/x230/t410s =
Local Discovery an, Global Discovery/Relays/NAT aus (das Handy erreicht den x220
über seine WG-Adresse mit fester Adresse im Handy-Syncthing und `ufw`-Regel
auf dem Tunnel). Nicht in chezmoi: Kartoffelcomputer (Handarbeit),
Handy-Syncthing.

**Verbindungsrichtung und Tunnel-Adressen (Stand 17.10.2026, verifiziert
über `GET /rest/system/connections`):**
- `type: tcp-server` bei einem Gerät heißt: **das Gerät hat uns angerufen**
  (eingehend), `tcp-client`: wir haben es angewählt. ihht, Handy: `tcp-server`
  auf dem x220. Bei Verbindungen über Relay steht `relay-*`, dann ist etwas
  nicht wie gewollt.
- Jede Seite, die angewählt werden soll, braucht die `ufw`-Regel auf ihrem
  Tunnel-Interface; wer nur ausgehend anruft (Handy), braucht auf seiner Seite
  nichts. Auf dem x220 gibt es je eine Regel pro Peer-WG-Adresse (ihht
  und so weiter; die Adressen stehen im Vault, nicht hier).
- Mit `globalDiscovery`/`relays` aus kennt ein Gerät den anderen nur noch über
  die feste Adresse (Gerät → Adressen) oder Local Discovery. Wer das vergisst,
  sieht „nicht verbunden" ohne Fehlermeldung.

**iOS (Synctrain), Einstellungen für „nur über WireGuard":**
- Das Handy braucht einen aktiven WG-Tunnel (`AllowedIPs` mit dem WG-Netz).
- Beim **Gerät** des x220 (Geräte → x220 → Adressen) die Adresse
  `tcp://<x220-WG-IP>:22000` eintragen. Das war der entscheidende Schritt.
- Einstellungen → Erweitert → Konnektivität → **Adressen** sind die *eigenen
  Höradressen des Handys* (an denen Synctrain eingehende Verbindungen annimmt),
  **nicht** die Adressen der Gegenstellen. Man verwechselt sie leicht.
- „Standard-Höradressen verwenden", „Standard-Relays verwenden" und „Auf
  eingehende Verbindungen hören" aus. iOS läuft im Hintergrund nur kurz, ein
  lauschender Port erreicht ohnehin niemand; die Verbindung geht immer vom
  Handy aus. Folge: In `~/Sync/vault/syncthing/x220/peers` steht das Handy nur
  mit `dynamic`, nicht mit einer festen Adresse.
- Optional: „Globale Suche"/NAT im Handy aus, sonst meldet es sich weiter bei
  den öffentlichen Discovery-Servern.

**Checkliste neuer Syncthing-Peer über WireGuard:** (1) `ufw`-Regel auf dem
Gegenüber, (2) feste Adresse beim Gerät, (3) Eintrag in `peers`, (4) nach dem
nächsten Apply `GET /rest/system/connections` prüfen (`tcp-*`, `10.8.0.x`).

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
