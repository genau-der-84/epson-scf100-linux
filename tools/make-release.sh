#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Build dist/epson-scf100-linux-VERSION.tar.gz (+ .sha256) from the files tracked by git.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
v=$(cat VERSION)
mkdir -p dist
git archive --format=tar.gz --prefix="epson-scf100-linux-$v/" -o "dist/epson-scf100-linux-$v.tar.gz" HEAD
(cd dist && sha256sum "epson-scf100-linux-$v.tar.gz" > "epson-scf100-linux-$v.tar.gz.sha256")
ls -l dist
