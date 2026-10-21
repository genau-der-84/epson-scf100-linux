# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-10-21

### Fixed
- Network printer search without avahi-daemon (e.g. Manjaro, where it is disabled by default): the SNMP fallback
  looked for the model name in the short `lpinfo -v` listing, which only has class and URI, and never found the printer.
  The long listing it uses now is translated by CUPS, so it and the other parsed CUPS outputs run with `LC_ALL=C`.
- The installer no longer confirms package manager transactions by itself unless it was started with `-y`.
  A transaction can do more than install the requested package (on Fedora, dnf removed old kernels because of
  `installonly_limit` while installing bsdtar); the user now sees the package manager's summary and decides.
- openSUSE: `--no-gpg-checks` only for Epson's unsigned escpr2 rpm (checksum verified), not for repository packages.

### Changed
- In text mode the installer says why there are no dialog windows (whiptail missing, e.g. on Fedora Workstation).
- Clearer description in the installer's main menu: what the driver does instead of "a regular printer for dye sublimation".

## [0.1.0] - 2026-10-21

First public release.

### Added
- CUPS driver for the Epson SureColor SC-F100 dye sublimation printer: filter `rastertoscf100` and PPD.
  Print jobs match the Windows driver command by command (media, quality, print direction, paper size,
  colour table in the printer off).
- Colour management with Epson's official ICC profiles (Rigid, Textile), perceptual or relative colorimetric.
  Option "None" for applications whose own colour management converts with the Epson profile (e.g. Affinity,
  Photoshop), the workflow that is often the more reliable one on Windows.
- Paper sizes: mug (240 x 100 mm, landscape), A4, Letter, Legal and custom sizes up to 216 x 1200 mm.
- Mirroring on/off, unidirectional/bidirectional printing, quality High/Standard.
- `install.sh`: guided setup (whiptail/dialog or plain text) in German or English depending on the locale,
  network discovery via mDNS/SNMP, USB and network (LPR) queues, optional queue without colour conversion
  for applications under Wine (`-a`), switching colour management of existing queues (`-c`, menu).
- Epson's escpr2 is installed from Epson's official download (fixed checksum, at least version 1.2.24).
- `scf100-fetch-icc`: fetches the ICC profiles from Epson's official macOS driver (fixed checksums).
- German translations of all printer options.

### Verified
- Manjaro (CUPS 2.4.14): installation, printing via USB and network, GIMP, Inkscape, LibreOffice,
  Okular, Affinity 3 under Wine.
- Debian 12, Ubuntu 22.04, Ubuntu 24.04, Fedora 44 (fresh containers, CUPS only): installation including
  Epson downloads, print jobs to a test receiver (mug PDF: same paper size and commands on all four), switching colour
  management, reinstall keeps settings, uninstall.
- Colour values sent to the printer are identical to those of the Windows driver; pressed mugs from
  Linux and Windows are indistinguishable.

### Notes
- Epson's escpr2 .deb does not declare its dependency on libcupsimage; the installer installs
  `libcupsimage2` / `libcupsimage2t64` when the wrapper needs it.
- The PPD maps IPP `print-quality` explicitly (`*APPrinterPreset`). Without this, Ubuntu's CUPS guessed a
  mapping and printed with quality "Standard" instead of the default "High".

[Unreleased]: https://github.com/genau-der-84/epson-scf100-linux/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/genau-der-84/epson-scf100-linux/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/genau-der-84/epson-scf100-linux/releases/tag/v0.1.0
