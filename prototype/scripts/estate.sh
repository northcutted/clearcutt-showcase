#!/usr/bin/env bash
# Verify the local estate with clearcutt-verify and build the portal site.
#
#   scripts/estate.sh [label]
#
# Writes the report bundle to .state/estate/bundle (estate-report.json, plus
# estate-history.json, which gains an entry per run, so running this before
# and after the drill gives the portal a timeline) and, if clearcutt-portal's
# dependencies can be installed, the site to .state/estate/site.
#
# Local-only workarounds (FINDINGS.md):
#   - trust policy key paths must be absolute (V-2), so the policy files are
#     generated here rather than committed;
#   - clearcutt-verify has no way to skip the transparency log for key-signed
#     evidence (V-1), so cosign is wrapped to add --insecure-ignore-tlog.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
bin=${CC_BIN:-/tmp/cc-bin}
portal_src=${CC_PORTAL_SRC:-/tmp/cp-src}
label=${1:-run}
state=$here/.state/estate
mkdir -p "$state/bundle" "$state/logs"
reg=localhost:5001

real_cosign=$(type -P cosign)
cat > "$state/cosign-notlog" <<EOF
#!/usr/bin/env bash
# cosign, with verification skipping the transparency log (keys signed with --tlog-upload=false).
case "\${1:-}" in
  verify|verify-attestation) exec "$real_cosign" "\$1" --insecure-ignore-tlog=true "\${@:2}" ;;
  *) exec "$real_cosign" "\$@" ;;
esac
EOF
chmod +x "$state/cosign-notlog"

cat > "$state/trust.yaml" <<EOF
apiVersion: clearcutt.dev/v1
kind: TrustPolicy
signers:
  - name: platform-and-app-images
    roles: [image]
    key: $here/keys/images.pub
  - name: platform-stacks
    roles: [stack]
    key: $here/keys/stacks.pub
EOF

cat > "$state/policy.yaml" <<EOF
apiVersion: clearcutt.dev/v1
kind: VerificationPolicy
# No provenance: SLSA provenance comes from GitHub artifact attestations in CI,
# which a local build doesn't have.
required: [signature, sbom, vulnerabilityScan, recipe]
trustPolicy: trust.yaml
failOn: critical
onlyFixed: true
maxDaysBehind: 7
maxScanAgeDays: 7
EOF

# The inventory: platform images by line tag, apps by latest. The upstream base
# (cgr.dev/chainguard/wolfi-base) is left out on purpose: with it observed,
# clearcutt-verify attributes every app to it instead of its run image, and
# `estate dependents` of a run image comes back empty (FINDINGS.md V-3).
# Set CC_ESTATE_UPSTREAM=1 to include it anyway.
cat > "$state/refs.txt" <<EOF
# platform
$reg/platform/run-go:1
$reg/platform/build-go:1
$reg/platform/run-python:3.14
$reg/platform/build-python:3.14
$reg/platform/run-node:24
$reg/platform/build-node:24
# apps
$reg/apps/checkout:latest
$reg/apps/catalog:latest
$reg/apps/storefront:latest
EOF
if [[ -n ${CC_ESTATE_UPSTREAM:-} ]]; then echo "cgr.dev/chainguard/wolfi-base:latest" >> "$state/refs.txt"; fi

generated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
set +e
"$bin/clearcutt-verify" estate verify --refs "$state/refs.txt" --policy "$state/policy.yaml" \
  --name clearcutt-showcase-local --out "$state/bundle" --cosign-path "$state/cosign-notlog" \
  --platforms linux/amd64,linux/arm64 --generated-at "$generated" 2>&1 | tee "$state/logs/verify-$label.log"
rc=${PIPESTATUS[0]}
set -e
cp "$state/bundle/estate-report.json" "$state/bundle/estate-report.$label.json"
echo "estate verify exit=$rc; report: $state/bundle/estate-report.json"

for base in run-go run-python run-node; do
  "$bin/clearcutt-verify" estate dependents --report "$state/bundle/estate-report.json" \
    --base "$reg/platform/$base" --format json > "$state/bundle/dependents-$base.json" 2>"$state/logs/dependents-$base.err" || true
done

# Portal (needs its npm dependencies once).
if [[ -d $portal_src ]]; then
  if [[ ! -d $portal_src/node_modules ]]; then
    (cd "$portal_src" && npm ci --ignore-scripts --no-audit --no-fund >/dev/null 2>&1) || echo "portal: npm ci failed"
  fi
  rm -rf "$state/site"
  (cd "$portal_src" && node bin/clearcutt-portal.ts build --bundle "$state/bundle" --out "$state/site" \
     --title "ClearCutt showcase (local prototype)") 2>&1 | tee "$state/logs/portal-$label.log" | tail -5
  echo "site: $state/site/index.html"
fi
exit "$rc"
