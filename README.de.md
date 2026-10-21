# epson-scf100-linux

**Linux-Druckertreiber für den Sublimationsdrucker Epson SureColor SC-F100.**
Tassen, Textilien und Hartwaren aus jedem Linux-Programm bedrucken, mit Epsons offiziellen ICC-Profilen,
genau wie mit dem Windows-Treiber.

[English](README.md) · [Änderungen](CHANGELOG.md) · [Technik (englisch)](docs/how-it-works.md) ·
[Affinity und andere Windows-Programme unter Wine](docs/affinity-wine.de.md)

> Nicht von Seiko Epson Corporation entwickelt, unterstützt oder mit ihr verbunden. „Epson“ und „SureColor“
> sind Marken der Seiko Epson Corporation und werden hier nur genannt, um den unterstützten Drucker zu bezeichnen.

## Wozu

Der SC-F100 ist ein reiner Sublimationsdrucker, und Epson bietet für ihn keinen Linux-Treiber. Der allgemeine Treiber `escpr2`
spricht zwar mit dem Drucker, nimmt aber die falschen Medieneinstellungen und die druckereigene
Farbtabelle. Sublimationsdrucke haben damit falsche Farben. Dieser Treiber sendet dieselben Aufträge wie
der Windows-Treiber, rechnet die Farben mit Epsons offiziellen Sublimationsprofilen um und spiegelt das Bild.

**Ergebnis:** Die Farbwerte, die beim Drucker ankommen, sind dieselben wie vom Windows-Treiber (Byte für Byte
verglichen). Gepresste Tassen von Linux- und Windows-Drucken sehen gleich aus.

## Funktionen

- Ein ganz normaler Drucker: drucken aus GIMP, Inkscape, LibreOffice, Krita, Bildbetrachtern, `lp`.
- Einstellungen im Druckdialog: Medium (DS Transfer **Rigid** für Tassen und Hartwaren, **Textile** für
  Stoffe), Qualität (Stark/Standard), Spiegeln, Farbverwaltung, Renderpriorität, Druckrichtung.
- Formate: **Tasse 240 × 100 mm**, A4, Letter, Legal und eigene Formate bis 216 × 1200 mm.
- Anschluss per USB und Netzwerk (LPR), der Drucker wird im Netz automatisch gefunden.
- Geführte Installation auf Deutsch oder Englisch, je nach eingestellter Sprache.
- Von Epson wird nichts mitgeliefert: Der Installer lädt Epsons `escpr2` und die ICC-Profile direkt bei
  Epson und prüft ihre Prüfsummen.

## Voraussetzungen

- Linux auf **x86_64** mit CUPS 2.x. Für andere Architekturen muss `epson-inkjet-printer-escpr2` ab 1.2.24
  aus den Quellen gebaut werden.
- Python 3 mit Pillow (samt LittleCMS, wie in allen Distributionspaketen).
- 7-Zip und bsdtar zum Entpacken der Profile. Unter Arch/Manjaro, Debian/Ubuntu, Fedora und openSUSE bietet
  der Installer an, fehlende Pakete nachzuinstallieren.
- Internetzugang während der Installation (Downloads bei Epson, rund 75 MB).

## Installation

```sh
git clone https://github.com/genau-der-84/epson-scf100-linux.git
cd epson-scf100-linux
sudo ./install.sh
```

Oder ein Release-Archiv herunterladen, entpacken und im entpackten Ordner `sudo ./install.sh` starten.

Ohne Optionen fragt der Installer in Auswahlfenstern:
- wie der Drucker angeschlossen ist (USB, Netzwerk oder beides),
- welchen der im Netz gefundenen Drucker er nehmen soll,
- welches Medium und welche Qualität vorgewählt sein sollen,
- ob zusätzlich eine Warteschlange für Programme unter Wine entstehen soll.

Ohne `whiptail`/`dialog` stellt er dieselben Fragen als Text.

Ohne Rückfragen:

| Option | Bedeutung |
|---|---|
| `-n`, `--netz ADRESSE\|auto` | Netz-Warteschlange (LPR); `auto` sucht den Drucker im Netz |
| `-s`, `--suchen` | nur die im Netz gefundenen SC-F100 anzeigen |
| `-m`, `--medium rigid\|textile` | vorgewähltes Medium (Standard: rigid) |
| `-q`, `--qualitaet stark\|standard` | vorgewählte Qualität (Standard: stark) |
| `-a`, `--programmfarbe` | zusätzliche Warteschlange `…-Programmfarbe` ohne Farbumrechnung (siehe unten) |
| `-c`, `--farbe treiber\|keine` | Farbverwaltung der vorhandenen Warteschlangen umstellen, sonst nichts |
| `-o`, `--nur-treiber` | nur den Treiber, keine Warteschlange |
| `-d`, `--dmg DATEI` | ICC-Profile aus einem schon heruntergeladenen Epson-macOS-Treiber nehmen |
| `-u`, `--entfernen` | alles entfernen |
| `-y`, `-j`, `--ja` | keine Rückfragen |
| `-t`, `--text` / `-g`, `--dialog` | Fragen als Text / in Fenstern |
| `-l`, `--sprache de\|en` | Sprache (Standard: nach Locale) |
| `-V`, `--version`, `-h`, `--hilfe` | Version, Hilfe |

Beispiele: `sudo ./install.sh -n auto -y` · `sudo ./install.sh -n 192.168.1.50 -m textil` ·
`sudo ./install.sh -u`. Die Kurzoptionen gelten in beiden Sprachen, die langen Namen gibt es auch auf
Englisch (`--network`, `--media`, `--color` …).

Warteschlangen: `SC-F100-USB`, `SC-F100-Netz` (englische Locale: `SC-F100-Network`), auf Wunsch
`…-Programmfarbe` (`…-AppColor`).

**Dem Drucker im Router eine feste IP-Adresse geben** (DHCP-Reservierung). Die Netz-Warteschlange hängt an
der Adresse.

## Drucken

1. Den Drucker `SC-F100-…` wählen und das Format **Tasse (240 × 100 mm)** (oder A4 usw.).
2. Im Programm **Hochformat** lassen. Das Tassenformat ist eine Querformat-Seite, der Treiber dreht sie wie
   der Windows-Treiber in die Vorschubrichtung.
3. In der Größe des Motivs drucken, z. B. in GIMP mit Bildauflösung 300 ppi und „Seitenränder ignorieren“.
   Spiegeln ist voreingestellt, wie für den Sublimationstransfer nötig.

Auf der Kommandozeile: `lp -d SC-F100-Netz motiv.pdf`. Für ein Bild in Tassengröße (240 × 100 mm, z. B.
2835 × 1181 Pixel bei 300 ppi) zusätzlich `-o print-scaling=none`:
`lp -d SC-F100-Netz -o print-scaling=none motiv.png`. Ohne diese Option skaliert CUPS Bilder, und zwar je nach
Distribution unterschiedlich (geprüft unter Debian 12, Ubuntu 22.04/24.04 und Fedora 44).

## Farbverwaltung: Wer rechnet ins Epson-Profil um?

Genau einer darf umrechnen, sonst stimmen die Farben nicht. Die Option heißt **Farbverwaltung**:

| Einstellung | wann |
|---|---|
| **Treiber** (Vorgabe) | Das Programm schickt normale sRGB-Farben: GIMP, Inkscape, LibreOffice, Bildbetrachter, `lp`. Der Treiber rechnet mit dem Epson-Profil um. |
| **Keine** | Das Programm hat schon ins Epson-Profil umgerechnet, z. B. Affinity mit dem Epson-Profil als Druckerprofil. |

Wo man sie wählt:
- **Für einen einzelnen Druck** im Druckdialog von GTK- und Qt-Programmen, bei den Druckeroptionen.
- **Als Vorgabe einer Warteschlange** an einer dieser Stellen:
  - in den Druckereinstellungen der Arbeitsumgebung (KDE: Systemeinstellungen → Drucker → Drucker
    einrichten → Papiereinstellungen → Farbverwaltung),
  - mit `sudo ./install.sh -c treiber|keine`,
  - im Menü von `sudo ./install.sh`,
  - in der CUPS-Weboberfläche unter `http://localhost:631`.
- **Programme unter Wine** (Affinity, Photoshop …) zeigen die Treiberoptionen nicht und nehmen immer die
  Vorgabe der Warteschlange. Für sie gibt es die zusätzliche Warteschlange `…-Programmfarbe` (Option `-a`).
  Ihre Vorgabe ist „Keine“, im Programm wählt man nur diesen Drucker. Siehe
  [docs/affinity-wine.de.md](docs/affinity-wine.de.md).

Eine eigene Einstellung eines Benutzers (`lpoptions -p WARTESCHLANGE -o ScfColor=…`, in `~/.cups/lpoptions`)
geht der Vorgabe der Warteschlange vor. Beim Umstellen über `install.sh` wird die des aufrufenden Benutzers
deshalb entfernt.

## Aktualisieren und entfernen

Aktualisieren: neue Version holen und `sudo ./install.sh` erneut starten. Vorhandene Warteschlangen behalten
Namen und Farbverwaltung.
Entfernen: `sudo ./install.sh -u`. Ein über die Paketverwaltung installiertes escpr2 bleibt bestehen.

## Fehlersuche

| Symptom | Ursache und Abhilfe |
|---|---|
| Druck übers Netz stockt, dauert 10 Minuten und mehr | Der Netzwerkteil des Druckers kann in einen Zustand geraten, in dem er langsam und mit doppelten Paketen antwortet (`ping` zeigt hohe Zeiten und `DUP!`). Drucker aus- und wieder einschalten. Ein Tassenauftrag dauert dann etwa 2,5 Minuten, wie unter Windows. |
| Ausdruck kommt als A4 / in falscher Größe | `epson-inkjet-printer-escpr2` älter als 1.2.24 (z. B. 1.2.9). `sudo ./install.sh` erneut starten, es installiert 1.2.43 daneben. |
| Motiv aus GIMP zu klein oder auf dem Kopf | In der Seiteneinrichtung **Hochformat** lassen, Bildauflösung auf 300 ppi stellen. |
| Farben zu dunkel oder verschoben | Prüfen, dass genau einer umrechnet (siehe oben). Affinity: Druckerprofil = Epson-Profil **und** Warteschlange `…-Programmfarbe`. |
| Warteschlange findet den Drucker nicht mehr | Der Drucker hat eine neue IP-Adresse. Im Router eine feste reservieren und `sudo ./install.sh -n NEUE_ADRESSE` starten. |
| `lpadmin` meldet, Druckertreiber seien veraltet | CUPS warnt bei jedem PPD-Treiber. Mit CUPS 2.x wird weiter gedruckt, der Installer blendet die Meldung aus. |

Protokolle: `journalctl -u cups` oder `/var/log/cups/error_log` (Zeilen mit `rastertoscf100`). Die
Statusmeldung der Warteschlange (`lpstat -p`) zeigt den Fehler des Filters in deiner Sprache. Bitte diese
Zeilen beilegen, wenn du ein Issue eröffnest.

Für die Netz-Warteschlange nicht `socket://` (Port 9100) nehmen, erprobt ist LPR.

## Wie es funktioniert

CUPS rechnet die Seite mit Ghostscript in ein RGB-Raster um. `rastertoscf100` dreht und spiegelt es,
rechnet die Farben mit dem Epson-Profil um (LittleCMS) und lässt es von Epsons `epson-escpr-wrapper2`
kodieren. Danach schreibt er den Auftrag so um, wie der Windows-Treiber ihn sendet:
- Medienkennung für Sublimation,
- Qualität,
- Farbtabelle im Drucker aus,
- fester Papierweg,
- Druckrichtung.

Einzelheiten (englisch): [docs/how-it-works.md](docs/how-it-works.md).

## Lizenz und Fremdbestandteile

- Dieses Projekt: **GPL-2.0-or-later** ([LICENSE](LICENSE)).
- **Epson escpr2** (`epson-inkjet-printer-escpr2`) lädt der Installer bei Epson. Die Hülle steht unter LGPL-2.1,
  die Bibliothek unter Epsons Lizenz. Sie ist nicht Teil dieses Projekts.
- **ICC-Profile** © Seiko Epson Corporation. Sie werden auf deinem Rechner aus Epsons offiziellem
  macOS-Treiber entnommen und nicht weitergegeben.

## Mitmachen

Fehlerberichte und Testberichte von anderen Distributionen sind willkommen, siehe die Issue-Vorlagen.
Weitere Modelle (z. B. SC-F500/SC-F501) werden noch nicht unterstützt. Ausgangspunkt wäre ein Mitschnitt
dessen, was der Windows-Treiber an den Drucker sendet. Entwickelt mit Unterstützung von Claude Code (Anthropic).
