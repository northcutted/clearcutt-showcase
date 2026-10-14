#!/usr/bin/env bash
# Bring up everything the local prototype needs, idempotently:
#
#   1. the tools: clearcutt-factory and clearcutt-verify built from origin/main
#      of the sibling clones (git archive, so their working trees are untouched)
#   2. a local OCI registry container (cc-registry) on localhost:5001
#   3. podman machine: localhost:5001 marked insecure (plain HTTP) for pulls
#   4. cosign key pairs for the two signer roles (images, stacks)
#   5. the BuildKit image the org profiles pin (scripts/buildkit-image.sh)
#
# Env: CC_BIN (default /tmp/cc-bin), CC_SRC (default the parent of this repo),
#      CC_REBUILD_TOOLS=1 to rebuild the tools even if present.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
src=${CC_SRC:-$(cd "$here/../.." && pwd)}
bin=${CC_BIN:-/tmp/cc-bin}
reg_port=5001

say() { printf '==> %s\n' "$*"; }

for t in podman cosign syft grype crane go git python3; do
  command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done

# 1. Tools from origin/main.
build_tool() { # name main-package-dir module-dir
  local name=$1 pkg=$2 dir=$3 tmp
  if [[ -x $bin/$name && -z ${CC_REBUILD_TOOLS:-} ]]; then
    say "$name: using $bin/$name ($("$bin/$name" version 2>/dev/null | head -1 || true))"
    return
  fi
  tmp=$(mktemp -d)
  git -C "$src/$name" fetch --quiet origin
  git -C "$src/$name" archive origin/main | tar -x -C "$tmp"
  mkdir -p "$bin"
  (cd "$tmp/$dir" && go build -o "$bin/$name" "$pkg")
  say "$name: built $bin/$name from origin/main $(git -C "$src/$name" rev-parse --short origin/main)"
  rm -rf "$tmp"
}
build_tool clearcutt-factory ./cmd/clearcutt-factory .
build_tool clearcutt-verify ./cmd/clearcutt-verify cli

# 2. Registry. Port 5000 is taken by macOS's AirPlay receiver, hence 5001.
if ! podman container exists cc-registry; then
  say "starting cc-registry on localhost:$reg_port"
  podman run -d --name cc-registry --restart=always -p $reg_port:5000 \
    -e REGISTRY_STORAGE_DELETE_ENABLED=true docker.io/library/registry:2 >/dev/null
elif [[ $(podman inspect -f '{{.State.Running}}' cc-registry) != true ]]; then
  podman start cc-registry >/dev/null
fi
until curl -fsS "http://localhost:$reg_port/v2/" >/dev/null 2>&1; do sleep 1; done
say "registry: http://localhost:$reg_port/v2/_catalog"

# 3. podman machine: pull from localhost:5001 over plain HTTP (factory runs the
#    pinned BuildKit image from there). Restart the API service only on change.
conf=/etc/containers/registries.conf.d/50-clearcutt-prototype.conf
want=$'[[registry]]\nlocation = "localhost:'$reg_port$'"\ninsecure = true'
if [[ $(podman machine ssh "cat $conf 2>/dev/null" | grep -v '^#' || true) != "$want" ]]; then
  say "podman machine: marking localhost:$reg_port insecure ($conf)"
  printf '# ClearCutt showcase prototype: local plain-HTTP registry (cc-registry)\n%s\n' "$want" |
    podman machine ssh "sudo mkdir -p /etc/containers/registries.conf.d && sudo tee $conf >/dev/null"
  podman machine ssh 'sudo systemctl restart podman.service'
  sleep 2
fi

# 4. Signing keys (never committed; see .gitignore).
export COSIGN_PASSWORD=${COSIGN_PASSWORD:-}
for role in images stacks; do
  if [[ ! -f $here/keys/$role.key ]]; then
    say "generating cosign key pair keys/$role.{key,pub}"
    rm -f "$here/keys/$role.pub"   # a committed .pub without its .key is useless here
    (cd "$here/keys" && cosign generate-key-pair --output-key-prefix "$role" >/dev/null 2>&1)
  fi
done

# 5. BuildKit image with the registry mirror.
say "BuildKit image: $("$here/scripts/buildkit-image.sh" 2>/dev/null)"
say "ready. Next: scripts/build-all.sh"
