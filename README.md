# epson-scf100-linux

**Linux printer driver for the Epson SureColor SC-F100 dye sublimation printer.**
Print mugs, textiles and hard goods from any Linux application, with Epson's official ICC profiles,
exactly like the Windows driver.

[Deutsch](README.de.md) · [Changelog](CHANGELOG.md) · [How it works](docs/how-it-works.md) ·
[Affinity and other Windows applications under Wine](docs/affinity-wine.md)

> Not made by, endorsed by or affiliated with Seiko Epson Corporation. "Epson" and "SureColor" are
> trademarks of Seiko Epson Corporation and are used here only to name the supported printer.

## Why

Epson offers no Linux driver for the SC-F100 in sublimation mode. The generic `escpr2` driver can talk
to the printer, but it uses the wrong media settings and applies the printer's own colour table, so
sublimation prints come out with wrong colours. This driver sends the same print jobs as the Windows
driver, converts colours with Epson's official sublimation ICC profiles, and mirrors the image.

**Result:** The colour values sent to the printer are identical to those of the Windows driver (compared
byte by byte), and mugs pressed from Linux and from Windows prints look the same.

## Features

- Works like any other printer: print from GIMP, Inkscape, LibreOffice, Krita, image viewers, `lp`.
- Options in the print dialog: media (DS Transfer **Rigid** for mugs and hard goods, **Textile** for
  fabrics), quality (High/Standard), mirroring, colour management, rendering intent, print direction.
- Paper sizes: **mug 240 × 100 mm**, A4, Letter, Legal and custom sizes up to 216 × 1200 mm.
- USB and network (LPR) connection, automatic discovery of the printer on the network.
- Guided installation in German or English (chosen from your locale).
- Nothing from Epson is redistributed: the installer downloads Epson's `escpr2` and the ICC profiles
  directly from Epson and verifies their checksums.

## Requirements

- Linux on **x86_64** with CUPS 2.x. Other architectures need `epson-inkjet-printer-escpr2` ≥ 1.2.24
  built from source.
- Python 3 with Pillow (including LittleCMS, as in all distribution packages).
- 7-Zip and bsdtar to unpack the profiles. The installer offers to install missing packages on
  Arch/Manjaro, Debian/Ubuntu, Fedora and openSUSE.
- Internet access during installation (Epson downloads, about 75 MB).

## Installation

```sh
git clone https://github.com/genau-der-84/epson-scf100-linux.git
cd epson-scf100-linux
sudo ./install.sh
```

Or download a release archive, unpack it, and run `sudo ./install.sh` in the unpacked folder.

Without options the installer asks in dialog windows: how the printer is connected (USB, network or
both), which of the printers found on the network to use, the default media and quality, and whether
you want an additional queue for applications under Wine. Without `whiptail`/`dialog` it asks the
same questions as plain text.

Non-interactive:

| Option | Meaning |
|---|---|
| `-n`, `--network ADDRESS\|auto` | network queue (LPR); `auto` searches the network |
| `-s`, `--search` | only list SC-F100 printers found on the network |
| `-m`, `--media rigid\|textile` | default media (default: rigid) |
| `-q`, `--quality high\|standard` | default quality (default: high) |
| `-a`, `--app-color` | additional queue `…-AppColor` without colour conversion (see below) |
| `-c`, `--color driver\|none` | switch the colour management of existing queues, nothing else |
| `-o`, `--driver-only` | driver only, no print queue |
| `-d`, `--dmg FILE` | take the ICC profiles from an already downloaded Epson macOS driver |
| `-u`, `--uninstall` | remove everything |
| `-y`, `--yes` | no questions |
| `-t`, `--text` / `-g`, `--dialog` | plain text questions / dialog windows |
| `-l`, `--lang de\|en` | language (default: from the locale) |
| `-V`, `--version`, `-h`, `--help` | version, help |

Examples: `sudo ./install.sh -n auto -y` · `sudo ./install.sh -n 192.168.1.50 -m textile` ·
`sudo ./install.sh -u`. German option names work as well (`--netz`, `--medium`, `--farbe` …).

Print queues: `SC-F100-USB`, `SC-F100-Network` (German locale: `SC-F100-Netz`), optionally
`…-AppColor` (`…-Programmfarbe`).

**Give the printer a fixed IP address** in your router (DHCP reservation). The network queue is bound
to the address.

## Printing

1. Choose the printer `SC-F100-…` and the paper size **Mug (240 × 100 mm)** (or A4 etc.).
2. Leave the application set to **portrait**. The mug size is a landscape page; the driver rotates it
   into the feed direction like the Windows driver.
3. Print at the size of your design (e.g. in GIMP: image resolution 300 ppi, "ignore page margins").
   Mirroring is on by default, as needed for sublimation transfer.

From the command line: `lp -d SC-F100-Network design.pdf`. For an image designed at mug size
(240 × 100 mm, e.g. 2835 × 1181 px at 300 ppi) add `-o print-scaling=none`:
`lp -d SC-F100-Network -o print-scaling=none design.png`. Without it CUPS scales images, and the result
differs between distributions (checked on Debian 12, Ubuntu 22.04/24.04, Fedora 44).

## Colour management: who converts to the Epson profile?

Exactly one party may convert, otherwise the colours are wrong. The option is called **Color Management**:

| Setting | When |
|---|---|
| **Driver** (default) | The application sends normal sRGB colours: GIMP, Inkscape, LibreOffice, image viewers, `lp`. The driver converts with the Epson profile. |
| **None** | The application has already converted to the Epson profile, e.g. Affinity with the Epson profile selected as printer profile. |

Where to choose it:
- **For a single print** in the print dialog of GTK and Qt applications, among the printer options.
- **As the default of a queue** in your desktop's printer settings (KDE: System Settings → Printers →
  configure the printer → page with the printer options → Color Management), with `sudo ./install.sh -c driver|none`, in the menu of
  `sudo ./install.sh`, or in the CUPS web interface at `http://localhost:631`.
- **Applications under Wine** (Affinity, Photoshop …) do not show the driver options and always use the
  queue default. Use the additional queue `…-AppColor` (option `-a`) for them: its default is "None",
  so you only pick that printer in the application. See [docs/affinity-wine.md](docs/affinity-wine.md).

A user's own setting (`lpoptions -p QUEUE -o ScfColor=…`, stored in `~/.cups/lpoptions`) overrides the
queue default. Switching via `install.sh` therefore removes the calling user's own setting.

## Updating and uninstalling

Update: get the new version and run `sudo ./install.sh` again. Existing queues keep their name and their
colour management setting.
Uninstall: `sudo ./install.sh -u`. An escpr2 installed through the package manager stays installed.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Printing over the network stalls, takes 10 minutes or more | The printer's network interface can get into a state where it answers slowly and with duplicate packets (`ping` shows high times and `DUP!`). Switch the printer off and on. A normal mug job then takes about 2.5 minutes, as on Windows. |
| Print comes out as A4 / wrong size | `epson-inkjet-printer-escpr2` older than 1.2.24 (e.g. 1.2.9). Run `sudo ./install.sh` again; it installs 1.2.43 next to it. |
| Design too small or upside down from GIMP | In the page setup leave **portrait**; set the image resolution to 300 ppi. |
| Colours too dark or shifted | Check that exactly one party converts colours (see above). Affinity: printer profile = Epson profile **and** queue `…-AppColor`. |
| Queue does not find the printer any more | The printer got a new IP address. Reserve a fixed one in the router and run `sudo ./install.sh -n NEW_ADDRESS`. |
| `lpadmin` says printer drivers are deprecated | CUPS warns about every PPD-based driver. Printing keeps working with CUPS 2.x; the installer hides the message. |

Logs: `journalctl -u cups` or `/var/log/cups/error_log` (lines with `rastertoscf100`). The status message
of the queue (`lpstat -p`) shows the filter's error in your language. Please attach these lines when you
open an issue.

Do not use `socket://` (port 9100) for the network queue; LPR is what has been verified.

## How it works

CUPS renders the page with Ghostscript to an RGB raster. `rastertoscf100` rotates and mirrors it, converts
the colours with the Epson profile (LittleCMS), and lets Epson's `epson-escpr-wrapper2` encode it. It then
rewrites the job the way the Windows driver sends it: sublimation media ID, quality, colour table in the
printer off, fixed paper path, print direction. Details: [docs/how-it-works.md](docs/how-it-works.md).

## Licence and third-party components

- This project: **GPL-2.0-or-later** ([LICENSE](LICENSE)).
- **Epson escpr2** (`epson-inkjet-printer-escpr2`) is downloaded from Epson by the installer. Its wrapper is
  LGPL-2.1, the library is under Epson's licence. It is not part of this project.
- **ICC profiles** © Seiko Epson Corporation. They are extracted from Epson's official macOS driver on your
  computer and are not redistributed.

## Contributing

Bug reports and test reports from other distributions are welcome, see the issue templates. Other models
(e.g. SC-F500/SC-F501) are not supported yet; a byte-level capture of the Windows driver's output would be
the starting point. The project was developed with the help of Claude Code (Anthropic).
