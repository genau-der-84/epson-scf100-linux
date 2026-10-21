# Affinity and other Windows applications under Wine

[Deutsch](affinity-wine.de.md)

Windows applications running under Wine print through CUPS like any Linux program. Two things are different:

- Their print dialog does **not show the driver options** (media, colour management …). They always use the
  defaults of the print queue.
- Applications like Affinity or Photoshop let you choose whether the application or the printer manages
  colours. On Windows, colour management by the application with the Epson profile is often the more
  reliable way to get correct colours. If you choose it, the application converts to the Epson profile and
  the driver must not convert a second time. This guide brings that workflow to Linux.

Verified with Affinity 3.3 (AppImage by ryzendew, Wine 11) on Manjaro: the colour values that arrive at the
driver are identical to those of a LittleCMS conversion sRGB → Epson Rigid, perceptual (759,264 of 759,264
pixels of the test chart, maximum deviation 0), and identical to Affinity on Windows.

## 1. Print queue without colour conversion

```sh
sudo ./install.sh -a          # or answer "Yes" in the guided setup
```

This creates `SC-F100-…-AppColor` (German: `…-Programmfarbe`) with colour management "None". Choose this
printer in the Windows application. For all other programs keep using the normal queue.

## 2. Epson profile in the Wine prefix

The profiles are at `/usr/share/scf100-sublimation/profiles/rigid.icc` and `textile.icc`.

- ⚠ Wine lists colour profiles only with the extension **`.icm`** (`EnumColorProfilesW` searches for `*icm`),
  Windows accepts both. Copy them with the new extension:
  ```sh
  C="$WINEPREFIX/drive_c/windows/system32/spool/drivers/color"
  cp /usr/share/scf100-sublimation/profiles/rigid.icc   "$C/Epson_SC-F100_Rigid.icm"
  cp /usr/share/scf100-sublimation/profiles/textile.icc "$C/Epson_SC-F100_Textile.icm"
  ```
- Affinity did not offer the profile even then. **Importing it in Affinity** worked:
  in Affinity 3 **File → Import ICC Profile** (German UI: Datei → ICC-Profil importieren). Affinity stores it in its own folder
  (`AppData\Roaming\Affinity\Affinity\3.0\profiles`).

## 3. Printing from Affinity

1. File → Print, printer `…-AppColor`, paper size **Mug (240 × 100 mm)**.
2. Colour management: printer profile **Epson SC-F100 … (Rigid)** (or Textile), rendering intent
   **Perceptual**.
3. Print. The driver sends the colours unchanged, mirrored, with the sublimation media settings.

## Affinity AppImage: known problems and fixes

These concern the Affinity AppImage, not this driver. Close Affinity completely before changing anything
(also `wineserver -k` with the AppImage's Wine, or log out).
The prefix of the AppImage is `~/.affinity-appimage-wineprefix`.

| Symptom | Cause | Fix |
|---|---|---|
| Affinity does not start, no message (journal: `System.UriFormatException: Invalid URI` in `FontCache`) | The AppImage copies its prefix without drive `z:` | `ln -s / ~/.affinity-appimage-wineprefix/dosdevices/z:` |
| Everything far too large | Without `zenity` the DPI dialog fails silently and 144 DPI from the bundled prefix remain | `echo 96 > ~/.affinity-appimage-dpi.conf` and `echo dont_show > ~/.affinity-appimage-dpi-preference.conf` |
| Window does not react at all, welcome screen invisible | Renderer `vulkan` without a working Vulkan driver | In `user.reg` of the prefix change `"renderer"="vulkan"` to `"renderer"="gl"` |
| Print dialog says "No printers installed" | The prefix was built by user `matt`; `TEMP` still points to `C:\users\matt\…`, and Wine's `winspool` aborts before listing printers | `ln -s "$USER" ~/.affinity-appimage-wineprefix/drive_c/users/matt` (if `drive_c/users/$USER` does not exist yet, create it first) |

After the printer fix, Wine reads the printer list only when a new `wineserver` starts: close Affinity
completely and start it again. New print queues also appear only after such a restart.

Wine does not list CUPS **instances** (`lpoptions -p QUEUE/INSTANCE`), only real queues. That is why the
variant without colour conversion is a separate queue.
