# Phase 1 findings

Every tool gap, bug, or surprise the local prototype hit, with how to
reproduce it, which project owns it, and how much it matters for the
showcase. IDs continue [plan.md §8](../docs/plan.md#8-what-each-tool-must-provide):
F1–F8, V1–V7, and P1–P6 are the plan's; F9–F16 (clearcutt-factory), V8–V12
(clearcutt-verify), and P7 (clearcutt-portal) are new; W1–W2 are upstream
(Wolfi, grype) and L1 is local-only.

Severity: **High** blocks a plan step or makes a demo claim untrue;
**Medium** needs a workaround or misleads; **Low** is friction.

Tools: clearcutt-factory and clearcutt-verify built from `origin/main`
(factory 38f4882, verify 123afd8), clearcutt-portal `origin/main` 6059220;
podman 6.0.2 (rootful machine, arm64, QEMU for amd64), cosign 3.1.3,
grype 0.120.1 (DB built 2026-10-10), syft, crane.

## Summary

The status column is as phase 1 found it (2026-10-15). Since then every
finding but W1 has been fixed and released; [`docs/issues.md`](../docs/issues.md)
has the current status and the fixing pull requests.

| ID | Owner | Severity | Finding | Status in phase 1 |
|---|---|---|---|---|
| F3 | factory | High | A refused rebase with `--update-lock` moves only the run image; rebuilding then uses the old build image | **Confirmed** on main; fix in PR #30 (open) |
| F6 | factory | High | Rebuilding from the old lock moves `latest` back to an unpatched image (#15) | **Reproduced** on main; fix in PR #32 (open) |
| F1, F2 | factory | — | Caller binding and a stack signer | Fixed in v0.1.1 (`sourceRepository`, `signing.stacks`); stack signer exercised here with keys |
| F9 | factory | High | Non-root build images (which `requireNonRoot` demands) break every app build | Worked around |
| F10 | factory | Medium | A rebased image never equals a rebuild from the pinned lock (base layer annotations) | New |
| F11 | factory | Medium | No way for the containerized BuildKit to reach a local or plain-HTTP registry | Worked around |
| F12 | factory | Low | Key mode has one signing key per profile; `stack push` can't sign as the stack signer | Worked around |
| F13 | factory | Low | Trust-policy `key:` paths resolve against the working directory | New |
| F14 | factory | Low | factory's own files (`app.lock.yaml`, `app.Containerfile`) are in the app's build context by default | Worked around |
| F15 | factory | Low | The documented `--tlog-upload=false` is deprecated in cosign 3 | New |
| F16 | factory | Low | `stack push` re-pushes and re-signs an unchanged stack, so signatures pile up | New |
| V8 | verify | Medium | No way to verify key-signed evidence made without a transparency log | Worked around |
| V9 | verify | Medium | Trust-policy `key:` paths aren't resolved against the policy file | Worked around |
| V10 | verify | High | With an upstream base in the inventory, apps are attributed to it instead of their run image; `estate dependents` is empty | Worked around |
| V11 | verify | Medium | Rebased apps lose their stack: `stacks` is null and stack signatures go unchecked | New |
| V12 | verify | Medium | `--reproduce` can't run for key signers | From code reading; not run |
| P7 | portal | Medium | Pages don't show stacks, `packagesSource`, or per-image history (its contract copy is older than verify's) | Confirmed |
| W1 | Wolfi/grype | High (demo) | grype sees no CVEs in OpenSSL 4.0 packages or in Wolfi libxml2 2.13.x | Drill adjusted |
| W2 | Wolfi | Medium (plan) | Package names moved: `openssl-4.0-*`, `libxml2-16`; plain `libxml2` is now empty; C extensions need `python-3.14-dev` | Plan updated |
| L1 | local | — | Port 5000 is macOS AirPlay; podman's API needed a restart to read `registries.conf.d` | Scripted in `up.sh` |

## clearcutt-factory

### F3: a refused rebase pins the new run image but keeps the old build image (High) — confirmed

Run: `drill.sh stage`, then `drill.sh respond`; output in
`evidence/drill-respond.txt`, logs in `evidence/logs/drill-respond-*`.

1. catalog was built against libxml2 2.13 (`libxml2.so.2`); the released
   run-python ships only `libxml2.so.16`.
2. `clearcutt-factory rebase -f catalog/app.yaml --push --update-lock` is
   refused on both platforms and exits 1:
   ```
   incompatible: the new base lacks libraries the app loads: /app/lib/catalog/_feeds.cpython-314-x86_64-linux-gnu.so needs libxml2.so.2
   error: the new base may break this image; rebuild it, or pass --force to rebase anyway
   catalog/app.lock.yaml now pins the new base; build the app to move it
   ```
3. The lock diff is one line: `base.digest` moved to the new run-python
   (`3718435d…` → `17210815…`); `app.build` still pins the held build-python
   (`56da8941…`, libxml2-dev 2.13).
4. `clearcutt-factory build -f catalog/app.yaml` from that lock (what merging
   the rebuild PR runs today) compiles `_feeds` against `libxml2.so.2` again,
   onto a run image without it, and fails its smoke test:
   `ImportError: libxml2.so.2: cannot open shared object file: No such file or directory`.
5. `lock --update` (which also moves the build image, `56da8941…` →
   `39744f22…`) and a rebuild fix it: catalog builds against
   `libxml2.so.16`, passes, and is published (`sha256:dd866467…`).

The stage step showed the same thing in reverse (catalog built on
`libxml2.so.16`, refused onto the held run image: `needs libxml2.so.16`).

Code: `internal/factory/rebase.go` calls `lockManifest(…,
LockOptions{UpdateBase: true, …})`, and `UpdateBase` only clears `Base` and
`App.RunPlatforms` (`internal/factory/factory.go`, `lockManifest`). Fix:
[PR #30](https://github.com/northcutted/clearcutt-factory/pull/30) (open;
not tested here, which ran factory main).

### F6 (factory#15): a push before the pin PR merges moves `latest` back (High) — reproduced

`drill.sh f6 checkout`, after `drill.sh respond`; output in
`evidence/drill-f6.txt`.

1. The fleet rebased checkout onto the patched run-go: `latest` =
   `sha256:ccf63a29…` (no fixable vulnerabilities).
2. Main still has the old lock (the pin PR isn't merged). `build --push` from
   it rebuilt the held checkout, which passes the gate (`failOn: critical`;
   its CVE is High), pushed `sha256:fbb41265…`, and moved `latest` to it.
   grype on it: `libcrypto3 3.6.3-r4 … CVE-2026-14456 High`.
3. The next fleet run rebased it forward again (`ccf63a29…`, "already
   published; moved its tags (latest)").

Step 2 pushed a new digest rather than re-tagging the held image the fleet
had published (`1c3879ed…`), because a rebuild never equals a rebase (F10);
had the old image been built rather than rebased, it would have printed "is
already published; moved its tags". Either way `latest` goes back. Fix:
[PR #32](https://github.com/northcutted/clearcutt-factory/pull/32) (open; not
tested here).

### F9: non-root build images break app builds (High)

`policy.requireNonRoot` applies to every manifest, including stack build
images, so they need a non-root `user`. The app build stage factory renders
(`internal/render/render.go`, `renderApp`) runs the stack's steps as the build
image's user, and:

- the first step begins with `mkdir -p /out` in `/`:
  `podman run --rm --user 65532 cgr.dev/chainguard/wolfi-base sh -c 'mkdir -p /out'`
  → `mkdir: can't create directory '/out': Permission denied`;
- `COPY src/ /src/` makes the source root-owned, so steps that write it fail
  (`npm prune --omit=dev` rewriting `package-lock.json` → `EACCES`);
- BuildKit cache mounts (`caches:`) are created root-owned, so a non-root step
  can't write them.

Workaround: `platform/images/_shared/build.yaml` ships `/out` and `/src` as
mode `1777` through a `from: build` tool (`stack-workdirs`); the go stack drops
`caches:` and puts `GOCACHE`/`GOMODCACHE` in `/tmp`; the node stack runs
`npm prune --omit=dev --no-save`. Fix: render `USER 0` at the top of the app
build stage (it never ships; the run image's user is what counts), or exempt
stack build images from `requireNonRoot`, and let `caches:` take a uid.

### F10: a rebased image never equals the rebuild of its pinned lock (Medium)

After `rebase -f checkout/app.yaml --push --update-lock` pushed
`sha256:ccf63a29…`, rebuilding from the updated lock without cache
(`verify -f checkout/app.yaml --digest sha256:ccf63a29…`) gives
`sha256:25f2ca6b…`. Layer digests, config, and manifest annotations are
identical. Only two layer descriptors differ: a rebase copies the new base's
descriptors verbatim, including BuildKit's `buildkit/rewritten-timestamp`
annotations on the run image's own layers, while a BuildKit build drops
base-layer annotations.

Consequences: merging a pin PR republishes the same content under a new
digest (new signatures and attestations, another `latest` move), so Act 2's
"nothing changed, nothing published" fails after every fleet rebase; and F6
rebuilds produce new digests instead of finding the old ones. Seen in
practice: re-running `build-all.sh` against the committed locks after the
drill re-tagged every platform image and catalog (built) at identical
digests, but pushed new digests for checkout and storefront (rebased)
(`evidence/act2-build-all.txt`). Fix: drop or
normalize base-layer descriptor annotations when rebasing, so a rebase and a
rebuild of the pinned lock agree bit for bit.

### F11: the containerized BuildKit can't pull from a local or plain-HTTP registry (Medium)

factory runs BuildKit with `podman run --privileged` on the default network
and fixed arguments (`internal/builder/buildkit.go`). Image references to
`localhost:5001/…`, which the host, cosign, syft, grype, and
go-containerregistry all need, resolve inside that container to the
container itself, and there is no way to pass a `buildkitd.toml` (mirrors,
`http = true`) or a network. Only `builder.addr` (a remote buildkitd plus a
local `buildctl`) escapes it.

Workaround: `builder.buildkit` names
`localhost:5001/tools/buildkit:v0.33.1-local`, which is moby/buildkit v0.33.1
plus a `buildkitd.toml` that mirrors `localhost:5001` to
`host.containers.internal:5001` over HTTP (`local/buildkit/`,
`scripts/buildkit-image.sh`; built with crane from a fixed-mtime layer, so its
digest is stable). Fix: a `builder.config` (buildkitd.toml) mounted into the
container, or `builder.network: host`.

### F12: one signing key per profile (Low)

In key mode, `signing.key` signs images and stacks alike
(`internal/factory/stack.go`); there is no per-role key or
`stack push --key`. With keyless CI this doesn't arise (the stacks workflow
has its own identity), but with keys the platform needs a second profile to
sign as the stack signer: `platform/stacks/factory.org.yaml`, regenerated by
`build-all.sh`. Fix: `stack push --key`, or `signing.stackKey`.

### F13: trust-policy `key:` is relative to the working directory (Low)

`LoadOrg` resolves `signing.key`, `signing.verify.key`, and
`signing.stacks.key` against the profile, but `LoadTrustPolicy`
(`internal/manifest/trust.go`) leaves a signer's `key:` as written. A shared
trust policy with relative keys therefore works only from one directory;
clearcutt-verify has the same problem (V9). This prototype uses
`signing.verify`/`signing.stacks` for factory and generates verify's trust
policy with absolute paths. Fix in both tools: resolve relative keys against
the trust policy file.

### F14: factory's own files are in the app's build context (Low)

The default app excludes are `.git` and `/out` (`render.DefaultExclude`), so
`app.lock.yaml`, `app.Containerfile`, and a per-repository `factory.org.yaml`
are copied into `/src` and embedded in the recipe; a lock-only pin PR changes
the build context. The apps here exclude them in `app.yaml`. Fix: exclude the
manifest's own lock and Containerfile by default.

### F15: cosign 3 deprecates `--tlog-upload` (Low)

The example profile documents `signing.args: [--use-signing-config=false,
--tlog-upload=false]`; cosign 3.1.3 prints `Flag --tlog-upload has been
deprecated, prefer using a --signing-config file with no transparency log
services` on every sign and attest. Fix: document a signing-config file.

### F16: `stack push` isn't idempotent (Low)

`stack push` always pushes and signs (`internal/factory/stack.go`), unlike
`build --push`, which re-tags an already published, attested digest. The
Act 2 re-run pushed the three unchanged stacks again (same digests) and
added a second signature to each (`crane manifest
localhost:5001/stacks/go:sha256-0852…` lists 2). Fix: skip the push and
signature when the digest exists and carries a valid stack signature.

### Other factory observations

- Releasing a hold re-resolves every package of that image, not just the
  held one: the drill's release also moved `python-3.14` from
  `3.14.8_git20261008-r1` to `3.14.8_git20261014-r0` in run-python (the lock
  is re-solved whenever the package list changes). Reasonable, but a CVE
  pull request then carries unrelated updates; `lock --update-package NAME`
  would keep it focused.
- Reproducibility held across a day: after the drill, run-go re-locked to
  the same packages and rebuilt to the digest it had the day before
  (`sha256:ae37fa63…`), and `build --push` re-tagged it instead of
  republishing.

## clearcutt-verify

### V8: key-signed evidence without a transparency log can't be verified (Medium)

With images signed `--tlog-upload=false`, every check fails with `not signed
by a trusted signer: cosign verify: exit status 1: failed to verify log
inclusion: not enough verified log entries from transparency log: 0 < 1`. The
message is also misleading: the trusted key did sign it. There is no
`--insecure-ignore-tlog`, per-signer cosign args, or offline mode.

Repro: `printf 'localhost:5001/platform/run-go:1\n' > r.txt && clearcutt-verify
estate verify --refs r.txt --policy .state/estate/policy.yaml --out /tmp/x`.
Workaround: `scripts/estate.sh` passes `--cosign-path` to a wrapper that adds
`--insecure-ignore-tlog=true` to `verify` and `verify-attestation`. Fix: a
signer-level `args` (like factory's `signing.verify.args`) or `tlog: false`.

### V9: trust-policy `key:` isn't resolved against the policy file (Medium)

`key:` goes to cosign verbatim, and cosign runs in the current directory (for
`--reproduce`, in a cache directory), so relative keys break; the report also
records the path as written. Workaround: `estate.sh` generates the trust
policy with absolute paths. Same fix as F13.

### V10: with an upstream base observed, apps are attributed to it, not to their run image (High)

With `cgr.dev/chainguard/wolfi-base:latest` in the inventory (plan §7 lists
it), every app's base is reported as wolfi-base, and
`estate dependents --base localhost:5001/platform/run-python` returns `[]`.
Without it, each app is proven on its run image (`layer-prefix`, proof).

Cause: `cli/internal/estategraph/graph.go`, `bestEdgeFor`, keeps the first
match among equally ranked methods (`if rank >= bestRank { continue }`) and
walks repositories alphabetically, so `cgr.dev/…` (a shorter layer prefix)
beats `localhost:5001/platform/run-python` (a longer one). Fix: among
`layer-prefix` matches, prefer the longest prefix (the nearest base). As it
stands this breaks the plan's base graph, the drill's "who is affected", and
V5's dependents output whenever an upstream base is inventoried. Workaround:
`estate.sh` leaves the upstream base out (`CC_ESTATE_UPSTREAM=1` adds it).

### V11: rebased apps lose their stack (Medium)

After the fleet rebases the apps (the normal steady state), the report has
`stacks: null`, and each app's `factory` has `rebasedFrom` and `stack` but no
`stackRef`/`stackDigest`, so stack versions and stack signatures are no
longer reported or verified. Before the rebase (apps built from recipes) all
three stacks were listed and verified against the stack signer. Fix: follow
`rebasedFrom` to the recipe for the stack fields too.

### V12: `--reproduce` doesn't work with key signers (Medium, not run)

From the code (`cli/internal/estateverify/build.go`, `trustedSignerFor`
ignores `Key`), a key-signed image's reproduction is `not-checked`, which
makes every factory image `unverified` when `--reproduce` is on. Not run
here; factory's own `verify --image` was run for every image instead (all
reproduce). Confirm, then pass `--key` through.

### Other observations

- Rebased images show **Tests: Missing**, while images built from a recipe
  show the recipe's smoke test as present. The fleet runs the same smoke test
  on a rebase, but nothing records it (relates to F7).
- `registry scan` would list cosign 3's `sha256-<digest>` bundle tags and the
  stack artifacts as images; the prototype passes explicit refs.

## clearcutt-portal

### P7: the site doesn't show what verify now reports (Medium)

The portal's `contract/` is pinned to an older clearcutt-verify commit
(`contract/UPSTREAM`). Reports from verify's main pass `check` (the portal
drops `additionalProperties: false`), but no page shows `stacks` or stack
signatures, `packagesSource` (a package page says "the report doesn't say
which source each image's package list was read from", though it now does),
or per-image history. The rest works from the bundle alone, offline:
overview, per-image evidence pages, bases, package pages (P5: who ships
`libxml2` at which version), and the history timeline (P6). Built with
`node bin/clearcutt-portal.ts build --bundle … --out …` (`scripts/estate.sh`).

## Wolfi and scanners

### W1: grype doesn't see the drill's packages as Wolfi ships them now (High for the demo)

- **OpenSSL.** wolfi-base and the language runtimes use OpenSSL 4.0
  (`openssl-4.0-libcrypto`, `openssl-4.0-libssl`; `libcrypto.so.4`). grype
  reports nothing for any `openssl-4.0-*` build: Wolfi's secdb has no entries
  for those names and NVD's CPE (`openssl:openssl`) doesn't match them, though
  NVD lists Highs fixed in 4.0.3. Holding the runtimes' OpenSSL would show
  nothing. The drill holds the OpenSSL 3 compatibility libraries
  (`libcrypto3`, `libssl3`), which the secdb covers: at 3.6.3-r4 grype reports
  **CVE-2026-14456 (High, fixed in 3.6.3-r5)**. Every 3.6.3 build also has
  two Criticals with an unknown fix state (CVE-2026-63073, CVE-2026-75803;
  fixed upstream in 3.6.4), which `onlyFixed: true` ignores, so the gate
  passes; with `onlyFixed: false` they'd need VEX.
- **libxml2.** Wolfi's secdb records no libxml2 fix after 2.11.5, and syft's
  CPE vendor (`libxml2`) doesn't match NVD's (`xmlsoft`), so grype reports
  **nothing** for 2.13.6-r3, though upstream 2.13.6 has CVE-2025-32414 and
  CVE-2025-32415 (High, fixed in 2.13.8) and CVE-2025-7425 (High, fixed only
  in 2.14.6, i.e. only with `libxml2.so.16`). The drill keeps the libxml2 hold
  for the ABI story (the refusal), but its "Detect" step must come from the
  package index (verify's report and the portal's package pages list every
  image that ships `libxml2` 2.13.6-r3), not from the scanner.

Owner: upstream (Wolfi advisories, grype matching). Showcase: Act 6 updated.

### W2: package names in the plan are out of date (Medium, plan)

- From 2.15.1-r2, `libxml2` is an empty transitional package; the library is
  `libxml2-16` (`libxml2.so.16`). run-python asked for `libxml2` and got no
  library (its smoke test caught it); it now names `libxml2-16`.
  `libxml2-dev` depends on `libxml2-16`.
- Wolfi also carries a 2.13 line (`libxml2-2.13-2`, 2.13.9, `libxml2.so.2`):
  a more realistic long-lived "ABI hold" than pinning `libxml2=2.13.6-r3`.
- build-python needs `python-3.14-dev` (`Python.h`) for C extensions.
- wolfi-base's repository is `https://apk.cgr.dev/chainguard` (a superset of
  packages.wolfi.dev/os with identical checksums).

## Local prototype only

### L1: environment

- macOS's AirPlay receiver holds port 5000, so the registry is on 5001.
- The podman machine (rootful) needed `localhost:5001` marked insecure in
  `/etc/containers/registries.conf.d/` and a restart of `podman.service`
  before its API honored it. `up.sh` does both, once.
