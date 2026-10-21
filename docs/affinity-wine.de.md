# Affinity und andere Windows-Programme unter Wine

[English](affinity-wine.md)

Windows-Programme unter Wine drucken über CUPS wie jedes Linux-Programm. Zwei Dinge sind anders:

- Ihr Druckdialog zeigt die **Treiberoptionen nicht** (Medium, Farbverwaltung …). Sie nehmen immer die
  Vorgaben der Warteschlange.
- Programme wie Affinity oder Photoshop lassen dich wählen, ob das Programm oder der Drucker die Farben
  verwaltet. Unter Windows ist die Farbverwaltung durch das Programm mit dem Epson-Profil oft der
  zuverlässigere Weg zu richtigen Farben. Wählst du sie, rechnet das Programm ins Epson-Profil um, und der
  Treiber darf nicht ein zweites Mal umrechnen. Diese Anleitung bringt genau diesen Weg nach Linux.

Geprüft mit Affinity 3.3 (AppImage von ryzendew, Wine 11) unter Manjaro:
- Die Farbwerte, die beim Treiber ankommen, gleichen einer LittleCMS-Umrechnung sRGB → Epson Rigid,
  wahrnehmungsorientiert. Beim Testbild waren 759 264 von 759 264 Pixeln gleich, die größte Abweichung war 0.
- Sie gleichen auch denen von Affinity unter Windows.

## 1. Warteschlange ohne Farbumrechnung

```sh
sudo ./install.sh -a          # oder im geführten Ablauf mit „Ja“ antworten
```

Das legt `SC-F100-…-Programmfarbe` an (englisch `…-AppColor`), mit Farbverwaltung „Keine“. Diesen Drucker im
Windows-Programm wählen. Für alle anderen Programme weiter die normale Warteschlange nehmen.

## 2. Epson-Profil im Wine-Präfix

Die Profile liegen unter `/usr/share/scf100-sublimation/profiles/rigid.icc` und `textile.icc`.

- ⚠ Wine listet Farbprofile nur mit der Endung **`.icm`**. `EnumColorProfilesW` sucht nach `*icm`, Windows
  nimmt beide. Deshalb mit neuer Endung kopieren:
  ```sh
  C="$WINEPREFIX/drive_c/windows/system32/spool/drivers/color"
  cp /usr/share/scf100-sublimation/profiles/rigid.icc   "$C/Epson_SC-F100_Rigid.icm"
  cp /usr/share/scf100-sublimation/profiles/textile.icc "$C/Epson_SC-F100_Textile.icm"
  ```
- Affinity bot das Profil auch dann nicht an. **Der Import in Affinity** hat funktioniert: Einstellungen →
  Farbe → ICC-Profil importieren. Affinity legt es in seinem eigenen Ordner ab
  (`AppData\Roaming\Affinity\Affinity\3.0\profiles`).

## 3. Drucken aus Affinity

1. Datei → Drucken, Drucker `…-Programmfarbe`, Papierformat **Tasse (240 × 100 mm)**.
2. Farbverwaltung: Druckerprofil **Epson SC-F100 … (Rigid)** (oder Textile), Renderpriorität
   **Wahrnehmungsorientiert / Perzeptiv**.
3. Drucken. Der Treiber gibt die Farben unverändert weiter, gespiegelt und mit den Medieneinstellungen für
   Sublimation.

## Affinity-AppImage: bekannte Probleme und Abhilfe

Diese Punkte betreffen das Affinity-AppImage, nicht diesen Treiber. Vor jeder Änderung Affinity ganz beenden.
Dazu gehört auch `wineserver -k` mit dem Wine des AppImages, oder einmal abmelden.
Das Präfix des AppImages ist `~/.affinity-appimage-wineprefix`.

| Symptom | Ursache | Abhilfe |
|---|---|---|
| Affinity startet nicht, keine Meldung (Journal: `System.UriFormatException: Invalid URI` in `FontCache`) | Das AppImage kopiert sein Präfix ohne Laufwerk `z:` | `ln -s / ~/.affinity-appimage-wineprefix/dosdevices/z:` |
| Alles viel zu groß | Ohne `zenity` scheitert der DPI-Dialog still, es bleiben 144 DPI aus dem mitgelieferten Präfix | `echo 96 > ~/.affinity-appimage-dpi.conf` und `echo dont_show > ~/.affinity-appimage-dpi-preference.conf` |
| Fenster reagiert gar nicht, Willkommensfenster unsichtbar | Renderer `vulkan` ohne funktionierenden Vulkan-Treiber | In `user.reg` des Präfixes `"renderer"="vulkan"` in `"renderer"="gl"` ändern |
| Druckdialog meldet „Keine Drucker installiert“ | Das Präfix wurde vom Benutzer `matt` gebaut. `TEMP` zeigt noch auf `C:\users\matt\…`, und Wines `winspool` bricht ab, bevor es Drucker einträgt | `ln -s "$USER" ~/.affinity-appimage-wineprefix/drive_c/users/matt` (gibt es `drive_c/users/$USER` noch nicht, zuerst anlegen) |

Nach der Drucker-Abhilfe liest Wine die Druckerliste erst beim Start eines neuen `wineserver`. Affinity also
ganz beenden und neu starten. Auch neue Warteschlangen erscheinen erst nach so einem Neustart.

Wine listet keine CUPS-**Instanzen** (`lpoptions -p WARTESCHLANGE/INSTANZ`), nur echte Warteschlangen. Deshalb
ist die Variante ohne Farbumrechnung eine eigene Warteschlange.
