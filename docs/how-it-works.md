# How it works

## Pipeline

```
application ──PDF/PS──▶ CUPS + Ghostscript ──RGB raster, 600 dpi──▶ rastertoscf100
   rastertoscf100: rotate · Epson ICC profile (LittleCMS) · mirror · pad to Windows page size
     ──CUPS raster v3──▶ epson-escpr-wrapper2 (Epson escpr2, unmodified)
     ──ESC/P-R──▶ rewrite like the Windows driver (lib/scf100/escpr.py) ──▶ usb:// or lpd://
```

The PPD declares `*cupsFilter2: "application/vnd.cups-raster application/vnd.epson.escpr 0 rastertoscf100"`,
so CUPS hands the filter an 8-bit RGB raster at 600 dpi of the printable area.

## Why Epson's escpr2 plus a rewrite

Epson's `escpr2` speaks the printer's language (ESC/P-R) and encodes the image bands with Epson's
compression. It does not know the SC-F100's sublimation media and applies the printer's colour table.
The output of the Windows driver was captured (printer port "FILE:", no ink used) and compared command by
command with the output of escpr2. The filter calls the unmodified wrapper and then changes only the
commands that differ. The image bands (`d-bsnd`) pass through unchanged.

| Command | escpr2 | Windows / this driver |
|---|---|---|
| remote preamble | escpr2 defaults | as Windows: `DP`, `SN`, `US`, `DR`, **`PP 01 01`** (fixed paper path), `HD 03 02` |
| `q-setq` media, quality | plain paper | **0xD2** DS Transfer Rigid / **0xD1** DS Transfer Textile; quality **2** High / **1** Standard |
| `m-setm` paper size | – | inserted after `q-seti`: 0x00 A4, 0x01 Letter, 0x02 Legal, **0x63** custom (mug) |
| `u-chku` | – | inserted after `q-seti` |
| `j-setj` paper size, direction | page as requested | printable area + 2 × margin; last byte **1** unidirectional (Windows default of the author) / 0 bidirectional |
| `p-setq` colour | printer LUT on | **LUT 4 (colour adjustment off)**, GammaCorrect 0xDC |

With the printer's colour adjustment off, the colours must already be in the printer's colour space. The
filter therefore converts sRGB to Epson's sublimation profile (perceptual by default, relative colorimetric
with black point compensation as option), exactly what the Windows driver does with "No colour adjustment"
plus an application that uses the profile.

## Margins: the "virtual page"

The SC-F100 prints with 70 dots (8.4 pt at 600 dpi) of margin, like the Windows and macOS drivers. On custom
paper sizes Epson's library subtracts 210 dots on the right and bottom edges instead of 70. The filter
therefore calls escpr2 with a page enlarged by 280 dots and afterwards writes the real paper size into
`j-setj`. The result is identical to the Windows job (mug: `j-setj` 2362 × 5668).

escpr2 **before 1.2.24** (e.g. 1.2.9) ignores the custom size and produces an A4 page. The installer and the
filter read the version from the wrapper binary and refuse older ones. 1.2.24 and 1.2.43 produce identical jobs.

## Orientation

The mug size is defined as a **landscape** page (240 × 100 mm, `100x240mmRotated`), so applications send the
design unrotated. The filter rotates landscape pages 90° clockwise into the feed direction, as Windows does.

If the mug size arrives in portrait, the application has rotated the design itself (CUPS convention:
counter-clockwise, e.g. GIMP or Okular set to "landscape"). The filter then rotates by a further 180°.

## Mirroring

The printer outputs the raster mirrored by itself (the macOS driver calls this `InverseMirrorImage`).
"Mirror on" therefore leaves the raster unchanged; "off" mirrors it beforehand.

## Verification

- **Commands:** jobs for the mug and A4 match the Windows captures command by command, apart from the timestamp.
- **Colours:** 108 of 147 compressed bands of the test chart are byte-identical between Windows/Affinity and
  this driver; cross-checks without conversion or with another intent match 0 bands. Affinity under Wine
  sends flat colour areas identical to the driver's own conversion (maximum deviation 0).
- **Mugs:** pressed from a Windows and a Linux print in one session with the same press settings: identical.

## Decisions and alternatives not taken

- **Driverless / IPP:** the printer's IPP service accepts only JPEG and raw data, without sublimation media
  or profile settings; it is no basis for sublimation printing.
- **Gutenprint:** has no SC-F model, and its ESC/P2 path would need its own colour profile (measuring
  equipment and pressed test charts) instead of Epson's.
- **Shipping Epson files:** not allowed. escpr2 and the ICC profiles are downloaded from Epson on the
  user's computer, with fixed checksums.
- **Own ESC/P-R encoder instead of escpr2:** possible later (the band compression is the only unknown); not
  needed as long as escpr2 is available.
- **PPD drivers are deprecated in CUPS:** they keep working with CUPS 2.x. A future step could wrap the
  driver as a Printer Application (e.g. with `pappl-retrofit`) without changing the filter.

## Files

| Path (installed) | Content |
|---|---|
| `/usr/lib/cups/filter/rastertoscf100` | CUPS filter (Python) |
| `/usr/lib/scf100-sublimation/scf100/` | raster reader, ESC/P-R rewrite |
| `/usr/lib/scf100-sublimation/wrapper` | path of the chosen escpr2 wrapper |
| `/usr/share/ppd/scf100-sublimation/epson-scf100-sublimation.ppd` | PPD |
| `/usr/share/scf100-sublimation/profiles/{rigid,textile}.icc` | Epson ICC profiles (fetched) |
| `/usr/bin/scf100-fetch-icc` | fetches the profiles again |
| `/var/lib/scf100-sublimation/` | installed version, marker for an escpr2 unpacked to `/opt` |

Environment variables for testing the filter without CUPS: `SCF100_LIB`, `SCF100_WRAPPER`,
`SCF100_PROFILE_DIR`, `SCF100_PREVIEW` (saves each page as it goes to escpr2), `PPD`, `LANG`.
