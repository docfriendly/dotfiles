#!/bin/bash
# Minuetlicher Heartbeat fuer Absturz-Forensik (x220-forensics-unplanned-restart).
# Schreibt Zeitstempel + AC/Akku/Temperatur/Luefter/Last, damit der letzte Eintrag
# vor einem unsauberen Neustart Zeitpunkt UND thermischen Zustand direkt zeigt.
#
# Einzeiler-Format. Die fuehrenden Felder (AC= / BAT= / TEMP=) sind unveraendert,
# damit die bestehende BERICHT-Auswertung weiter passt; die Thermik-Felder
# (PKG/CORE/FAN/LOAD/TOP) haengen hinten dran.
#
# Hintergrund: Vorfall am 2026-09-03 ~14:15 war ein stiller thermischer Hard-Lock
# beim Bauen eines podman-Images (THM0 94 C beim Notreboot). Seitdem loggen wir
# auch Package-Temp und Luefterdrehzahl mit. Feinkoerniges 5s-Log waehrend Builds
# macht der Wrapper ~/.local/bin/pbuild.
#
# Generisch (auch x230 u. a.): Netzteil/Akku werden ueber /sys/class/power_supply/*/type
# gefunden (Mains/Battery), nicht ueber feste Namen. Log je Rechner getrennt, Hostname
# steht zusaetzlich als HOST= am Zeilenende. Auf dem x220 setzt der Cron-Eintrag
# LOG=<Vault>/x220_heartbeat.log, damit das bestehende Log fortgefuehrt wird.
HOST=$(hostname)
LOG=${LOG:-$HOME/.local/state/heartbeat-$HOST.log}
mkdir -p "$(dirname "$LOG")" 2>/dev/null

r()  { cat "$1" 2>/dev/null; }                       # roher sysfs-Read, leer bei Fehler
mc() { local v; v=$(r "$1"); if [ -n "$v" ]; then echo $(( v / 1000 )); else echo '?'; fi; }

# hwmon-Nummern sind ueber Reboots nicht stabil -> ueber name-Datei aufloesen.
hwmon_by_name() {
  local d
  for d in /sys/class/hwmon/hwmon*; do
    [ "$(r "$d/name")" = "$1" ] && { echo "$d"; return 0; }
  done
  return 1
}
# thermal_zone ueber type aufloesen (Fallback: zone0).
zone_by_type() {
  local z
  for z in /sys/class/thermal/thermal_zone*; do
    [ "$(r "$z/type")" = "$1" ] && { echo "$z"; return 0; }
  done
  echo /sys/class/thermal/thermal_zone0
}
# coretemp-Sensor per Label finden (Package id 0 / Core 0 / Core 1).
ct_input() {  # $1 = Label-Teilstring
  local ct f
  ct=$(hwmon_by_name coretemp) || return 1
  for f in "$ct"/temp*_label; do
    [ -e "$f" ] || continue
    case "$(r "$f")" in
      *"$1"*) echo "${f%_label}_input"; return 0 ;;
    esac
  done
  return 1
}

# Erstes power_supply-Geraet eines Typs (Mains/Battery) -> Pfad, sonst leer.
ps_by_type() {
  local d
  for d in /sys/class/power_supply/*; do
    [ "$(r "$d/type")" = "$1" ] && { echo "$d"; return 0; }
  done
  return 1
}
# Luefter: thinkpad-hwmon, sonst erster hwmon mit fan1_input.
fan_input() {
  local d f
  d=$(hwmon_by_name thinkpad) && { echo "$d/fan1_input"; return 0; }
  for f in /sys/class/hwmon/hwmon*/fan1_input; do
    [ -e "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

ZONE0=$(zone_by_type acpitz)

MAINS=$(ps_by_type Mains); BATDEV=$(ps_by_type Battery)
AC=$(r "${MAINS:+$MAINS/online}");       AC=${AC:-?}
BAT=$(r "${BATDEV:+$BATDEV/capacity}");  BAT=${BAT:-?}

TEMP=$(mc "$ZONE0/temp")                                  # == altes thermal_zone0 (Rueckwaertskompat)
PKG=$(mc "$(ct_input 'Package id 0')")                    # Package-Temp = fuehrt beim Freeze
C0=$(mc "$(ct_input 'Core 0')")
C1=$(mc "$(ct_input 'Core 1')")
FAN=$(r "$(fan_input)");                          FAN=${FAN:-?}
LOAD=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null); LOAD=${LOAD:-?}
TOP=$(ps -eo pcpu=,comm= --sort=-pcpu 2>/dev/null | awk 'NR==1 && $1+0 > 0 {printf "%s:%.0f%%", $2, $1}')
TOP=${TOP:-idle}

echo "$(date '+%Y-%m-%dT%H:%M:%S%z') AC=${AC} BAT=${BAT}% TEMP=${TEMP}C PKG=${PKG}C CORE=${C0}/${C1}C FAN=${FAN}RPM LOAD=${LOAD} TOP=${TOP} HOST=${HOST}" >> "$LOG"

# --- Akku-Alarm per ntfy (Stufe 1 <= 25 %, Stufe 2 <= 10 %, nur ohne Netzteil) ---
# Meldet je Stufe genau einmal; das Statusfile merkt die zuletzt gemeldete Stufe und
# wird zurueckgesetzt, sobald das Netzteil wieder dran ist / der Akku ueber der
# Schwelle liegt. Schlaegt curl fehl (WLAN weg), bleibt der Stand unveraendert und
# die naechste Minute versucht es erneut. TEST_AC/TEST_BAT/WARN*/NTFY_URL/STATE
# sind nur fuer Tests ueberschreibbar.
NTFY_URL=${NTFY_URL:-https://ntfy.sh/harrys_test_channel}
WARN1=${WARN1:-25}; WARN2=${WARN2:-10}
STATE=${STATE:-$HOME/.cache/x220-akku-alarm.state}
A_AC=${TEST_AC:-$AC}; A_BAT=${TEST_BAT:-$BAT}

LEVEL=0
if [ "$A_AC" = 0 ] && [[ "$A_BAT" =~ ^[0-9]+$ ]]; then
  if   [ "$A_BAT" -le "$WARN2" ]; then LEVEL=2
  elif [ "$A_BAT" -le "$WARN1" ]; then LEVEL=1
  fi
fi
PREV=$(r "$STATE"); PREV=${PREV:-0}
if [ "$LEVEL" -gt "$PREV" ]; then
  if [ "$LEVEL" = 2 ]; then PRIO=urgent; TAGS=skull; else PRIO=high; TAGS=battery; fi
  if curl -fsS -m 10 --connect-timeout 5 -H "Title: $HOST Akku ${A_BAT}%" \
       -H "Priority: $PRIO" -H "Tags: $TAGS" \
       -d "Akku ${A_BAT}%, Netzteil nicht angesteckt (Stufe ${LEVEL})" "$NTFY_URL" >/dev/null 2>&1
  then mkdir -p "$(dirname "$STATE")"; echo "$LEVEL" > "$STATE"; fi
elif [ "$LEVEL" -lt "$PREV" ]; then
  mkdir -p "$(dirname "$STATE")"; echo "$LEVEL" > "$STATE"
fi

# --- Stufe 0: Netzteil seit >= AC_LOST_MIN Minuten ab (unabhaengig vom Ladestand) ---
# Meldet einmal pro Netzteil-Ausfall, damit man noch vor Ort umstecken kann. Kurzes
# Umstecken (< AC_LOST_MIN) loest nichts aus. Zusaetzlich einmalige Nachmeldung
# "Immer noch abgesteckt" nach AC_STILL_MIN Minuten. TEST_NOW nur fuer Tests.
AC_LOST_MIN=${AC_LOST_MIN:-3}
AC_STILL_MIN=${AC_STILL_MIN:-30}
LOST_FILE=${LOST_FILE:-$HOME/.cache/x220-ac-lost.since}      # Epoch des Ausfallbeginns
LOST_SENT=${LOST_SENT:-$HOME/.cache/x220-ac-lost.notified}   # Marker: schon gemeldet
LOST_SENT2=${LOST_SENT2:-$HOME/.cache/x220-ac-lost.notified2} # Marker: Nachmeldung gesendet
NOW=${TEST_NOW:-$(date +%s)}
mkdir -p "$(dirname "$LOST_FILE")" 2>/dev/null
if [ "$A_AC" = 0 ]; then
  [ -e "$LOST_FILE" ] || echo "$NOW" > "$LOST_FILE"
  SINCE=$(r "$LOST_FILE"); SINCE=${SINCE:-$NOW}
  if [ ! -e "$LOST_SENT" ] && [ $(( NOW - SINCE )) -ge $(( AC_LOST_MIN * 60 )) ]; then
    curl -fsS -m 10 --connect-timeout 5 -H "Title: $HOST Netzteil ab" \
         -H "Priority: high" -H "Tags: electric_plug" \
         -d "Netzteil seit ${AC_LOST_MIN}+ Min nicht angesteckt, Akku ${A_BAT}%" "$NTFY_URL" >/dev/null 2>&1 \
      && : > "$LOST_SENT"
  fi
  if [ ! -e "$LOST_SENT2" ] && [ $(( NOW - SINCE )) -ge $(( AC_STILL_MIN * 60 )) ]; then
    curl -fsS -m 10 --connect-timeout 5 -H "Title: $HOST Immer noch abgesteckt" \
         -H "Priority: high" -H "Tags: electric_plug" \
         -d "Immer noch abgesteckt: Netzteil seit ${AC_STILL_MIN}+ Min ab, Akku ${A_BAT}%" "$NTFY_URL" >/dev/null 2>&1 \
      && : > "$LOST_SENT2"
  fi
elif [ "$A_AC" = 1 ]; then
  rm -f "$LOST_FILE" "$LOST_SENT" "$LOST_SENT2"
fi

# --- Hibernate bei Akku <= HIB_AT % ohne Netzteil ---
# Braucht sudoers-Regel (siehe sudoers_x220-hibernate). Nach einem Resume Sperrzeit
# HIB_COOLDOWN s, damit ein weiterhin leerer Akku nicht sofort wieder hibernatet.
# HIB_CMD ist fuer Tests ueberschreibbar (z. B. "echo").
HIB_AT=${HIB_AT:-6}
HIB_CMD=${HIB_CMD:-sudo -n /usr/sbin/pm-hibernate}
HIB_COOLDOWN=${HIB_COOLDOWN:-900}
HIB_STAMP=${HIB_STAMP:-$HOME/.cache/x220-hibernate.stamp}
if [ "$A_AC" = 0 ] && [[ "$A_BAT" =~ ^[0-9]+$ ]] && [ "$A_BAT" -le "$HIB_AT" ]; then
  LASTHIB=$(r "$HIB_STAMP"); LASTHIB=${LASTHIB:-0}
  if [ $(( NOW - LASTHIB )) -ge "$HIB_COOLDOWN" ]; then
    echo "$NOW" > "$HIB_STAMP"
    curl -fsS -m 10 --connect-timeout 5 -H "Title: $HOST hibernatet" \
         -H "Priority: urgent" -H "Tags: zzz" \
         -d "Akku ${A_BAT}% (<= ${HIB_AT}%), kein Netzteil: gehe in den Ruhezustand" "$NTFY_URL" >/dev/null 2>&1
    sync
    if $HIB_CMD >/dev/null 2>&1; then
      echo "$(date '+%Y-%m-%dT%H:%M:%S%z') HIBERNATE-OK (Rueckkehr aus Ruhezustand) HOST=${HOST}" >> "$LOG"
    else
      echo "$(date '+%Y-%m-%dT%H:%M:%S%z') HIBERNATE-FEHLER rc=$? cmd=${HIB_CMD} HOST=${HOST}" >> "$LOG"
    fi
  fi
fi
