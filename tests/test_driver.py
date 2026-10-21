# SPDX-License-Identifier: GPL-2.0-or-later
"""Tests without printer and without Epson files: python3 -m unittest discover -s tests"""
import importlib.machinery
import importlib.util
import io
import os
import re
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "lib"))

from scf100 import escpr, raster  # noqa: E402


def load_filter():
    path = os.path.join(ROOT, "filter", "rastertoscf100")
    loader = importlib.machinery.SourceFileLoader("rastertoscf100", path)
    spec = importlib.util.spec_from_loader("rastertoscf100", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def cmd(cls, name, params):
    return escpr.command(cls, name, params)


def sample_job(width=2222, height=5528):
    """A minimal ESC/P-R job as escpr2 writes it (values shortened)."""
    jsetj = (b"\x00\x00\x0b\x00" + b"\x00\x00\x10\x00"           # paper w/l (ignored)
             + (70).to_bytes(2, "big") + (70).to_bytes(2, "big")  # top, left margin
             + width.to_bytes(4, "big") + height.to_bytes(4, "big")
             + b"\x00\x00")                                       # 20: ?, 21: direction
    body = (cmd(b"q", b"seti", b"\x00" * 4)
            + cmd(b"q", b"setq", b"\x0b\x01\x00\x00\x00\x00")
            + cmd(b"j", b"setj", jsetj)
            + cmd(b"p", b"sttp", b"")
            + cmd(b"d", b"bsnd", b"\x01\x02\x03")
            + cmd(b"p", b"endp", b"")
            + cmd(b"j", b"endj", b""))
    return b"\x1b@" + escpr.ESCPR_START + body


class RasterTest(unittest.TestCase):
    def test_v3_roundtrip(self):
        w, h = 7, 3
        data = bytes(range(w * h * 3))
        f = io.BytesIO(b"3SaR" + raster.header_v3(w, h, 600, (12.5, 30.0)) + data)
        pages = list(raster.pages(f))
        self.assertEqual(len(pages), 1)
        head, got = pages[0]
        self.assertEqual((head["cupsWidth"], head["cupsHeight"], head["HWResolutionX"]), (w, h, 600))
        self.assertEqual((head["cupsBitsPerColor"], head["cupsBitsPerPixel"], head["cupsColorSpace"]), (8, 24, 1))
        self.assertAlmostEqual(head["PageWidthF"], 12.5)
        self.assertEqual(got, data)

    def test_v2_compression(self):
        w, h = 4, 2
        hdr = raster.header_v3(w, h, 600, (1.0, 1.0))          # same header layout as version 2
        # one line used twice (repeat byte 1): pixel A three times (run 2), then pixel B once (run 0)
        line = bytes([1]) + bytes([2]) + b"\x0a\x0b\x0c" + bytes([0]) + b"\x01\x02\x03"
        f = io.BytesIO(b"2SaR" + hdr + line)
        head, got = next(raster.pages(f))
        self.assertEqual(got, (b"\x0a\x0b\x0c" * 3 + b"\x01\x02\x03") * 2)

    def test_not_a_raster(self):
        with self.assertRaises(raster.RasterError):
            list(raster.pages(io.BytesIO(b"%PDF-1.7")))

    def test_truncated(self):
        f = io.BytesIO(b"3SaR" + raster.header_v3(10, 10, 600, (1.0, 1.0)) + b"\0" * 10)
        with self.assertRaises(raster.RasterError):
            list(raster.pages(f))


class EscprTest(unittest.TestCase):
    def commands(self, job):
        start = job.find(escpr.ESCPR_START) + len(escpr.ESCPR_START)
        return [(c + n, p) for c, n, p in escpr.read_commands(job, start)]

    def test_rewrite(self):
        out = escpr.rewrite(sample_job(), media=0xD1, direction=1, quality=1, size_id=0x63)
        cmds = self.commands(out)
        names = [n for n, _ in cmds]
        self.assertEqual(names, [b"qseti", b"msetm", b"uchku", b"qsetq", b"jsetj", b"psttp", b"psetq",
                                 b"dbsnd", b"pendp", b"jendj"])
        p = dict(cmds)
        self.assertEqual(p[b"qsetq"][:2], b"\xd1\x01")
        self.assertEqual(p[b"msetm"][0], 0x63)
        self.assertEqual(p[b"psetq"][2:5], b"\x04\x00\xdc")             # LUT 4, gamma 0xDC
        self.assertEqual(int.from_bytes(p[b"jsetj"][0:4], "big"), 2222 + 140)
        self.assertEqual(int.from_bytes(p[b"jsetj"][4:8], "big"), 5528 + 140)
        self.assertEqual(p[b"jsetj"][21], 1)
        self.assertEqual(p[b"dbsnd"], b"\x01\x02\x03")                   # raster data untouched
        self.assertIn(b"PP\x03\x00\x00\x01\x01", out[:80000])            # fixed paper path
        self.assertTrue(out.endswith(b"JE\x01\x00\x00\x1b\x00\x00\x00"))

    def test_existing_psetq_is_patched(self):
        job = sample_job().replace(cmd(b"p", b"sttp", b""),
                                   cmd(b"p", b"sttp", b"") + cmd(b"p", b"setq", b"\x00\x03\x01\x00\x80" + b"\0" * 7))
        cmds = self.commands(escpr.rewrite(job))
        setq = [p for n, p in cmds if n == b"psetq"]
        self.assertTrue(all(p[2:5] == b"\x04\x00\xdc" for p in setq))

    def test_not_escpr(self):
        with self.assertRaises(ValueError):
            escpr.rewrite(b"%!PS")

    def test_wrapper_version(self):
        with tempfile.NamedTemporaryFile() as f:
            f.write(b"\x00junk 1.2.43\x00more 3.14 text 11.2.43.1\x00")
            f.flush()
            self.assertEqual(escpr.wrapper_version(f.name), (1, 2, 43))
        with tempfile.NamedTemporaryFile() as f:
            f.write(b"1.2.9 and 1.2.43")
            f.flush()
            self.assertIsNone(escpr.wrapper_version(f.name))          # ambiguous
        self.assertIsNone(escpr.wrapper_version("/does/not/exist"))
        self.assertLess((1, 2, 9), escpr.ESCPR2_MIN)


class FilterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.f = load_filter()

    def test_find_size(self):
        self.assertEqual(self.f.find_size(680.31, 283.46), (0x63, 2222, 5528))   # mug, landscape
        self.assertEqual(self.f.find_size(595.28, 841.89)[0], 0x00)              # A4
        self.assertEqual(self.f.find_size(500, 700), (0x63, None, None))         # custom

    def test_parse_options(self):
        o = self.f.parse_options("ScfMedia=Textile job-name='a b' noScfMirror collate")
        self.assertEqual(o, {"ScfMedia": "Textile", "job-name": "a b", "ScfMirror": "False", "collate": "True"})

    def test_ppd_defaults(self):
        d = self.f.ppd_defaults(os.path.join(ROOT, "ppd", "epson-scf100-sublimation.ppd"))
        self.assertEqual((d["ScfColor"], d["ScfMedia"], d["ScfMirror"]), ("Driver", "Rigid", "True"))
        self.assertEqual(d["PageSize"], "100x240mmRotated")

    def test_prepare_page_rotates_mug(self):
        from PIL import Image
        w, h = 5528, 2222                                    # printable area of the landscape mug size
        img = Image.new("RGB", (w, h), "white")
        img.putpixel((0, 0), (255, 0, 0))                    # top left of the design
        head = next(raster.pages(io.BytesIO(b"3SaR" + raster.header_v3(w, h, 600, (680.31, 283.46))
                                            + img.tobytes())))[0]
        page, size_id = self.f.prepare_page(head, img.tobytes(), {}, None)
        self.assertEqual((page.size, size_id), ((2222, 5528), 0x63))
        self.assertEqual(page.getpixel((2221, 0)), (255, 0, 0))   # rotated clockwise: top left -> top right


class ConsistencyTest(unittest.TestCase):
    def test_versions_match(self):
        def read(*path, encoding="utf-8"):
            with open(os.path.join(ROOT, *path), encoding=encoding) as f:
                return f.read()
        version = read("VERSION").strip()
        ppd = read("ppd", "epson-scf100-sublimation.ppd", encoding="latin-1")
        self.assertIn(f'*FileVersion: "{version}"', ppd)
        self.assertIn(f"epson-scf100-linux {version}\"", ppd)
        changelog = read("CHANGELOG.md")
        self.assertRegex(changelog, rf"## \[?{re.escape(version)}\]?")


if __name__ == "__main__":
    unittest.main()
