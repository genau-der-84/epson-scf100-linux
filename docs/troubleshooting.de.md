# Fehlersuche

[English](troubleshooting.md) · [README](../README.de.md)

| Symptom | Ursache und Abhilfe |
|---|---|
| Druck übers Netz stockt, dauert 10 Minuten und mehr | Der Netzwerkteil des Druckers kann in einen Zustand geraten, in dem er langsam und mit doppelten Paketen antwortet (`ping` zeigt hohe Zeiten und `DUP!`). Drucker aus- und wieder einschalten. Ein Tassenauftrag dauert dann etwa 2,5 Minuten, wie unter Windows. |
| Ausdruck kommt als A4 / in falscher Größe | `epson-inkjet-printer-escpr2` älter als 1.2.24 (z. B. 1.2.9). `sudo ./install.sh` erneut starten, es installiert 1.2.43 daneben. |
| Motiv aus GIMP zu klein oder auf dem Kopf | In der Seiteneinrichtung **Hochformat** lassen, Bildauflösung auf 300 ppi stellen. |
| Farben zu dunkel oder verschoben | Prüfen, dass genau einer umrechnet (siehe [Farbverwaltung](../README.de.md#farbverwaltung-wer-rechnet-ins-epson-profil-um)). Affinity: Druckerprofil = Epson-Profil **und** Warteschlange `…-Programmfarbe`. |
| Bild per `lp` in falscher Größe | CUPS skaliert Bilder. Für ein Bild in Tassengröße `lp -d WARTESCHLANGE -o print-scaling=none motiv.png` nehmen. |
| Warteschlange findet den Drucker nicht mehr | Der Drucker hat eine neue IP-Adresse. Im Router eine feste reservieren und `sudo ./install.sh -n NEUE_ADRESSE` starten. |
| `lpadmin` meldet, Druckertreiber seien veraltet | CUPS warnt bei jedem PPD-Treiber. Mit CUPS 2.x wird weiter gedruckt, der Installer blendet die Meldung aus. |

Protokolle: `journalctl -u cups` oder `/var/log/cups/error_log` (Zeilen mit `rastertoscf100`). Die
Statusmeldung der Warteschlange (`lpstat -p`) zeigt den Fehler des Filters in deiner Sprache. Bitte diese
Zeilen beilegen, wenn du ein Issue eröffnest.

Für die Netz-Warteschlange nicht `socket://` (Port 9100) nehmen, erprobt ist LPR.
