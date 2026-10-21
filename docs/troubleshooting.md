# Troubleshooting

[Deutsch](troubleshooting.de.md) · [README](../README.md)

| Symptom | Cause and fix |
|---|---|
| Printing over the network stalls, takes 10 minutes or more | The printer's network interface can get into a state where it answers slowly and with duplicate packets (`ping` shows high times and `DUP!`). Switch the printer off and on. A normal mug job then takes about 2.5 minutes, as on Windows. |
| Print comes out as A4 / wrong size | `epson-inkjet-printer-escpr2` older than 1.2.24 (e.g. 1.2.9). Run `sudo ./install.sh` again; it installs 1.2.43 next to it. |
| Design too small or upside down from GIMP | In the page setup leave **portrait**; set the image resolution to 300 ppi. |
| Colours too dark or shifted | Check that exactly one party converts colours (see [Colour management](../README.md#colour-management-who-converts-to-the-epson-profile)). Affinity: printer profile = Epson profile **and** queue `…-AppColor`. |
| Image printed with `lp` has the wrong size | CUPS scales images. For an image at mug size use `lp -d QUEUE -o print-scaling=none design.png`. |
| Queue does not find the printer any more | The printer got a new IP address. Reserve a fixed one in the router and run `sudo ./install.sh -n NEW_ADDRESS`. |
| `lpadmin` says printer drivers are deprecated | CUPS warns about every PPD-based driver. Printing keeps working with CUPS 2.x; the installer hides the message. |

Logs: `journalctl -u cups` or `/var/log/cups/error_log` (lines with `rastertoscf100`). The status message
of the queue (`lpstat -p`) shows the filter's error in your language. Please attach these lines when you
open an issue.

Do not use `socket://` (port 9100) for the network queue; LPR is what has been verified.
