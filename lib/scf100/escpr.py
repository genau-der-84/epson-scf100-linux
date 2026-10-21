# SPDX-License-Identifier: GPL-2.0-or-later
"""Rewrite an ESC/P-R job from Epson's escpr2 the way the Windows driver sends it for the SC-F100.

Module of the CUPS filter rastertoscf100; also usable as a pipe filter (stdin -> stdout).

Reads an ESC/P-R job produced by epson-escpr-wrapper2 and rewrites it like the Windows driver
does with "No colour adjustment" (byte-level captures of the Windows driver, see docs/how-it-works.md):

  - Preamble (remote commands) as on Windows: DP/SN/US/DR/PP instead of the escpr2 values,
    in particular PP 01 01 (fixed paper path) and HD 03 02.
  - q-setq: media ID (0xD2 Rigid, 0xD1 Textile) and quality (2 High, 1 Standard).
  - after q-seti: insert m-setm (paper size ID) and u-chku.
  - j-setj: paper size = printable area + 2 x margin. escpr2 is called with a larger "virtual"
    page because Epson's library leaves 210 dots of right/bottom margin on custom sizes;
    the SC-F100 only needs 70. Print direction as selected.
  - after p-sttp: p-setq with LUT=4 (colour adjustment in the printer OFF), GammaCorrect 0xDC.
    The colours therefore have to be converted to the Epson profile BEFOREHAND.

The raster data (d-bsnd) are passed through unchanged.

Environment (pipe mode): SCF100_MEDIA (default 0xD2), SCF100_DIRECTION (default 1).
"""
import os
import re
import sys
import time

ESCPR_START = b"\x1b(R\x06\x00\x00ESCPR"

# Oldest escpr2 version verified to work. 1.2.9 (AUR) ignores the custom paper size and produces
# an A4 page (j-setj 4960 x 7014 instead of 2362 x 5668). 1.2.24 and 1.2.43 are byte-identical and correct.
ESCPR2_MIN = (1, 2, 24)


def wrapper_version(path):
    """Version of epson-escpr-wrapper2 read from the binary (it contains exactly one, e.g. "1.2.43")."""
    try:
        with open(path, "rb") as f:
            found = set(re.findall(rb"(?<![\d.])1\.\d+\.\d+(?![\d.])", f.read()))
    except OSError:
        return None
    if len(found) != 1:
        return None
    return tuple(int(x) for x in found.pop().split(b"."))


def command(cls: bytes, name: bytes, params: bytes) -> bytes:
    return b"\x1b" + cls + len(params).to_bytes(4, "little") + name + params


def remote(*cmds: bytes) -> bytes:
    """Remote command block: ESC @ ESC @ ESC ( R ... REMOTE1 <cmds> ESC 00 00 00"""
    return (b"\x1b\x01@EJL 1284.4\n@EJL     \n\x1b@\x1b@\x1b(R\x08\x00\x00REMOTE1"
            + b"".join(cmds) + b"\x1b\x00\x00\x00")


def rcmd(name: bytes, payload: bytes) -> bytes:
    return name + len(payload).to_bytes(2, "little") + payload


def timestamp() -> bytes:
    t = time.localtime()
    return b"\x00" + t.tm_year.to_bytes(2, "big") + bytes([t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec])


def preamble() -> bytes:
    ti = rcmd(b"TI", timestamp())
    part1 = (b"\x00\x00\x00" + remote(ti, rcmd(b"JS", b"\x00" * 4),
                                      rcmd(b"JH", bytes.fromhex("000171e5e7930a002700000a")),
                                      rcmd(b"HD", bytes.fromhex("000302"))))
    # Two ESC ( d with 32767 zero bytes each, like the Windows driver
    filler = (b"\x1b(d\xff\x7f" + b"\x00" * 32767) * 2 + b"\x00\x00\x00"
    part2 = remote(ti, rcmd(b"DP", b"\x00\x00"), rcmd(b"SN", b"\x00"),
                   rcmd(b"US", b"\x00\x00\x01"), rcmd(b"US", b"\x00\x01\x00"),
                   rcmd(b"US", b"\x00\x02\x00"), rcmd(b"US", b"\x00\x05\x00"),
                   rcmd(b"US", b"\x00\x07\x00"), rcmd(b"DR", b"\x00\x42\x00\x00"),
                   rcmd(b"PP", b"\x00\x01\x01"))
    return part1 + filler + part2 + b"\x1b(A\x09\x00" + b"\x00" * 9


def trailer() -> bytes:
    ld = b"\x1b@\x1b(R\x08\x00\x00REMOTE1" + rcmd(b"LD", b"") + b"\x1b\x00\x00\x00"
    je = b"\x1b@\x1b(R\x08\x00\x00REMOTE1" + rcmd(b"LD", b"") + rcmd(b"JE", b"\x00") + b"\x1b\x00\x00\x00"
    return ld + je


def read_commands(d: bytes, i: int):
    """ESC/P-R commands from position i up to and including j-endj."""
    while i < len(d):
        if d[i] != 0x1b:
            raise ValueError(f"no ESC at position {i}")
        cls = d[i + 1:i + 2]
        ln = int.from_bytes(d[i + 2:i + 6], "little")
        name = d[i + 6:i + 10]
        params = d[i + 10:i + 10 + ln]
        yield cls, name, params
        i += 10 + ln
        if cls + name == b"jendj":
            return


def rewrite(d: bytes, media: int = 0xD2, direction: int = 1, quality: int = 2,
            size_id: int = 0x63) -> bytes:
    """Values from the Windows driver captures:
    media      q-setq byte 0: 0xD2 DS Transfer Rigid, 0xD1 DS Transfer Textile
    quality    q-setq byte 1: 2 = "High", 1 = "Standard"
    direction  j-setj last byte: 1 = unidirectional, 0 = bidirectional
    size_id    m-setm byte 0: 0x00 A4, 0x01 Letter, 0x02 Legal, 0x63 custom size (e.g. mug)
    """
    start = d.find(ESCPR_START)
    if start < 0:
        raise ValueError("not an ESC/P-R job (marker ESC ( R ... ESCPR missing)")
    out = bytearray(preamble())
    out += ESCPR_START
    p_setq_seen = False
    for cls, name, params in read_commands(d, start + len(ESCPR_START)):
        k = cls + name
        if k == b"qsetq":
            params = bytes([media, quality]) + params[2:]
        elif k == b"jsetj":
            top = int.from_bytes(params[8:10], "big", signed=True)
            left = int.from_bytes(params[10:12], "big", signed=True)
            aw, al = int.from_bytes(params[12:16], "big"), int.from_bytes(params[16:20], "big")
            pw, pl = aw + 2 * left, al + 2 * top
            params = (pw.to_bytes(4, "big") + pl.to_bytes(4, "big") + params[8:20]
                      + params[20:21] + bytes([direction]) + params[22:])
        elif k == b"psetq":
            p_setq_seen = True
            params = params[:2] + b"\x04" + b"\x00\xdc" + params[5:]
        out += command(cls, name, params)
        if k == b"qseti":
            out += command(b"m", b"setm", bytes([size_id]) + bytes.fromhex("000063000000"))
            out += command(b"u", b"chku", b"\x01\x00")
        elif k == b"psttp":
            out += command(b"p", b"setq", bytes.fromhex("000304" + "00dc" + "00" * 7))
            p_setq_seen = True
    if not p_setq_seen:
        raise ValueError("p-setq missing - colour adjustment in the printer would stay on")
    out += trailer()
    return bytes(out)


if __name__ == "__main__":
    data = sys.stdin.buffer.read()
    try:
        sys.stdout.buffer.write(rewrite(data, int(os.environ.get("SCF100_MEDIA", "0xD2"), 0),
                                        int(os.environ.get("SCF100_DIRECTION", "1"), 0)))
    except ValueError as e:
        print(f"ERROR: scf100-escpr: {e}", file=sys.stderr)
        sys.exit(1)
