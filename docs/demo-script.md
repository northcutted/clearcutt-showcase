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

Done before the audience arrives, with `demo/drill.sh stage`. It opens and
merges a platform PR labelled **DRILL**. That PR holds two packages at their last
vulnerable Wolfi builds:

- **OpenSSL** (`libcrypto3`/`libssl3`), present in every run image through
  wolfi-base;
- **libxml2 2.13.x** in `run-python` and `build-python`. This is a realistic
  "ABI hold": 2.14 changed the soname from `libxml2.so.2` to `libxml2.so.16`.
  catalog's C extension was built against `.so.2`.

The exact CVEs are picked while prototyping. They must be real, fixed in a
newer Wolfi build, and rated **High**, so the "before" state passes the
critical gate. If something triaged as not exploitable is Critical, the
security team records that in `platform/vex/`, which is a real feature to
show. The fleet automation rebases every app onto the held images. The
rebased apps are the "before" state the audience sees.

### Live (about 20 min of wall clock; times from merge)

| t | Step | What the audience sees | Proves |
|---|---|---|---|
| −2m | **Detect** | The portal and estate report show the High CVEs: OpenSSL in all run images and the 3 apps that inherit it; libxml2 in `run-python` and `catalog`. The base graph shows which apps sit on which run image, proven by layer digest. | One fleet-wide answer to "who is affected?", including inherited exposure |
| 0 | **Fix** | `drill.sh respond` opens the platform PR "Release the OpenSSL and libxml2 holds". The lock diff shows exact versions, CI's gate is green, and the PR is merged. | The fix is a reviewed, gated change to a lockfile |
| ~8m | **Publish** | The run and build images are published, signed, and attested. The second runner reproduces them. `notify` dispatches to `checkout`, `catalog`, and `storefront`. | The platform's publish is the only manual step |
| ~12m | **Rebase** | `checkout` and `storefront` report `linux/amd64: safe to rebase`, `linux/arm64: safe to rebase`. They are smoke-tested, scanned, gated, signed, and pushed with a **rebase record**. The rebase is repeated from that record, the digests match, and a pin PR opens in each app repository. | Patched in minutes, with no app-team action and no rebuild |
| ~12m | **Refusal** | `catalog` reports `incompatible: the new base lacks libraries the app loads: /app/lib/catalog/_feeds…so needs libxml2.so.2`. Its job goes red, and it gets a **rebuild PR** instead. | Factory refuses an unsafe rebase, says exactly why, and routes it to a human |
| ~20m | **Rebuild** | CI on catalog's PR rebuilds against the new build image (`libxml2.so.16`; needs F3) and passes. The catalog team merges it and it is published. | The fallback path is automated up to the review |
| ~25m | **All clear** | The estate report and portal show zero fixable Highs, every app current on its run image, rebase records verified, and a before-and-after timeline. | The response is auditable after the fact |

Merge the pin PRs, or let auto-merge do it, before any other push to an app's
`main`. Otherwise a rebuild from the old lock moves `latest` back (F6).

### Reset

Run `drill.sh stage` again. This exercises the refusal path in reverse.

## Act 7: The boring parts keep running (2 min)

- The daily fleet runs show `already on the newest base; nothing to do`.
- The weekly lock jobs show no PRs when nothing moved.
- The estate history shows the drill as a blip.

**Proves:** steady state is quiet. Automation only speaks when something
changed.
