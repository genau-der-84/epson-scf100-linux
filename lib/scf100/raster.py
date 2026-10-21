# SPDX-License-Identifier: GPL-2.0-or-later
"""Read and write CUPS raster (versions 1, 2 and 3, both byte orders) without libcups.

Only what the SC-F100 filter needs: 8 bits per colour, RGB/sRGB, chunky colour order.
Format: "CUPS Raster Format" (https://www.cups.org/doc/spec-raster.html).
"""
import struct

SYNC = {b"RaSt": (">", 1), b"tSaR": ("<", 1), b"RaS2": (">", 2), b"2SaR": ("<", 2),
        b"RaS3": (">", 3), b"3SaR": ("<", 3)}

# Names of the 32-bit values starting at byte 256 of the page header, in file order
_FIELDS = ("AdvanceDistance AdvanceMedia Collate CutMedia Duplex HWResolutionX HWResolutionY "
           "BBoxL BBoxB BBoxR BBoxT InsertSheet Jog LeadingEdge MarginL MarginB ManualFeed "
           "MediaPosition MediaWeight MirrorPrint NegativePrint NumCopies Orientation OutputFaceUp "
           "PageWidth PageHeight Separations TraySwitch Tumble cupsWidth cupsHeight cupsMediaType "
           "cupsBitsPerColor cupsBitsPerPixel cupsBytesPerLine cupsColorOrder cupsColorSpace "
           "cupsCompression cupsRowCount cupsRowFeed cupsRowStep").split()
HEADER_V1, HEADER_V23 = 420, 1796


class RasterError(Exception):
    pass


def _exactly(f, n):
    d = f.read(n)
    if len(d) != n:
        raise RasterError(f"raster ends early ({len(d)} of {n} bytes)")
    return d


def pages(f):
    """Yield (header: dict, data: bytes) per page; data are the uncompressed lines."""
    sync = f.read(4)
    if sync not in SYNC:
        raise RasterError(f"not a CUPS raster (sync word {sync!r})")
    end, version = SYNC[sync]
    size = HEADER_V1 if version == 1 else HEADER_V23
    while True:
        raw = f.read(size)
        if not raw:
            return
        if len(raw) != size:
            raise RasterError("incomplete page header")
        values = struct.unpack(end + "%dI" % len(_FIELDS), raw[256:256 + 4 * len(_FIELDS)])
        h = dict(zip(_FIELDS, values))
        h["MediaType"] = raw[128:192].split(b"\0")[0].decode(errors="replace")
        if version != 1:
            h["cupsNumColors"] = struct.unpack(end + "I", raw[420:424])[0]
            h["PageWidthF"], h["PageHeightF"] = struct.unpack(end + "2f", raw[428:436])  # cupsPageSize
            h["cupsPageSizeName"] = raw[1732:1796].split(b"\0")[0].decode(errors="replace")
        bpl, height = h["cupsBytesPerLine"], h["cupsHeight"]
        if version == 2:
            data = _read_v2(f, bpl, height, h["cupsBitsPerPixel"] // 8 or 1)
        else:
            data = _exactly(f, bpl * height)
        yield h, data


def _read_v2(f, bpl, height, bpp):
    """Version 2: one repeat byte per line group, then pixel runs (repeat/literal)."""
    out = bytearray()
    lines = 0
    while lines < height:
        repeat = _exactly(f, 1)[0] + 1
        line = bytearray()
        while len(line) < bpl:
            n = _exactly(f, 1)[0]
            if n & 0x80:                       # 257-n literal pixels follow
                line += _exactly(f, (257 - n) * bpp)
            else:                              # next pixel n+1 times
                line += _exactly(f, bpp) * (n + 1)
        if len(line) != bpl:
            raise RasterError("line longer than cupsBytesPerLine")
        repeat = min(repeat, height - lines)
        out += bytes(line) * repeat
        lines += repeat
    return bytes(out)


def header_v3(width, height, dpi, page_pt, name=""):
    """CUPS raster v3 page header (little endian, write the sync word 3SaR first), 8-bit RGB."""
    s = lambda t: t.encode().ljust(64, b"\0")  # noqa: E731
    u = [0, 0, 0, 0, 0, dpi, dpi, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 1, 0, 0,                         # NumCopies = 1
         round(page_pt[0]), round(page_pt[1]), 0, 0, 0,
         width, height, 0, 8, 24, width * 3, 0, 1, 0, 0, 0, 0, 3]
    h = s("") * 4 + struct.pack("<%dI" % len(u), *u)
    h += struct.pack("<7f", 1.0, page_pt[0], page_pt[1], 0, 0, page_pt[0], page_pt[1])
    h += b"\0" * (16 * 4 + 16 * 4 + 16 * 64) + s("") + s("") + s(name)
    assert len(h) == HEADER_V23, len(h)
    return h
