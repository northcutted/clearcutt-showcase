# Demo script

The demo runs about 40 minutes live, plus waiting on CI. Every step happens on
GitHub in `clearcutt-showcase`. The presenter needs only a browser, `gh`,
`cosign`, and `clearcutt-factory`. Times are estimates; I'll measure them during
rehearsal.

## Act 0: Tour (3 min)

1. **`platform/factory.org.yaml`.** One file sets the registry, signer and caller
   binding, stack signer, vulnerability gate, and policy for the whole org.
2. **`platform/images/run-python/image.yaml`** and its lock. The intent is ten
   lines; the lock pins every package by version and hash.
3. **`platform/stacks/python.yaml`**, pushed as `ghcr.io/clearcutt-showcase/stacks/python:1`
   and signed by the platform workflow.
4. **`catalog/app.yaml`.** An app is a stack reference, env, and a smoke test. It
   can't add OS packages.
5. **The portal** shows every image with its evidence, its base graph, and drift.

**Proves:** ownership is split as factory intends. The platform owns the OS and
toolchains, app teams own only their code.

## Act 1: An app team ships (8 min, mostly CI)

1. Open a `storefront` PR that changes the homepage text. CI runs `render --check`,
   then builds `linux/amd64` and `linux/arm64`, smoke-tests both, writes the SBOM,
   scans, and gates. No secrets are involved.
2. Merge it. On `main`, CI pushes, signs keylessly, attaches the SBOM,
   vulnerability, and recipe attestations, and adds SLSA provenance. A **second
   runner** then rebuilds from the signed recipe alone and the digests match.
3. On the presenter's laptop (a third machine):
   ```sh
   cosign verify ghcr.io/clearcutt-showcase/apps/storefront@sha256:… \
     --certificate-identity-regexp '^https://github\.com/northcutted/clearcutt-factory/\.github/workflows/images\.yml@' \
     --certificate-github-workflow-repository clearcutt-showcase/storefront \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   clearcutt-factory verify --image ghcr.io/clearcutt-showcase/apps/storefront@sha256:…
   gh attestation verify oci://ghcr.io/clearcutt-showcase/apps/storefront@sha256:… --repo clearcutt-showcase/storefront
   ```

**Proves:**
- PRs are gated before merge.
- Images are reproducible bit for bit, and anyone can check that.
- The signature is bound to the repository that built the image, not just to
  the shared workflow.

## Act 2: Nothing changed, nothing published (3 min)

Re-run `platform.yml` on `main`, or push a docs-only change. Every image
rebuilds to the same digest:

- the logs say `… is already published; moved its tags`;
- the reproduce jobs say `nothing to reproduce`;
- no new signatures or attestations pile up.

**Proves:** builds are deterministic, and publishing is idempotent.

## Act 3: Weekly lock updates (6 min)

1. Dispatch `update-locks` in `platform`. It opens one PR per image whose inputs
   moved. Each PR body lists exactly what moved (package versions, image
   digests), and the lock diff shows the hashes.
2. CI gates each PR. Merging one, say `run-node`, publishes it. `notify` then
   wakes the app repos, and `storefront` is rebased onto it (as in Act 6, but
   routine).

**Proves:** updates are reviewable, and they reach apps without any app-team
work.

## Act 4: A toolchain change rebuilds instead of rebasing (5 min)

Bump Go in `build-go` and merge it. The stack is pushed, and `notify` sends
`clearcutt.stack-published`. `checkout` gets a lock-update PR that moves the
stack and build image, and its own CI builds and tests it.

**Proves:** changes to an app's own layer go through that app's CI. Factory
rebases only when the app's bits don't change.

## Act 5: Guardrails across repositories (4 min)

These are three PRs prepared in advance. Each fails with a precise message.

1. **Unsigned stack.** `catalog` points at an unsigned stack pushed to a
   scratch tag. `lock` fails with `stack … is not signed by the org's signer
   (policy.requireSignedStacks)`.
2. **Root user.** `checkout` sets `user: "0"`. Policy fails because the profile
   requires non-root.
3. **OS packages.** `storefront` adds `packages:` to `app.yaml`. The manifest is
   rejected, because what an app needs from the OS belongs in the run image.

**Proves:** the platform's policy holds in every app repository, not just its
own.

## Act 6: CVE drill

### Staging

Done before the audience arrives, with `bringup/drill-github.sh stage`
([results](../bringup/DRILL-RESULTS.md)). It opens and merges a platform PR
labelled **DRILL**. That PR holds two packages at their last
vulnerable Wolfi builds:

- **OpenSSL 3** (`libcrypto3`/`libssl3`) at **3.6.3-r4**, in every run image
  (the platform ships them as compatibility libraries; wolfi-base itself is on
  OpenSSL 4.0). grype reports **CVE-2026-14456 (High)**, fixed in 3.6.3-r5;
  the release resolves 3.6.5-r2. Two Criticals with no Wolfi fix recorded
  (CVE-2026-63073, CVE-2026-75803) are ignored by `onlyFixed`, so the gate
  passes; turning `onlyFixed` off would need VEX in `platform/vex/`.
- **libxml2 2.13.6-r3** (`libxml2.so.2`) in `run-python` and `build-python`,
  instead of `libxml2-16` (2.15.x, `libxml2.so.16`). This is a realistic "ABI
  hold": catalog's C extension is built against `.so.2`. Upstream 2.13.6 has
  Highs (CVE-2025-32414, -32415; CVE-2025-7425 is fixed only on the `.so.16`
  line), but **grype reports none of them** for Wolfi's package (FINDINGS W1),
  so this one is detected from the package index, not the scanner.

These were picked while prototyping (`prototype/scripts/drill-holds.py`).
The fleet automation rebases checkout and storefront onto the held images;
catalog's rebase is refused (it needs `libxml2.so.16`) and it is rebuilt on
the held build image. Those are the "before" state the audience sees.

### Live (about 22 min of wall clock; times from merge)

The "Measured" column is the first real run, on 2026-10-17 under
`northcutted`, without the GitHub App: the apps' fleets were woken by hand
and their pull requests reopened to start CI
([`bringup/DRILL-RESULTS.md`](../bringup/DRILL-RESULTS.md) has every run and
PR).

| t | Measured | Step | What the audience sees | Proves |
|---|---|---|---|---|
| −2m | 17 fixable Highs (baseline 5) | **Detect** | The portal and estate report show the High CVE in OpenSSL 3 in all run images and the 3 apps that inherit it, and the package index shows libxml2 2.13.6 in `run-python`, `build-python`, and `catalog` (the scanner doesn't flag it). The base graph shows which apps sit on which run image, proven by layer digest. | One fleet-wide answer to "who is affected?", including inherited exposure |
| 0 | gate 3m40s | **Fix** | `drill-github.sh respond` opens the platform PR "Release the OpenSSL and libxml2 holds". The lock diff shows exact versions, CI's gate is green, and the PR is merged. | The fix is a reviewed, gated change to a lockfile |
| ~8m | published +5m10s; reproduced +7m25s; notify +7m35s | **Publish** | The run and build images are published, signed, and attested. The second runner reproduces them. `notify` dispatches to `checkout`, `catalog`, and `storefront`. | The platform's publish is the only manual step |
| ~12m | pin PRs +11m58s, +12m05s | **Rebase** | `checkout` and `storefront` report `linux/amd64: safe to rebase`, `linux/arm64: safe to rebase`. They are smoke-tested, scanned, gated, signed, and pushed with a **rebase record**. The rebase is repeated from that record, the digests match, and a pin PR opens in each app repository. | Patched in minutes, with no app-team action and no rebuild |
| ~12m | refused +9m45s; rebuild PR +9m35s | **Refusal** | `catalog` reports `incompatible: the new base lacks libraries the app loads: /app/lib/catalog/_feeds…so needs libxml2.so.2`. Its job goes red, and it gets a **rebuild PR** instead. | Factory refuses an unsafe rebase, says exactly why, and routes it to a human |
| ~20m | CI 2m24s; merged +16m20s; published +21m38s | **Rebuild** | CI on catalog's PR rebuilds against the new build image (`libxml2.so.16`; needs F3) and passes. The catalog team merges it and it is published. | The fallback path is automated up to the review |
| ~25m | estate and portal +27m03s: 5 fixable Highs, 9/9 verified | **All clear** | The estate report and portal show the drill's Highs gone (the 5 left are build-node's npm, as before the drill), every app current on its run image, rebase records verified, and a before-and-after timeline. | The response is auditable after the fact |

Merge the pin PRs, or let auto-merge do it, before any other push to an app's
`main`. Otherwise a rebuild from the old lock moves `latest` back (F6).

### Reset

Run `drill-github.sh stage` again. This exercises the refusal path in
reverse (measured: catalog refused with `needs libxml2.so.16` at +9m51s).

## Act 7: The boring parts keep running (2 min)

- The daily fleet runs show `already on the newest base; nothing to do`.
- The weekly lock jobs show no PRs when nothing moved.
- The estate history shows the drill as a blip.

**Proves:** steady state is quiet. Automation only speaks when something
changed.
