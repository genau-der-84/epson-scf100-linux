#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# epson-scf100-linux: set up the Epson SC-F100 (dye sublimation) as a regular CUPS printer.
# Dialogs and messages in German for a German locale, English for every other language. Help: ./install.sh -h
#
# What it does:
#   1. Check dependencies: CUPS, Python with Pillow/LittleCMS, 7-Zip and bsdtar (for the profiles).
#   2. Download Epson's escpr2 (closed library, Epson licence) if no suitable version is installed:
#      Debian/Ubuntu .deb, Fedora/openSUSE .rpm, otherwise the .rpm unpacked to /opt. Fixed checksum.
#   3. Own files: filter, Python module, PPD.
#   4. Fetch the ICC profiles from Epson's official macOS driver (not shipped, (c) Seiko Epson).
#   5. Create print queues: USB and/or network, optionally a variant without colour conversion for
#      applications that cannot reach the driver options (e.g. under Wine). -c or the menu switches
#      the colour management of existing queues.
set -euo pipefail

NAME=scf100-sublimation
SRC=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
VERSION=$(cat "$SRC/VERSION" 2>/dev/null || echo unknown)
LIB=/usr/lib/$NAME
DATA=/usr/share/$NAME
PROFILES=$DATA/profiles
PPD_DIR=/usr/share/ppd/$NAME
STATE=/var/lib/$NAME
ESCPR2_VER=1.2.43
ESCPR2_RPM_URL="https://download-center.epson.com/f/module/a6ae8171-6d05-4d46-82db-395524b10875/epson-inkjet-printer-escpr2-1.2.43-1.x86_64.rpm"
ESCPR2_RPM_SHA=bd078ca885c8a3456fcba30ef86bdaff2e5464ba5df0147425dc571f9cb7db9e
ESCPR2_DEB_URL="https://download-center.epson.com/f/module/ad51740c-2aeb-4566-a16b-71e9a3c43604/epson-inkjet-printer-escpr2_1.2.43-1_amd64.deb"
ESCPR2_DEB_SHA=d26facfd537507cc067da18f385ce67f8d846fa76f712d09b1b2a7a23fddbda5
WRAPPER_PATHS="/usr/lib/cups/filter/epson-escpr-wrapper2 /usr/libexec/cups/filter/epson-escpr-wrapper2 /opt/epson-inkjet-printer-escpr2/cups/lib/filter/epson-escpr-wrapper2"

# --- Language: German for a German locale, otherwise English ---------------------------------------
# sudo usually keeps LANG/LC_*; without them the system locale applies.
detect_language() {
  local l="${LC_ALL:-${LC_MESSAGES:-${LANGUAGE:-${LANG:-}}}}" f
  if [ -z "$l" ] || [ "$l" = C ] || [ "$l" = POSIX ]; then
    for f in /etc/locale.conf /etc/default/locale; do
      [ -r "$f" ] && l=$(sed -n 's/^LANG=["]\{0,1\}\([^"]*\)["]\{0,1\}$/\1/p' "$f" | head -1) && [ -n "$l" ] && break
    done
  fi
  case "$l" in de|de_*|de.*|de:*) echo de ;; *) echo en ;; esac
}
UI_LANG=$(detect_language)
t() { if [ "$UI_LANG" = de ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }   # t "deutsch" "english"

usage() {
  if [ "$UI_LANG" = de ]; then cat <<'EOF'
Epson SC-F100 (Sublimation) als normalen Drucker einrichten.

  sudo ./install.sh                  Einrichtung mit Auswahlfenstern

Ohne Fenster:
  -n, --netz ADRESSE|auto            Netz-Warteschlange (LPR); "auto" sucht den Drucker im Netz
  -s, --suchen                       nur nach SC-F100 im Netz suchen und anzeigen
  -m, --medium rigid|textile         vorgewähltes Papier (Standard: rigid)
  -q, --qualitaet stark|standard     vorgewählte Qualität (Standard: stark)
  -a, --programmfarbe                zusätzlich eine Warteschlange "...-Programmfarbe" ohne Farbumrechnung
                                     (für Farbverwaltung im Programm mit dem Epson-Profil, z. B. Affinity unter Wine)
  -c, --farbe treiber|keine          Farbverwaltung der vorhandenen Warteschlangen umstellen, sonst nichts
  -o, --nur-treiber                  nur den Treiber, keine Warteschlange
  -d, --dmg DATEI                    Epson-macOS-Treiber (.dmg) für die ICC-Profile von hier nehmen
  -u, --entfernen                    alles wieder entfernen
  -y, -j, --ja                       keine Rückfragen (auch die Paketverwaltung bestätigt dann selbst)
  -g, --dialog                       Auswahlfenster auch zusammen mit Optionen
  -t, --text                         Fragen als Text statt in Fenstern
  -l, --sprache de|en                Sprache festlegen (sonst nach Locale)
  -V, --version                      Version anzeigen
  -h, --hilfe                        diese Hilfe

Jede Option gibt es auch auf Englisch (--network, --search, --media, --quality, --app-color, --color,
--driver-only, --uninstall, --yes, --lang, --help).
EOF
  else cat <<'EOF'
Set up the Epson SC-F100 (dye sublimation) as a regular printer.

  sudo ./install.sh                  guided setup with dialog windows

Without dialogs:
  -n, --network ADDRESS|auto         network queue (LPR); "auto" searches the network for the printer
  -s, --search                       only search the network for SC-F100 printers and list them
  -m, --media rigid|textile          default paper (default: rigid)
  -q, --quality high|standard        default quality (default: high)
  -a, --app-color                    also create a queue "...-AppColor" without colour conversion (for
                                     colour management in the application with the Epson profile, e.g. Affinity under Wine)
  -c, --color driver|none            switch colour management of the existing queues, nothing else
  -o, --driver-only                  install the driver only, no print queue
  -d, --dmg FILE                     use this Epson macOS driver (.dmg) for the ICC profiles
  -u, --uninstall                    remove everything again
  -y, --yes                          do not ask questions (the package manager confirms by itself, too)
  -g, --dialog                       dialog windows even when options are given
  -t, --text                         plain text questions instead of dialog windows
  -l, --lang de|en                   set the language (default: from the locale)
  -V, --version                      show the version
  -h, --help                         this help

German option names work as well (--netz, --suchen, --medium, --qualitaet, --programmfarbe, --farbe,
--nur-treiber, --entfernen, --ja, --sprache, --hilfe).
EOF
  fi
}

YES=0; DMG=""; NETWORK=(); QUEUES=1; ACTION=install; WANT_USB=1
MEDIA=Rigid; QUALITY=High; DIALOG=""; SEARCH_ONLY=0; APP_COLOR=0; COLOR=""
ARGS="$*"
[ $# -eq 0 ] && [ -t 0 ] && [ -t 1 ] && DIALOG=auto
need_value() { [ $# -ge 2 ] && [ -n "$2" ] || { echo "$(t "Wert fehlt für" "missing value for") $1" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    -y|-j|--yes|--ja) YES=1 ;;
    -d|--dmg) need_value "$@"; DMG=$(readlink -f "$2"); shift ;;
    -n|--network|--netz) need_value "$@"; NETWORK+=("$2"); shift ;;
    -s|--search|--suchen) SEARCH_ONLY=1 ;;
    -m|--media|--medium) need_value "$@"; MEDIA=$2; shift ;;
    -q|--quality|--qualitaet|--qualität) need_value "$@"; QUALITY=$2; shift ;;
    -a|--app-color|--app-colour|--programmfarbe) APP_COLOR=1 ;;
    -c|--color|--colour|--farbe) need_value "$@"; COLOR=$2; ACTION=color; shift ;;
    -o|--driver-only|--nur-treiber|--ohne-drucker) QUEUES=0 ;;
    -u|--uninstall|--remove|--entfernen) ACTION=uninstall ;;
    -g|--dialog) DIALOG=auto ;;
    -t|--text) DIALOG=text ;;
    -l|--lang|--language|--sprache) need_value "$@"
       case "$2" in de*) UI_LANG=de ;; en*) UI_LANG=en ;; *) echo "--lang: de|en" >&2; exit 2 ;; esac; shift ;;
    -V|--version) echo "epson-scf100-linux $VERSION"; exit 0 ;;
    -h|--help|--hilfe) usage; exit 0 ;;
    *) echo "$(t "Unbekannte Option" "Unknown option"): $1 ($(t "Hilfe: $0 -h" "help: $0 -h"))" >&2; exit 2 ;;
  esac
  shift
done
USER_YES=$YES   # -y given by the user (the guided setup sets YES=1 later, after its summary)
case "${MEDIA,,}" in rigid) MEDIA=Rigid ;; textile|textil) MEDIA=Textile ;;
  *) echo "--media: rigid|textile" >&2; exit 2 ;; esac
case "${QUALITY,,}" in high|stark|hoch) QUALITY=High ;; standard|normal) QUALITY=Standard ;;
  *) echo "--quality: high|standard ($(t "oder stark" "or stark"))" >&2; exit 2 ;; esac
case "${COLOR,,}" in "") ;; driver|treiber) COLOR=Driver ;; none|keine|application|app|programm) COLOR=Application ;;
  *) echo "--color: driver|none ($(t "oder treiber|keine" "or treiber|keine"))" >&2; exit 2 ;; esac

# Queue names follow the language; existing queues keep their name (both spellings are recognised)
USB_QUEUE=SC-F100-USB
NET_QUEUE=$(t SC-F100-Netz SC-F100-Network)
SUFFIX=$(t -Programmfarbe -AppColor)
is_variant() { case "$1" in *-Programmfarbe|*-AppColor) return 0 ;; esac; return 1; }

info()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[33m%s: %s\033[0m\n' "$(t WARNUNG WARNING)" "$*" >&2; }
die()   { printf '\033[31m%s: %s\033[0m\n' "$(t FEHLER ERROR)" "$*" >&2; exit 1; }

# --- User interface: whiptail, else dialog, else plain questions in the terminal --------------------
TITLE=$(t "Epson SC-F100 Sublimation – Einrichtung" "Epson SC-F100 Sublimation – Setup")
UI=text
if [ "$DIALOG" = auto ]; then
  if command -v whiptail >/dev/null; then UI=whiptail; elif command -v dialog >/dev/null; then UI=dialog
  else echo "$(t "Hinweis: Für Auswahlfenster fehlt whiptail (Paket newt, whiptail bzw. libnewt). Die Fragen kommen als Text." \
                 "Note: whiptail is missing for dialog windows (package newt, whiptail or libnewt). Questions come as text.")"; fi
fi
window() {  # call whiptail/dialog; the selection goes to stdout
  "$UI" --title "$TITLE" "$@" 3>&1 1>&2 2>&3
}
ui_message() {  # text
  if [ "$UI" = text ]; then
    printf '\n%b\n\n' "$1"; [ "$YES" = 1 ] || read -r -p "$(t "Weiter mit Enter " "Press Enter to continue ")" _; return 0
  fi
  window --msgbox "$1" 20 78
}
ui_notice() {  # text, without waiting for a key
  if [ "$UI" = text ]; then printf '%b\n' "$1"; else "$UI" --title "$TITLE" --infobox "$1" 8 60; fi
}
ui_yesno() {  # question -> return code 0 = yes
  [ "$YES" = 1 ] && return 0
  if [ "$UI" = text ]; then
    local a; read -r -p "$(printf '%b' "$1") $(t "[J/n]" "[Y/n]") " a; [ -z "$a" ] || [[ "$a" =~ ^[JjYy] ]]; return
  fi
  window --yesno "$1" 16 78
}
ui_input() {  # question default -> text on stdout
  if [ "$UI" = text ]; then local a; read -r -p "$1 [$2] " a; echo "${a:-$2}"; return; fi
  window --inputbox "$1" 10 78 "$2"
}
ui_menu() {  # question tag text [tag text ...] -> tag on stdout
  local question=$1; shift
  if [ "$UI" = text ]; then
    local i=1 tags=() a
    printf '\n%b\n' "$question" >&2
    while [ $# -gt 0 ]; do printf '  %d) %s\n' "$i" "$2" >&2; tags+=("$1"); shift 2; i=$((i + 1)); done
    read -r -p "$(t "Auswahl" "Choice") [1] " a; a=${a:-1}
    [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le ${#tags[@]} ] || return 1
    echo "${tags[$((a - 1))]}"; return
  fi
  window --menu "$question" 22 78 6 "$@"
}

# --- Finding the printer ------------------------------------------------------------------------
# The SC-F100 announces itself via mDNS/Bonjour as "UNIX Printer" (_printer._tcp, port 515) with its
# IPv4 address. Without a running avahi-daemon, CUPS' SNMP search remains.
# Output: one line "ADDRESS<TAB>DESCRIPTION" per printer found.
search_printers() {
  local found=""
  if command -v avahi-browse >/dev/null; then
    found=$(timeout 8 avahi-browse -rpt _printer._tcp 2>/dev/null \
      | awk -F';' '$1 == "=" && $3 == "IPv4" && /SC-F100/ { n = $4; gsub(/\\032/, " ", n); print $8 "\t" n " (" $7 ")" }' \
      | sort -u) || true
  fi
  if [ -z "$found" ] && command -v lpinfo >/dev/null; then
    # The model name is only in the long listing (-l); the short one prints just class and URI
    found=$(timeout 30 lpinfo -l --include-schemes snmp -v 2>/dev/null \
      | awk '/^Device: uri = / { uri = $4 }
             /^[ \t]+make-and-model = .*SC-F100/ && match(uri, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {
               print substr(uri, RSTART, RLENGTH) "\tEPSON SC-F100 (SNMP)" }' \
      | sort -u) || true
  fi
  printf '%s' "$found"
}
lpr_reachable() { timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/515"' _ "$1" 2>/dev/null; }
start_cups() {
  systemctl is-active -q cups 2>/dev/null || systemctl start cups 2>/dev/null || systemctl start cups.socket 2>/dev/null || true
}
find_usb() {  # ask only the USB backend: fast, and does not hang on network backends
  lpinfo --include-schemes usb -v 2>/dev/null | awk '$2 ~ /^usb:\/\/EPSON\/SC-F100/ {print $2; exit}' || true; }
queue_exists() { lpstat -v "$1" >/dev/null 2>&1; }
existing_name() {  # preferred name, other-language name -> the one that exists, else the preferred one
  if ! queue_exists "$1" && queue_exists "$2"; then echo "$2"; else echo "$1"; fi
}

# --- Colour management ---------------------------------------------------------------------------
# The queue default (lpadmin) applies to all users. A user's own value in ~/.cups/lpoptions takes
# precedence, though; set_color therefore also removes that of the calling user, otherwise the switch
# would have no effect for them.
own_queues() {  # all queues of this driver, one name per line
  local q
  for q in $(lpstat -v 2>/dev/null | awk '{print $3}' | tr -d ':'); do
    timeout 10 lpoptions -p "$q" 2>/dev/null | grep -q 'scf100' && echo "$q"   # timeout: foreign network printers can hang
  done
  return 0
}
color_of() {  # queue -> Driver | Application
  timeout 10 lpoptions -p "$1" -l 2>/dev/null | awk -F': ' '$1 ~ /^ScfColor\// { n = split($2, w, " ");
    for (i = 1; i <= n; i++) if (w[i] ~ /^\*/) print substr(w[i], 2) }'
}
color_name() {
  if [ "$1" = Application ]; then t "keine Umrechnung (Farbverwaltung im Programm)" "no conversion (colour management in the application)"
  else t "Treiber rechnet mit dem Epson-Profil um" "driver converts with the Epson profile"; fi
}
set_color() {  # queue Driver|Application
  local out u="${SUDO_USER:-}"
  out=$(lpadmin -p "$1" -o "ScfColor=$2" 2>&1) || die "lpadmin -p $1: $out"
  if [ -n "$u" ] && [ "$u" != root ] && sudo -H -u "$u" lpoptions -p "$1" 2>/dev/null | grep -q 'ScfColor='; then
    sudo -H -u "$u" lpoptions -p "$1" -r ScfColor >/dev/null 2>&1 || true
    echo "  $(t "Eigene Einstellung von $u für $1 entfernt (ging der Vorgabe vor)." "Removed $u's own setting for $1 (it overrode the default).")"
  fi
  echo "  $1: $(color_name "$(color_of "$1")")"
}
switch_color() {  # without COLOR: interactive; with COLOR: all queues except the variants
  local qs q choice entries=()
  mapfile -t qs < <(own_queues)
  if [ ${#qs[@]} -eq 0 ]; then
    ui_message "$(t "Es gibt noch keine Warteschlange dieses Treibers. Bitte zuerst installieren." \
                    "There is no print queue of this driver yet. Please install first.")"; exit 1
  fi
  if [ -n "$COLOR" ]; then
    info "$(t "Farbverwaltung umstellen" "Switching colour management")"
    for q in "${qs[@]}"; do is_variant "$q" || set_color "$q" "$COLOR"; done
    return
  fi
  if [ ${#qs[@]} -eq 1 ]; then q=${qs[0]}
  else
    for q in "${qs[@]}"; do entries+=("$q" "$(color_name "$(color_of "$q")")"); done
    q=$(ui_menu "$(t "Welche Warteschlange?" "Which print queue?")" "${entries[@]}") || exit 1
  fi
  choice=$(ui_menu "$(t "Farbverwaltung für $q
Jetzt: $(color_name "$(color_of "$q")")

Gilt für alle Programme, die diese Warteschlange nutzen, solange im
Druckdialog nichts anderes gewählt wird. Programme unter Wine (z. B. Affinity)
nehmen immer diese Vorgabe." \
"Colour management for $q
Now: $(color_name "$(color_of "$q")")

Applies to every application using this queue unless something else is chosen
in the print dialog. Applications under Wine (e.g. Affinity) always use this
default.")" \
    Driver "$(t "Treiber rechnet um (GIMP, Inkscape, Bildbetrachter ...)" "Driver converts (GIMP, Inkscape, image viewers ...)")" \
    Application "$(t "Keine – die Farbverwaltung des Programms rechnet ins Epson-Profil um" "None – the application's colour management converts to the Epson profile")") || exit 1
  [ "$UI" = text ] || clear
  info "$(t "Farbverwaltung umstellen" "Switching colour management")"
  set_color "$q" "$choice"
}

# --- Guided setup -------------------------------------------------------------------------------
guided() {
  local choice
  choice=$(ui_menu "$(t "Was möchtest du tun?

Dieser Treiber druckt Transferpapiere auf dem Epson SC-F100 aus jedem
Linux-Programm, mit Epsons offiziellen ICC-Profilen wie unter Windows.
Er nutzt Epsons escpr2 und die Profile aus Epsons macOS-Treiber.
Beides wird direkt bei Epson geladen." \
"What would you like to do?

This driver prints transfer paper on the Epson SC-F100 from any Linux
application, with Epson's official ICC profiles, just like on Windows.
It relies on Epson's escpr2 and on the profiles from Epson's macOS driver,
both downloaded directly from Epson.")" \
    install "$(t "Installieren oder aktualisieren" "Install or update")" \
    color "$(t "Farbverwaltung einer Warteschlange umstellen" "Switch the colour management of a queue")" \
    uninstall "$(t "Alles wieder entfernen" "Remove everything")") || exit 1
  if [ "$choice" = color ]; then ACTION=color; return; fi
  if [ "$choice" = uninstall ]; then
    ui_yesno "$(t "Treiber, Profile und alle SC-F100-Warteschlangen dieses Treibers entfernen?" \
                  "Remove the driver, the profiles and all SC-F100 queues of this driver?")" || exit 1
    ACTION=uninstall; return
  fi

  start_cups
  local usb usb_text
  usb=$(find_usb)
  if [ -n "$usb" ]; then usb_text=$(t "angeschlossen" "connected"); else usb_text=$(t "derzeit nicht angeschlossen" "not connected right now"); fi
  choice=$(ui_menu "$(t "Wie ist der Drucker angeschlossen?

Je Verbindung gibt es eine eigene Warteschlange. Beides zugleich geht auch,
z. B. daheim im Netz und unterwegs per USB. USB: $usb_text." \
"How is the printer connected?

Each connection gets its own print queue. Both at once is fine too,
e.g. network at home and USB on the road. USB: $usb_text.")" \
    both "$(t "USB und Netzwerk" "USB and network")" \
    network "$(t "Nur Netzwerk" "Network only")" \
    usb "$(t "Nur USB" "USB only")" \
    none "$(t "Keine Warteschlange, nur den Treiber installieren" "No print queue, install the driver only")") || exit 1
  case $choice in
    none) QUEUES=0 ;;
    network) WANT_USB=0 ;;
    *) WANT_USB=1 ;;
  esac
  if [ "$WANT_USB" = 1 ] && [ "$QUEUES" = 1 ] && [ -z "$usb" ]; then
    ui_message "$(t "Per USB ist gerade kein SC-F100 angeschlossen.

Die USB-Warteschlange entsteht, sobald du den Drucker einsteckst, einschaltest
und dieses Skript erneut startest. Der Rest wird jetzt schon eingerichtet." \
"No SC-F100 is connected via USB right now.

The USB queue is created once you plug in and switch on the printer and run
this script again. Everything else is set up now.")"
  fi
  if [ "$choice" = network ] || [ "$choice" = both ]; then
    ui_notice "$(t "Suche SC-F100 im Netz ..." "Searching the network for SC-F100 ...")"
    local found addr="" entries=() a n
    found=$(search_printers)
    if [ -n "$found" ]; then
      while IFS=$'\t' read -r a n; do
        if [ "$UI" = text ]; then entries+=("$a" "$n, $a"); else entries+=("$a" "$n"); fi   # windows show the address as tag
      done <<<"$found"
      addr=$(ui_menu "$(t "Gefundene Drucker:" "Printers found:")" "${entries[@]}" \
             manual "$(t "Adresse selbst eingeben" "Enter the address manually")") || exit 1
      [ "$addr" = manual ] && addr=""
    else
      ui_message "$(t "Im Netz wurde kein SC-F100 gefunden.

Die Adresse steht am Drucker im Netzwerkstatus (Einstellungen >
Netzwerkeinstellungen) oder im Router bei den verbundenen Geräten." \
"No SC-F100 was found on the network.

The printer shows its address in its network status (Settings >
Network Settings), or look it up in your router's list of devices.")"
    fi
    while [ -z "$addr" ]; do
      addr=$(ui_input "$(t "IP-Adresse oder Name des Druckers:" "IP address or host name of the printer:")" "") || exit 1
    done
    if ! lpr_reachable "$addr"; then
      ui_yesno "$(t "Unter $addr antwortet kein Druckdienst (LPR, Port 515).

Trotzdem so anlegen?" "No print service answers at $addr (LPR, port 515).

Create the queue anyway?")" || exit 1
    fi
    NETWORK=("$addr")
  fi
  if [ "$QUEUES" = 1 ]; then
    MEDIA=$(ui_menu "$(t "Welches Papier soll vorgewählt sein?

Im Druckdialog jedes Programms lässt es sich jederzeit umstellen." \
"Which paper should be preselected?

It can be changed at any time in the print dialog of every application.")" \
      Rigid "$(t "DS Transfer General Purpose – Rigid (Tassen, Hartwaren)" "DS Transfer General Purpose – Rigid (mugs, hard goods)")" \
      Textile "$(t "DS Transfer General Purpose – Textile (Stoffe)" "DS Transfer General Purpose – Textile (fabrics)")") || exit 1
    QUALITY=$(ui_menu "$(t "Welche Druckqualität soll vorgewählt sein?" "Which print quality should be preselected?")" \
      High "$(t "Stark (Vorgabe für Sublimation)" "High (recommended for sublimation)")" \
      Standard "$(t "Standard (schneller)" "Standard (faster)")") || exit 1
    choice=$(ui_menu "$(t "Zusätzliche Warteschlange ohne Farbumrechnung anlegen?

Für Programme, in denen du die Farbverwaltung dem Programm überlässt und das
Epson-Profil als Druckerprofil wählst, vor allem Windows-Programme unter Wine
(Affinity, Photoshop ...). Deren Druckdialog zeigt die Optionen dieses
Treibers nicht. Alle anderen Programme nutzen die normale Warteschlange." \
"Create an additional queue without colour conversion?

For applications where you leave colour management to the application and
choose the Epson profile as printer profile, mainly Windows applications under
Wine (Affinity, Photoshop ...). Their print dialog does not show this driver's
options. All other applications use the regular queue.")" \
      no "$(t "Nein" "No")" \
      yes "$(t "Ja, zusätzlich „…$SUFFIX“ anlegen" "Yes, also create \"…$SUFFIX\"")") || exit 1
    [ "$choice" = yes ] && APP_COLOR=1
  fi
  local summary; summary="$(t "Zusammenfassung:" "Summary:")\n\n"
  if [ "$QUEUES" = 1 ]; then
    [ "$WANT_USB" = 1 ] && summary+="  - USB: $USB_QUEUE ($usb_text)\n"
    [ ${#NETWORK[@]} -gt 0 ] && summary+="  - $(t Netzwerk Network): $(existing_name "$NET_QUEUE" "$(other_net_queue)") -> ${NETWORK[0]}\n"
    summary+="  - $(t Vorgabe Defaults): $MEDIA, $(t "Qualität" quality) $(quality_name)\n"
    [ "$APP_COLOR" = 1 ] && summary+="  - $(t "dazu ohne Farbumrechnung" "plus without colour conversion"): $(variant_base)$SUFFIX\n"
  else
    summary+="  - $(t "nur Treiber, keine Warteschlange" "driver only, no print queue")\n"
  fi
  summary+="\n$(t "Fehlende Pakete, Epsons escpr2 und die ICC-Profile werden bei Bedarf
heruntergeladen. Jetzt einrichten?" "Missing packages, Epson's escpr2 and the ICC profiles are downloaded
if needed. Set up now?")"
  ui_yesno "$summary" || exit 1
  YES=1   # all questions are answered, the rest runs through
}
other_net_queue() { if [ "$NET_QUEUE" = SC-F100-Netz ]; then echo SC-F100-Network; else echo SC-F100-Netz; fi; }
variant_base() { if [ ${#NETWORK[@]} -gt 0 ]; then existing_name "$NET_QUEUE" "$(other_net_queue)"; else echo "$USB_QUEUE"; fi; }
quality_name() { if [ "$QUALITY" = High ]; then t "Stark" "High"; else echo Standard; fi; }

[ "${SCF100_FUNCTIONS_ONLY:-}" = 1 ] && return 0 2>/dev/null   # for tests: load the functions only
[ "$(id -u)" = 0 ] || die "$(t "Bitte mit sudo starten" "Please run with sudo"): sudo $0 $ARGS"

if [ "$SEARCH_ONLY" = 1 ]; then
  start_cups
  info "$(t "SC-F100 im Netz suchen" "Searching the network for SC-F100")"
  f=$(search_printers)
  if [ -n "$f" ]; then printf '%s\n' "$f" | sed 's/^/  /'
  else echo "  $(t "Nichts gefunden. Ist der Drucker eingeschaltet und im selben Netz?" "Nothing found. Is the printer switched on and on the same network?")"; fi
  exit 0
fi

# Resolve the network address "auto" (non-interactive call)
for i in "${!NETWORK[@]}"; do
  [ "${NETWORK[$i]}" = auto ] || continue
  start_cups
  info "$(t "SC-F100 im Netz suchen" "Searching the network for SC-F100")"
  f=$(search_printers)
  [ -n "$f" ] || die "$(t "Kein SC-F100 im Netz gefunden. Adresse am Drucker ablesen (Netzwerkstatus) und mit -n ADRESSE angeben." \
                          "No SC-F100 found on the network. Look up the address on the printer (network status) and pass it with -n ADDRESS.")"
  [ "$(printf '%s\n' "$f" | wc -l)" = 1 ] || die "$(t "Mehrere SC-F100 gefunden - bitte einen mit -n ADRESSE wählen:" \
                                                      "Several SC-F100 found - please pick one with -n ADDRESS:")
$f"
  NETWORK[i]=$(cut -f1 <<<"$f"); echo "  $(t gefunden found): $(cut -f2 <<<"$f") - ${NETWORK[$i]}"
done

if [ "$ACTION" = install ] && { [ "$DIALOG" = auto ] || { [ "$DIALOG" = text ] && [ "$YES" = 0 ]; }; }; then
  guided
  [ "$UI" = text ] || clear
fi

# shellcheck disable=SC1091
. /etc/os-release
FAMILY=other
case " ${ID:-} ${ID_LIKE:-} " in
  *" arch "*|*" manjaro "*) FAMILY=arch ;;
  *" debian "*|*" ubuntu "*) FAMILY=debian ;;
  *" fedora "*|*" rhel "*) FAMILY=fedora ;;
  *" suse "*|*" opensuse "*) FAMILY=suse ;;
esac
FILTER_DIR=$( (cups-config --serverbin 2>/dev/null || echo /usr/lib/cups) | head -1)/filter

# The package manager confirms by itself only if the user gave -y. Otherwise it shows its own summary and
# asks: a transaction can do more than install the requested package (Fedora's dnf removed old kernels
# because of installonly_limit while installing bsdtar, test 21.10.2026); the user must see that.
pkg_install() {  # packages or local package files...
  local y=()
  case $FAMILY in
    arch)   [ "$USER_YES" = 1 ] && y=(--noconfirm); pacman -S --needed "${y[@]}" "$@" ;;
    debian) [ "$USER_YES" = 1 ] && y=(-y); apt-get install "${y[@]}" "$@" ;;
    fedora) [ "$USER_YES" = 1 ] && y=(-y); dnf install "${y[@]}" "$@" ;;
    suse)   [ "$USER_YES" = 1 ] && y=(-y)
            local g=(); case " $* " in *".rpm "*) g=(--no-gpg-checks) ;; esac   # global option, only for Epson's unsigned rpm (checksum verified)
            zypper "${g[@]}" install "${y[@]}" "$@" ;;
  esac || die "$(t "Paketinstallation abgebrochen oder fehlgeschlagen" "Package installation cancelled or failed"): $*"
}

uninstall() {
  info "$(t "Warteschlangen entfernen" "Removing print queues")"
  local q
  for q in $(own_queues); do lpadmin -x "$q" && echo "  $q"; done
  info "$(t "Dateien entfernen" "Removing files")"
  rm -f "$FILTER_DIR/rastertoscf100" /usr/bin/scf100-fetch-icc /usr/bin/scf100-icc-holen
  rm -rf "$LIB" "$PPD_DIR" "$DATA"
  if [ -f "$STATE/escpr2-unpacked" ] || [ -f "$STATE/escpr2-entpackt" ]; then
    info "$(t "Von hier entpacktes Epson-escpr2 entfernen" "Removing the Epson escpr2 unpacked by this script")"
    rm -rf /opt/epson-inkjet-printer-escpr2
  fi
  rm -rf "$STATE"
  info "$(t "Fertig. Ein per Paketverwaltung installiertes Epson-escpr2 bleibt bestehen." \
            "Done. An Epson escpr2 installed through the package manager is left in place.")"
}
[ "$ACTION" = uninstall ] && { uninstall; exit 0; }
[ "$ACTION" = color ] && { start_cups; switch_color; exit 0; }

# --- 1. Dependencies ------------------------------------------------------------------------------
info "$(t "Abhängigkeiten prüfen" "Checking dependencies") ($PRETTY_NAME, $FAMILY)"
MISSING=()
command -v lpadmin >/dev/null || MISSING+=(cups)
python3 -c "from PIL import ImageCms" 2>/dev/null || MISSING+=(pillow)
command -v 7z >/dev/null || command -v 7zz >/dev/null || MISSING+=(7zip)
command -v bsdtar >/dev/null || MISSING+=(bsdtar)
command -v curl >/dev/null || MISSING+=(curl)
if [ ${#MISSING[@]} -gt 0 ]; then
  case $FAMILY in
    arch)   declare -A P=([cups]=cups [pillow]=python-pillow [7zip]=7zip [bsdtar]=libarchive [curl]=curl) ;;
    debian) declare -A P=([cups]=cups [pillow]=python3-pil [7zip]=7zip [bsdtar]=libarchive-tools [curl]=curl)
            apt-get update -qq
            apt-cache show 7zip >/dev/null 2>&1 || P[7zip]=p7zip-full ;;     # Ubuntu 22.04: only p7zip
    fedora) declare -A P=([cups]=cups [pillow]=python3-pillow [7zip]=7zip [bsdtar]=bsdtar [curl]=curl) ;;
    suse)   declare -A P=([cups]=cups [pillow]=python3-Pillow [7zip]=7zip [bsdtar]=bsdtar [curl]=curl) ;;
    *) die "$(t "Es fehlen: ${MISSING[*]} - bitte mit der Paketverwaltung nachinstallieren" \
                "Missing: ${MISSING[*]} - please install them with your package manager")" ;;
  esac
  PACKAGES=(); for f in "${MISSING[@]}"; do PACKAGES+=("${P[$f]}"); done
  ui_yesno "$(t "Fehlende Pakete installieren" "Install missing packages"): ${PACKAGES[*]}?" || die "$(t Abgebrochen Cancelled)"
  pkg_install "${PACKAGES[@]}"
fi

# --- 2. Epson escpr2 ---------------------------------------------------------------------------
# Older escpr2 (e.g. 1.2.9) print custom sizes as A4. The first wrapper with a sufficient version is
# chosen; the filter reads the choice from $LIB/wrapper.
version_of() {  # wrapper -> "1.2.43" or empty
  python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from scf100.escpr import wrapper_version as v
r = v(sys.argv[2]); print(".".join(map(str, r)) if r else "")' "$SRC/lib" "$1"
}
ESCPR2_MIN=$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from scf100.escpr import ESCPR2_MIN as m
print(".".join(map(str, m)))' "$SRC/lib")
version_ok() { [ -n "$1" ] && [ "$(printf '%s\n%s\n' "$ESCPR2_MIN" "$1" | sort -V | head -1)" = "$ESCPR2_MIN" ]; }
choose_wrapper() {
  WRAPPER=""; TOO_OLD=""
  local w v
  for w in $WRAPPER_PATHS; do
    [ -x "$w" ] || continue
    v=$(version_of "$w")
    if version_ok "$v"; then WRAPPER=$w; WRAPPER_VER=$v; return 0; fi
    TOO_OLD+="$w (${v:-?}) "
  done
  return 1
}
if choose_wrapper; then
  info "$(t "Epson escpr2 vorhanden" "Epson escpr2 found"): $WRAPPER_VER, $WRAPPER"
else
  [ "$(uname -m)" = x86_64 ] || die "$(t "Epson escpr2 ab $ESCPR2_MIN fehlt. Für $(uname -m) bitte aus den Quellen installieren (AUR/Epson)." \
                                         "Epson escpr2 $ESCPR2_MIN or newer is missing. On $(uname -m) please build it from source (AUR/Epson).")"
  [ -n "$TOO_OLD" ] && warn "$(t "Vorhandenes escpr2 ist zu alt (mindestens $ESCPR2_MIN nötig, ältere drucken das Tassenformat als A4)" \
                                 "Installed escpr2 is too old (at least $ESCPR2_MIN needed, older versions print the mug size as A4)"): $TOO_OLD"
  t "Epsons escpr2 $ESCPR2_VER wird direkt bei Epson geladen und steht unter der Epson-Lizenz
(Quelltext-Teile LGPL-2.1, Bibliothek nur als Objektdatei, siehe COPYING.EPSON im Paket).
" "Epson's escpr2 $ESCPR2_VER is downloaded directly from Epson and is under Epson's license
(source parts LGPL-2.1, library as object file only, see COPYING.EPSON in the package).
"
  ui_yesno "$(t "Epson escpr2 $ESCPR2_VER laden und installieren?" "Download and install Epson escpr2 $ESCPR2_VER?")" \
    || die "$(t "Ohne passendes escpr2 geht es nicht" "A suitable escpr2 is required")"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  download() {  # Epson answers HTTP 403 to curl's default user agent, 200 to an empty one (as nixpkgs does)
    curl -fL --progress-bar --retry 2 --user-agent '' -o "$TMP/$2" "$1"
    echo "$3  $TMP/$2" | sha256sum -c --quiet - \
      || die "$(t "Prüfsumme von $2 stimmt nicht - hat Epson das Paket geändert?" "Checksum of $2 does not match - did Epson change the package?")"
  }
  case $FAMILY in
    debian) download "$ESCPR2_DEB_URL" escpr2.deb $ESCPR2_DEB_SHA; pkg_install "$TMP/escpr2.deb" ;;
    fedora|suse) download "$ESCPR2_RPM_URL" escpr2.rpm $ESCPR2_RPM_SHA; pkg_install "$TMP/escpr2.rpm" ;;
    *)      download "$ESCPR2_RPM_URL" escpr2.rpm $ESCPR2_RPM_SHA
            bsdtar -xf "$TMP/escpr2.rpm" -C / ./opt/epson-inkjet-printer-escpr2
            mkdir -p "$STATE"; echo "$ESCPR2_VER" > "$STATE/escpr2-unpacked" ;;
  esac
  choose_wrapper || die "$(t "escpr2 installiert, aber kein epson-escpr-wrapper2 ab $ESCPR2_MIN gefunden" \
                              "escpr2 installed, but no epson-escpr-wrapper2 $ESCPR2_MIN or newer found"): $TOO_OLD"
  info "$(t "Epson escpr2 installiert" "Epson escpr2 installed"): $WRAPPER_VER, $WRAPPER"
fi

# Epson's .deb does not declare its dependency on libcupsimage (missing on Debian/Ubuntu without
# printer-driver packages; the filter then fails with "libcupsimage.so.2: cannot open shared object file").
missing_libs() { ldd "$1" 2>/dev/null | awk '/not found/ {print $1}'; }
LIBS=$(missing_libs "$WRAPPER")
if [ -n "$LIBS" ]; then
  case $FAMILY in
    debian) for p in libcupsimage2t64 libcupsimage2; do
              apt-cache show "$p" >/dev/null 2>&1 && { LIBPKG=$p; break; }
            done ;;
    suse)   LIBPKG=libcupsimage2 ;;
    fedora) LIBPKG=cups-libs ;;
    arch)   LIBPKG=libcups ;;
  esac
  if [ -n "${LIBPKG:-}" ] && grep -q libcupsimage <<<"$LIBS"; then
    ui_yesno "$(t "Epsons escpr2 braucht noch $LIBPKG. Installieren?" "Epson's escpr2 also needs $LIBPKG. Install it?")" \
      || die "$(t Abgebrochen Cancelled)"
    pkg_install "$LIBPKG"
    LIBS=$(missing_libs "$WRAPPER")
  fi
  [ -z "$LIBS" ] || die "$(t "Dem Epson-Wrapper fehlen Bibliotheken" "Libraries missing for the Epson wrapper"): ${LIBS//$'\n'/ } ($WRAPPER)"
fi

# --- 3. Own files ------------------------------------------------------------------------------
info "$(t "Treiber installieren" "Installing the driver") ($VERSION)"
install -d "$LIB/scf100" "$PPD_DIR" "$PROFILES" "$STATE"
install -m 644 "$SRC"/lib/scf100/*.py "$LIB/scf100/"
install -m 755 "$SRC/filter/rastertoscf100" "$FILTER_DIR/rastertoscf100"
install -m 644 "$SRC/ppd/epson-scf100-sublimation.ppd" "$PPD_DIR/"
install -m 755 "$SRC/tools/fetch-icc.sh" /usr/bin/scf100-fetch-icc
rm -f /usr/bin/scf100-icc-holen "$LIB/rastertoscf100"      # names of earlier development versions
[ -f "$STATE/escpr2-entpackt" ] && mv "$STATE/escpr2-entpackt" "$STATE/escpr2-unpacked"
echo "$WRAPPER" > "$LIB/wrapper"          # preferred by the filter (see step 2)
echo "$VERSION" > "$STATE/version"
if command -v cupstestppd >/dev/null; then
  cupstestppd -q "$PPD_DIR/epson-scf100-sublimation.ppd" || die "$(t "PPD-Prüfung fehlgeschlagen" "PPD check failed") (cupstestppd)"
fi

# --- 4. ICC profiles ----------------------------------------------------------------------------
if [ -f "$PROFILES/rigid.icc" ] && [ -f "$PROFILES/textile.icc" ]; then
  info "$(t "ICC-Profile vorhanden" "ICC profiles present")"
else
  info "$(t "ICC-Profile aus dem offiziellen Epson-macOS-Treiber holen" "Fetching the ICC profiles from Epson's official macOS driver")"
  export SCF100_LANG=$UI_LANG
  if [ -n "$DMG" ]; then /usr/bin/scf100-fetch-icc --dmg "$DMG" "$PROFILES"; else /usr/bin/scf100-fetch-icc "$PROFILES"; fi
fi

# --- 5. Print queues ----------------------------------------------------------------------------
create_queue() {  # name uri description [further lpadmin options]
  # CUPS 2.x warns about every PPD driver that PPD drivers are deprecated. That applies to all PPD
  # drivers and printing keeps working; the message would only confuse. Other lpadmin messages stay visible.
  # ⚠ With -P, cupsd resets all defaults to those of the new PPD. The colour management of an existing
  # queue is therefore passed on explicitly; "$@" takes precedence.
  local out rc=0 name=$1 uri=$2 text=$3 keep=() c; shift 3
  if queue_exists "$name"; then
    c=$(color_of "$name"); [ -n "$c" ] && keep=(-o "ScfColor=$c")
  fi
  out=$(lpadmin -p "$name" -E -v "$uri" -P "$PPD_DIR/epson-scf100-sublimation.ppd" -D "$text" -L "" \
          -o printer-is-shared=false -o "ScfMedia=$MEDIA" -o "ScfQuality=$QUALITY" "${keep[@]}" "$@" 2>&1) || rc=$?
  out=$(grep -v -i -E 'deprecated|veraltet' <<<"$out" || true)
  [ -n "$out" ] && printf '%s\n' "$out" >&2
  [ "$rc" = 0 ] || die "$(t "Warteschlange $name konnte nicht angelegt werden" "Could not create print queue $name") (lpadmin, rc $rc)"
  echo "  $name -> $uri"
  LAST=("$name" "$uri" "$text")
}
LAST=(); CREATED=()
if [ "$QUEUES" = 1 ]; then
  start_cups
  if [ "$WANT_USB" = 1 ]; then
    info "$(t "Drucker suchen (USB)" "Looking for the printer (USB)")"
    USB=$(find_usb)
    if [ -n "$USB" ]; then
      create_queue "$USB_QUEUE" "$USB" "Epson SC-F100 Sublimation (USB)"; CREATED+=("$USB_QUEUE (USB)")
    else
      echo "  $(t "Kein SC-F100 per USB gefunden. Später einstecken und das Skript erneut starten." \
                  "No SC-F100 found via USB. Plug it in later and run this script again.")"
    fi
  fi
  for addr in "${NETWORK[@]}"; do
    info "$(t "Netz-Warteschlange für" "Network print queue for") $addr"
    lpr_reachable "$addr" || warn "$(t "$addr antwortet nicht auf Port 515 (LPR) - Drucker aus oder Adresse falsch?" \
                                       "$addr does not answer on port 515 (LPR) - printer off or wrong address?")"
    q=$(existing_name "$NET_QUEUE" "$(other_net_queue)")
    create_queue "$q" "lpd://$addr/lp" "Epson SC-F100 Sublimation ($(t Netz network) $addr)"; CREATED+=("$q ($addr)")
  done
  # Variant without colour conversion, on the connection created last (network before USB). An existing
  # variant is updated as well, even without -a, and keeps its name (also one in the other language).
  variant=""
  if [ ${#LAST[@]} -gt 0 ]; then
    for v in "${LAST[0]}-Programmfarbe" "${LAST[0]}-AppColor"; do queue_exists "$v" && variant=$v && break; done
    [ -n "$variant" ] && APP_COLOR=1
  fi
  if [ "$APP_COLOR" = 1 ]; then
    if [ ${#LAST[@]} -gt 0 ]; then
      info "$(t "Warteschlange ohne Farbumrechnung" "Print queue without colour conversion")"
      base=("${LAST[@]}"); variant=${variant:-${base[0]}$SUFFIX}
      create_queue "$variant" "${base[1]}" "${base[2]} – $(t "Farbe vom Programm" "colour from application")" -o ScfColor=Application
      CREATED+=("$variant ($(t "ohne Farbumrechnung" "no colour conversion"))")
    else
      warn "$(t "Keine Warteschlange angelegt, daher auch keine ohne Farbumrechnung." "No print queue created, so no queue without colour conversion either.")"
    fi
  fi
fi

info "$(t "Fertig." "Done.")"
echo "  $(t "Treiber" "Driver"):   $FILTER_DIR/rastertoscf100, PPD $PPD_DIR/epson-scf100-sublimation.ppd"
echo "  $(t "Profile" "Profiles"): $PROFILES"
Q=${CREATED[0]:-$USB_QUEUE}; Q=${Q%% *}
echo "  $(t "Drucken:  aus jedem Programm, oder: lp -d $Q datei.pdf" "Printing: from any application, or: lp -d $Q file.pdf")"
echo "  $(t "Vorgabe" "Defaults"):  $(t "Tasse (240 x 100 mm)" "Mug (240 x 100 mm)"), $MEDIA, $(quality_name), $(t gespiegelt mirrored), $(if [ ${#CREATED[@]} -gt 0 ]; then color_name "$(color_of "$Q")"; else color_name Driver; fi)"
echo "  $(t "Farbe:    umstellen mit sudo $0 -c treiber|keine, im Menü dieses Skripts oder in den
            Druckereinstellungen der Arbeitsumgebung (Option „Farbverwaltung“)" \
        "Colour:   switch with sudo $0 -c driver|none, in this script's menu or in the printer
            settings of your desktop (option \"Color Management\")")"
if [ ${#NETWORK[@]} -gt 0 ]; then
  echo "  $(t "Hinweis:  Die Netz-Warteschlange hängt an der Adresse. Damit sie sich nicht ändert, im Router
            eine feste Adresse (DHCP-Reservierung) für den Drucker einrichten." \
          "Note:     The network queue is bound to the address. Give the printer a fixed address in your
            router (DHCP reservation) so it does not change.")"
fi
if [ "$UI" != text ]; then
  w="$(t "Fertig eingerichtet." "Setup complete.")\n\n"
  if [ ${#CREATED[@]} -gt 0 ]; then
    w+="$(t Drucker Printers):\n"; for e in "${CREATED[@]}"; do w+="  - $e\n"; done
  else
    w+="$(t "Keine Warteschlange angelegt." "No print queue created.")\n"
  fi
  w+="\n$(t "Drucken aus jedem Programm. Für Tassen das Format „Tasse (240 x 100 mm)“
wählen und im Programm Hochformat lassen." "Print from any application. For mugs choose the paper size \"Mug (240 x 100 mm)\"
and leave the application set to portrait.")"
  [ "$APP_COLOR" = 1 ] && w+="\n\n$(t "„…$SUFFIX“ ist für Farbverwaltung im Programm (z. B. Affinity unter Wine):
dort das Epson-Profil als Druckerprofil wählen." "\"…$SUFFIX\" is for colour management in the application (e.g. Affinity under
Wine): choose the Epson profile as printer profile there.")"
  [ ${#NETWORK[@]} -gt 0 ] && w+="\n\n$(t "Tipp: Im Router eine feste Adresse für den Drucker einrichten, sonst
findet die Netz-Warteschlange ihn nach einem Adresswechsel nicht mehr." "Tip: give the printer a fixed address in your router, otherwise the network
queue loses it when the address changes.")"
  ui_message "$w"
fi
