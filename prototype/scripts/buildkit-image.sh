#!/usr/bin/env bash
# Publish the prototype's BuildKit image to the local registry: moby/buildkit
# v0.33.1 plus local/buildkit/buildkitd.toml (see the comment in that file).
# Built with crane from a fixed-mtime layer, so the digest is the same on
# every machine and every run (the org profiles pin it).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
reg=${CC_REGISTRY:-localhost:5001}
base=docker.io/moby/buildkit:v0.33.1@sha256:cec9f139f45e93c5c69c60f8b07cfad9f43f4ef6b6a6cd917527fea5ff2e3dea
dst=$reg/tools/buildkit:v0.33.1-local
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 -I - "$here/local/buildkit/buildkitd.toml" "$tmp/layer.tar" <<'PY'
import sys, tarfile, io
src, out = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
with tarfile.open(out, "w", format=tarfile.PAX_FORMAT) as t:
    for d in ("etc/", "etc/buildkit/"):
        i = tarfile.TarInfo(d.rstrip("/")); i.type = tarfile.DIRTYPE; i.mode = 0o755; i.mtime = 0
        t.addfile(i)
    i = tarfile.TarInfo("etc/buildkit/buildkitd.toml"); i.size = len(data); i.mode = 0o644; i.mtime = 0
    t.addfile(i, io.BytesIO(data))
PY
refs=()
for arch in amd64 arm64; do
  crane append --platform linux/$arch -b "$base" -f "$tmp/layer.tar" -t "$reg/tools/buildkit:v0.33.1-local-$arch" >/dev/null
  refs+=(-m "$reg/tools/buildkit:v0.33.1-local-$arch")
done
crane index append "${refs[@]}" -t "$dst" >/dev/null
echo "$dst@$(crane digest "$dst")"
