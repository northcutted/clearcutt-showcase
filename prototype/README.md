# Local prototype (phase 1)

The whole showcase fleet from [plan §3](../docs/plan.md#3-images-stacks-and-apps),
running on one laptop against a local registry: the platform's six images and
three stacks, the three apps, reproducibility checks, a rebase, the CVE drill
([demo-script Act 6](../docs/demo-script.md#act-6-cve-drill)), and an estate
report with its portal site. Nothing touches GitHub.

What it found is in [FINDINGS.md](FINDINGS.md); logs, digests, and timings are
in [`evidence/`](evidence/).

## Layout

The directories stand in for the future repositories.

| Directory | Future repository | Contains |
|---|---|---|
| `platform/` | `platform` | `factory.org.yaml`; `images/_shared/{build,run}.yaml` and `images/{build,run}-{go,python,node}/` (manifest, lock, Containerfile); `stacks/{go,python,node}.yaml` (and `stacks/factory.org.yaml`, generated, to sign with the stack key) |
| `checkout/` | `checkout` | Go service (chi, uuid) on `localhost:5001/stacks/go:1` |
| `catalog/` | `catalog` | Python 3.14 service (Starlette and uvicorn from hashed `requirements.txt`) with the `catalog._feeds` C extension linked against libxml2, on `stacks/python:1` |
| `storefront/` | `storefront` | Node 24 TypeScript service (Fastify) on `stacks/node:1` |
| `keys/` | (org secrets) | `images.pub` and `stacks.pub`; the private keys are generated locally and never committed |
| `local/buildkit/` | — | the BuildKit config that lets builds pull from the local registry (FINDINGS F11) |
| `scripts/` | — | `up.sh`, `build-all.sh`, `drill.sh`, `estate.sh`, `buildkit-image.sh` |
| `evidence/` | — | logs of every step, and the drill transcripts |

Each app directory carries its own copy of the org profile (registry
`localhost:5001/apps`, tag `latest`), as each app repository will until F5.

## Differences from the plan, and why

- **Registry:** `localhost:5001` (a `registry:2` container named
  `cc-registry`), not GHCR. Port 5000 is macOS's AirPlay receiver.
- **Signing:** cosign key pairs instead of keyless. `keys/images.*` signs
  platform and app images; `keys/stacks.*` signs stacks, and the apps'
  `policy.requireSignedStacks` accepts only that key (`signing.stacks`), so
  the two signer roles stay separate. No transparency log
  (`--tlog-upload=false`; `--insecure-ignore-tlog` when verifying).
- **No SLSA provenance:** it comes from GitHub artifact attestations in CI.
- **BuildKit image:** `builder.buildkit` is `localhost:5001/tools/buildkit:v0.33.1-local`,
  moby/buildkit v0.33.1 plus a registry mirror config (F11).
- **Build images:** ship `/out` and `/src` world-writable so that non-root
  stack steps can write them (F9).
- **Packages:** `run-python` ships `libxml2-16`, `build-python` adds
  `python-3.14-dev`, and every run image ships `libcrypto3`/`libssl3` (W1, W2).

## Reproduce it from scratch

Needs podman (a running machine), cosign, syft, grype, crane, go, git,
python3, and node (for the portal). The sibling clones `../../clearcutt-factory`,
`../../clearcutt-verify` are built from their `origin/main` with `git archive`
(their working trees aren't touched); the portal is read from
`$CC_PORTAL_SRC` (default `/tmp/cp-src`, e.g.
`git -C ../../clearcutt-portal archive origin/main | tar -x -C /tmp/cp-src`).

```sh
scripts/up.sh            # tools, registry, podman config, keys, BuildKit image
scripts/build-all.sh     # platform images → stacks → apps (lock, build, test, scan, push, sign)
scripts/estate.sh base   # clearcutt-verify estate report + portal site in .state/estate/
scripts/drill.sh stage   # the drill's "before" state
scripts/estate.sh before
scripts/drill.sh respond # release, publish, fleet rebase, F3 check, catalog rebuild
scripts/estate.sh after
scripts/drill.sh f6      # reproduce factory#15
scripts/drill.sh status
```

Reproducibility of any published image, from its signed recipe (or by
repeating its rebase record):

```sh
cd platform && clearcutt-factory verify --image localhost:5001/platform/run-python@sha256:…
```

## Results

### 1. Build, test, push, sign

All six platform images, three stacks, and three apps built for
`linux/amd64` and `linux/arm64`, ran as 65532, passed their smoke tests on
both platforms (amd64 under QEMU), passed the gate (`failOn: critical`,
`onlyFixed`), and were pushed with a signature, a recipe, and per-platform
CycloneDX SBOM and vulnerability attestations. Times on an M-series laptop
(6 CPUs to the podman machine), warm BuildKit cache:

| Image | Seconds | Image | Seconds |
|---|---|---|---|
| run-go | 21 | build-go | 69 |
| run-python | 35 | build-python | 135–142 (C toolchain, both arches) |
| run-node | 71 | build-node | 54 |
| checkout | 34 | catalog | 38 (C extension under emulation) |
| storefront | 52 | stack push (each) | ~2 |

### 2. Reproducibility

`clearcutt-factory verify --image <repo>@<digest>` rebuilt every image from
its signed recipe alone, without cache, and got the same digest, including
the non-Go stacks that run under emulation (`crossCompile: false`):

| Image | Rebuild (s) | Image | Rebuild (s) | Image | Rebuild (s) |
|---|---|---|---|---|---|
| run-go | 9 | run-python | 22 | run-node | 28 |
| build-go | 43 | build-python | 88 | build-node | 28 |
| checkout | 16 | catalog | 25 | storefront | 35 |

(`evidence/logs/verify-summary.txt`.) A day later, releasing the drill's
holds re-locked run-go to the same package set and rebuilt it to the same
digest it had before the drill (`sha256:ae37fa63…`), which `build --push`
recognized as already published.

### 3. Rebase

The platform added `libcrypto3`/`libssl3` to every run image and republished
them. `rebase -f <app>/app.yaml --push --update-lock` then moved each app
onto its new run image: both platforms `safe to rebase`, smoke-tested,
scanned, signed, with a rebase record, and the lock pinned to the new base.
checkout 13 s, catalog 19 s, storefront 29 s; repeating each rebase from its
record (`verify --image`) took under 2 s and matched. A rebuild from the new
lock does *not* give the rebased digest (F10): re-running `build-all.sh`
after the drill re-tagged all six platform images and catalog at identical
digests ("already published"), but pushed new digests for the rebased
checkout and storefront (`evidence/act2-build-all.txt`).

### 4. CVE drill

See [`evidence/drill-stage.txt`](evidence/drill-stage.txt) and
[`evidence/drill-respond.txt`](evidence/drill-respond.txt).

**Stage** (`drill.sh stage`, 379 s). `drill-holds.py` pins `libcrypto3` and
`libssl3` to 3.6.3-r4 in `_shared/run.yaml`, and swaps `libxml2-16` for
`libxml2=2.13.6-r3` (`libxml2.so.2`) in run-python and build-python, each line
marked `# DRILL hold`. Publishing the four images took 275 s (build-python
131 s). The fleet then rebased checkout (13 s) and storefront (26 s) onto the
held run images. catalog's rebase was refused, the drill in reverse
(`…/_feeds.cpython-314-x86_64-linux-gnu.so needs libxml2.so.16`), so it was
re-locked and rebuilt on the held build image (37 s).

**Before.** grype on every app (and run image): `libcrypto3`/`libssl3`
3.6.3-r4, **CVE-2026-14456, High**, fixed in 3.6.3-r5; the gate passed
(`failOn: critical`; the two Criticals have no Wolfi fix, so `onlyFixed`
ignores them). grype says nothing about libxml2 2.13.6 (W1), but the estate
report's package index lists `libxml2 2.13.6-r3` in run-python, build-python,
and catalog, and `estate dependents --base …/run-python` names catalog. The
estate's fixable Highs went from 5 (baseline: npm's bundled packages in
build-node) to 17.

**Respond** (`drill.sh respond`, 500 s):

| t (s) | Step | Result |
|---|---|---|
| 0–365 | Release the holds; lock and publish run-go, run-python, run-node, build-python | run-go rebuilt to its pre-drill digest (`ae37fa63…`, re-tagged, not republished); build-python 146 s |
| 378 | checkout: `rebase --push --update-lock` | `safe to rebase` ×2, smoke-tested, signed, rebase record; 13 s |
| 405 | storefront: same | safe ×2; 27 s |
| 407 | catalog: same | **refused**: `…/_feeds.cpython-314-{x86_64,aarch64}-linux-gnu.so needs libxml2.so.2`; exit 1; lock now pins the new run image; 2 s |
| 407 | F3: catalog's lock | only `base` moved; `app.build` still the held build-python |
| 425 | F3: build from that lock | smoke test fails: `ImportError: libxml2.so.2: cannot open shared object file` |
| 471 | `lock --update` (moves the build image too), build, publish | catalog on `libxml2.so.16`, smoke-tested ×2, pushed; 46 s |
| 472 | `verify --image` on the rebased apps | both repeat to the same digest in under 1 s |

**After.** Every app and run image scans with no fixable vulnerabilities;
the estate's fixable Highs are back to 5, and its history has the three runs
(baseline, before, after) for the portal's timeline.

**factory#15** (`drill.sh f6`, after respond): with checkout's pre-pin lock
restored (main before the pin PR merges), `build --push` pushed the held
image (`fbb41265…`, CVE-2026-14456) and moved `latest` to it; the next
fleet rebase moved it forward again (F6).

### 5. Estate verification and portal

`scripts/estate.sh` runs `clearcutt-verify estate verify` over the nine
images (trust policy: the images key for `image`, the stacks key for
`stack`; required: signature, SBOM, vulnerability scan, recipe) and builds
the portal site from the bundle. Every image is `verified`; every base is
proven by layer digest; built apps' stacks are verified against the stack
signer; rebased apps are verified through their rebase records; the history
gains an entry per run (baseline, before, after), which the portal's history
page shows. The workarounds and gaps (V8–V12, P7) are in FINDINGS.md.

## Stop and clean up

```sh
podman rm -f -v cc-registry     # the registry and everything in it
podman volume rm clearcutt-factory-buildkit-cache   # factory's BuildKit cache
podman machine ssh 'sudo rm /etc/containers/registries.conf.d/50-clearcutt-prototype.conf && sudo systemctl restart podman.service'
rm -rf out .state keys/*.key
```
