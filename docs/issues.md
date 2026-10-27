# Issues filed for the showcase

Plan IDs are the ones in [plan.md §8](plan.md#8-what-each-tool-must-provide).
Phase 1 (the local prototype) found F9–F16, V8–V12, and P7; evidence and repro
steps are in [`prototype/FINDINGS.md`](../prototype/FINDINGS.md).

This is the showcase's only status table. **As of 2026-10-18 every pull
request below is merged and released** (clearcutt-factory v0.1.1–v0.3.0,
clearcutt-verify v0.15.0–v0.16.0, clearcutt-portal v0.1.0); a PR link in a
row is the fix. W1 (upstream) is the one finding still open. The work that
followed the second assessment is in [`assessment.md`](assessment.md) and
[below](#from-the-second-assessment-2026-10-18).

## clearcutt-factory

| Plan | Issue | Status |
|---|---|---|
| F1 | [#11](https://github.com/northcutted/clearcutt-factory/issues/11): reusable-workflow signatures don't match the identity `init` writes | Fixed in v0.1.1 |
| F2 | [#12](https://github.com/northcutted/clearcutt-factory/issues/12): `requireSignedStacks` uses the image signer | Fixed in v0.1.1; enforced wherever a stack is used in [PR #33](https://github.com/northcutted/clearcutt-factory/pull/33) |
| F3 | [#29](https://github.com/northcutted/clearcutt-factory/issues/29): refused rebase keeps the old build image | Confirmed in phase 1; [PR #30](https://github.com/northcutted/clearcutt-factory/pull/30) |
| F4 | [#13](https://github.com/northcutted/clearcutt-factory/issues/13): cross-repository fleet notification | [PR #36](https://github.com/northcutted/clearcutt-factory/pull/36) (`images.yml` outputs, `notify.yml`, dispatch in `init`) |
| F5 | [#14](https://github.com/northcutted/clearcutt-factory/issues/14): share one org profile across repositories | `signing.trustPolicy` in v0.1.1; publishing and extending a signed profile in [PR #50](https://github.com/northcutted/clearcutt-factory/pull/50) (used by the bring-up) |
| F6 | [#15](https://github.com/northcutted/clearcutt-factory/issues/15): a push before the pin PR merges can move `latest` back | Reproduced in phase 1; [PR #32](https://github.com/northcutted/clearcutt-factory/pull/32) (unchanged source), [PR #45](https://github.com/northcutted/clearcutt-factory/pull/45) for changed source ([#35](https://github.com/northcutted/clearcutt-factory/issues/35)) and fleet races ([#37](https://github.com/northcutted/clearcutt-factory/issues/37)) |
| F7 | [#16](https://github.com/northcutted/clearcutt-factory/issues/16): attest the second-runner reproduction | [PR #36](https://github.com/northcutted/clearcutt-factory/pull/36) (`reproduction/v1` predicate) |
| F8 | [#17](https://github.com/northcutted/clearcutt-factory/issues/17): GitHub App credentials for the reusable workflows | [PR #36](https://github.com/northcutted/clearcutt-factory/pull/36) |
| F9 | [#38](https://github.com/northcutted/clearcutt-factory/issues/38): non-root build images break app builds | [PR #46](https://github.com/northcutted/clearcutt-factory/pull/46) |
| F10 | [#39](https://github.com/northcutted/clearcutt-factory/issues/39): a rebased image never equals a rebuild of its lock | [PR #47](https://github.com/northcutted/clearcutt-factory/pull/47) |
| F11 | [#40](https://github.com/northcutted/clearcutt-factory/issues/40): BuildKit config and network | [PR #48](https://github.com/northcutted/clearcutt-factory/pull/48) |
| F12 | [#41](https://github.com/northcutted/clearcutt-factory/issues/41): one signing key per profile | [PR #48](https://github.com/northcutted/clearcutt-factory/pull/48) (`signing.stackKey`, `stack push --key`) |
| F13 | Trust-policy `key:` paths relative to the policy file | [PR #33](https://github.com/northcutted/clearcutt-factory/pull/33) |
| F14 | [#42](https://github.com/northcutted/clearcutt-factory/issues/42): factory's own files in the app's build context | [PR #46](https://github.com/northcutted/clearcutt-factory/pull/46) |
| F15 | [#43](https://github.com/northcutted/clearcutt-factory/issues/43): cosign 3 deprecates `--tlog-upload` | [PR #48](https://github.com/northcutted/clearcutt-factory/pull/48) (signing-config docs, `tlog: false`) |
| F16 | [#44](https://github.com/northcutted/clearcutt-factory/issues/44): `stack push` re-signs unchanged stacks | [PR #48](https://github.com/northcutted/clearcutt-factory/pull/48) |

## clearcutt-verify

| Plan | Issue | Status |
|---|---|---|
| V1 | [#48](https://github.com/northcutted/clearcutt-verify/issues/48): trust policy for reusable-workflow signers | Done (v0.15.0); hardened in [PR #69](https://github.com/northcutted/clearcutt-verify/pull/69) |
| V2 | [#49](https://github.com/northcutted/clearcutt-verify/issues/49): verify factory evidence | Done (v0.15.0); content read only from verified statements in [PR #69](https://github.com/northcutted/clearcutt-verify/pull/69) |
| V3 | [#50](https://github.com/northcutted/clearcutt-verify/issues/50): enumerate GHCR through the GitHub Packages API | Done (v0.15.0) |
| V4, V5 | [#51](https://github.com/northcutted/clearcutt-verify/issues/51): stacks as entities; dependents output | Done (v0.15.0) |
| V6 | [#52](https://github.com/northcutted/clearcutt-verify/issues/52): run in GitHub Actions | Done (v0.15.0); SHA-pinned action installs its own release in [PR #69](https://github.com/northcutted/clearcutt-verify/pull/69) |
| V7 | [#70](https://github.com/northcutted/clearcutt-verify/issues/70): read factory's reproduction attestations | [PR #71](https://github.com/northcutted/clearcutt-verify/pull/71) |
| V8 | Key-signed evidence without a transparency log | [PR #71](https://github.com/northcutted/clearcutt-verify/pull/71) (`tlog: false`) |
| V9 | Trust-policy `key:` paths | [PR #69](https://github.com/northcutted/clearcutt-verify/pull/69) |
| V10 | An upstream base steals every app's base edge | [PR #71](https://github.com/northcutted/clearcutt-verify/pull/71) (nearest base wins) |
| V11 | Rebased apps lose their stack | [PR #71](https://github.com/northcutted/clearcutt-verify/pull/71) |
| V12 | `--reproduce` with key signers | [PR #69](https://github.com/northcutted/clearcutt-verify/pull/69) |

## clearcutt-portal

| Plan | Issue | Status |
|---|---|---|
| P1 | Build from a report bundle plus history | Done |
| P2 | GitHub Pages action | Done (v0.1.0) |
| P3 | [#5](https://github.com/northcutted/clearcutt-portal/issues/5): copy-paste verify commands | [PR #8](https://github.com/northcutted/clearcutt-portal/pull/8), [PR #9](https://github.com/northcutted/clearcutt-portal/pull/9) |
| P4 | Base graph | Done |
| P5 | [#6](https://github.com/northcutted/clearcutt-portal/issues/6): package search by version range | [PR #8](https://github.com/northcutted/clearcutt-portal/pull/8) |
| P6 | [#7](https://github.com/northcutted/clearcutt-portal/issues/7): compare runs, per image | [PR #8](https://github.com/northcutted/clearcutt-portal/pull/8); CVE IDs fixed per run in [PR #9](https://github.com/northcutted/clearcutt-portal/pull/9) |
| P7 | Show stacks, `packagesSource`, per-image history | [PR #4](https://github.com/northcutted/clearcutt-portal/pull/4) |

## Found while preparing the bring-up

| Plan | Owner | Gap | Status |
|---|---|---|---|
| F17 | factory | `fleet.yml` and `update-locks.yml` couldn't open a pull request for a manifest at the repository root (branch `factory/rebase/.` is not a valid ref) | Fixed in v0.2.0 ([#51](https://github.com/northcutted/clearcutt-factory/issues/51): `factory/rebase/root-app`). The bring-up keeps each app in a subdirectory anyway |
| V13 | factory, verify | `required: [provenance]` failed every rebased image, which had a rebase record but no SLSA provenance | Fixed in factory v0.2.0 ([#52](https://github.com/northcutted/clearcutt-factory/issues/52): `fleet.yml` attests provenance for rebased images); the estate policy requires provenance again |

## Found in the CVE drill on GitHub (2026-10-17)

Details in [`bringup/DRILL-RESULTS.md`](../bringup/DRILL-RESULTS.md).

| Owner | Issue | Status |
|---|---|---|
| factory | [#57](https://github.com/northcutted/clearcutt-factory/issues/57): a refused rebase's rebuild pull request is titled "Pin … to the newest run image", like a routine pin | Fixed in v0.3.0 ("Rebuild … on the newest run and build images") |
| factory | [#60](https://github.com/northcutted/clearcutt-factory/issues/60): `notify` waits for the second-runner reproduction (about 2m20s) | Fixed in v0.3.0 (`images.yml` `reproduce: false` and `published`); the showcase calls it twice |
| factory | [#59](https://github.com/northcutted/clearcutt-factory/issues/59): releasing a hold re-resolves every package of the image | Fixed in v0.3.0 (`lock --update-package`); `drill-github.sh` uses it |
| factory | [#55](https://github.com/northcutted/clearcutt-factory/issues/55): the platform can't extend the profile it publishes | Fixed in v0.3.0 (`extends: {path: …}`); the platform uses it |

## Upstream (not filed)

W1 (grype matches nothing for Wolfi's `openssl-4.0-*` packages or for libxml2
2.13.x) belongs to Wolfi's advisories and grype's matching. The drill works
around it (see FINDINGS.md).

## From the second assessment (2026-10-18)

The plan is [`assessment.md` §4](assessment.md#4-the-plan). Phases A–D are
being worked as one pull request per repository and phase:

| Phase | Repository | Pull request | Status |
|---|---|---|---|
| A | clearcutt-verify | [#74](https://github.com/northcutted/clearcutt-verify/pull/74) | Merged 2026-10-18: #1, #2, #6, #8, #9 fixed; "couldn't check" is `unknown`; `metadata.platforms`; rebase-record tests read; real-cosign `cosign-e2e` job |
| A | clearcutt-factory | [#63](https://github.com/northcutted/clearcutt-factory/pull/63) | Merged 2026-10-26: #3, #4, #5, #10, workflow hardening (actionlint + zizmor), `.gitignore`/`.dockerignore`, real-cosign `cosign` job, attestation healing (Phase B). **Showcase follow-up at the next factory release:** re-render every apk image's Containerfile (`clearcutt-factory render`), which gives each a new digest once; `publish-ref` is not needed (the default branch publishes); the trust policy already names `sourceRef` |
| A | showcase | this repository | Done: trust policy from the signed profile (#7); status tables retired; demo commands fixed; Dependabot and a read-only workflow token in every repository |
| B | clearcutt-verify | [#76](https://github.com/northcutted/clearcutt-verify/pull/76) | Merged and **released as v0.17.0** 2026-10-26, after an independent review whose six bugs were fixed in the PR: `--rescan` (grype over verified SBOMs, gating on the worse scan), per-image VEX, observe-only tier, stable IDs, staleness from claims, `sourceRepositoryOwner`, the `estate` signer role, the contract gate, and the new-bundle-format failure (Sigstore's trusted root fetched once per run). **Live 2026-10-26 22:41 UTC:** the estate pins v0.17.0, rescans all 9 images (0 unknown), checks the pulled bundle's signature, and sets `maxScanAgeDays: 7`; 9 of 9 verified |
| B | clearcutt-factory | [#69](https://github.com/northcutted/clearcutt-factory/pull/69) | Review fixes pushed at `f71db3a`; fresh CI pending (real-Cosign, tests and lint passed; build/reproduction jobs running). Fixed malformed VEX scope widening, shared-input/deletion build selection, auto-merge ordering, re-attestation self-trust, and Cosign dropping VEX/SBOM metadata. Phase B includes: build-image event, stacks by digest, `reattest`, image-scoped VEX matching verify's rule, `auto-merge`, changed-only pull-request builds (each lock PR builds only its own image, so a gate failure that spans images no longer deadlocks them) |
| B | showcase | — | VEX statement and finding owners written (`platform/org/vex/`, platform README); the automated drill waits for factory B and releases |
| C | all | [verify #77](https://github.com/northcutted/clearcutt-verify/pull/77) | In progress: evidence readers, OpenVEX 0.0.1 and stricter CI landed on the PR branch; a reproduced Trivy false-clean coverage bug was fixed at `f29e9d4` (local vet/race passed). Still pending: `policy init`, progress, timeouts, cache, Notation verification and attested VEX attribution. Done so far: [start-here.md](start-here.md), [trust-model.md](trust-model.md), organization-ready bring-up (rehearsed). Factory C queued: `app.yml` + `init --platform/--app/--estate`, `doctor`, owner-scoped trust and registry federation |
| D | clearcutt-portal | [#10](https://github.com/northcutted/clearcutt-portal/pull/10) | Merged 2026-10-18: fix-first view, findings pages, lists, contract warnings and gate, history windowing, 500-image budget, Playwright + axe, signed `bundle-ref`, one version input |
| D | clearcutt-portal | [#11](https://github.com/northcutted/clearcutt-portal/pull/11) | Merged 2026-10-26 after CI passed at `955f59e`: Verify v0.17.0 contract, publisher/fresh scans, visible suppressions, observe-only, provenance and platform coverage, and rescan/observe-only history. **Release v0.2.0 prepared in [#12](https://github.com/northcutted/clearcutt-portal/pull/12)** at `27bd160`; release-tag publication waits for that exact head's CI and merge |

## Seen live while Phases A–D were in progress (2026-10-26)

Three of the assessment's claims happened on the live showcase by themselves,
a week after Phase A started. Recorded here as evidence.

**How the loop closed (2026-10-26, UTC).** The six pin pull requests could not
be green one at a time (each PR builds all six images, five of them still on
the vulnerable brotli), so they were combined into one
([platform #15](https://github.com/northcutted/clearcutt-showcase-platform/pull/15)).
Merged **02:27**. The platform rebuilt all six images, signed, attested,
reproduced on a second runner, published stacks and the profile, and notified
the apps: done **02:38**. Each app's fleet rebased it onto its new run image
and signed the rebase: checkout, catalog, and storefront all at **02:38–02:39**.
The estate re-verified on the `estate-changed` dispatch at **02:41**: 9 of 9
images verified, no brotli finding, catalog's scan verified again (the new
rebase record and attestations replaced the ones cosign could not read).
**Fourteen minutes from merge to a green estate, with no human step after the
merge.** What still needed a human: the merge itself (a week), and the "pin
to the newest run image" pull requests the fleets opened afterwards, which
wait again (checkout #9, catalog #7, storefront #8), as does a Dependabot
pull request in catalog (#8) that fails the gate only because its branch
still carries the old lock.

| What happened | Which gap | What it proves |
|---|---|---|
| A fixable **Critical, CVE-2026-111497 (brotli)**, reached Wolfi's `libbrotli*` after 2026-10-19. Every platform image build on a pull request from 2026-10-26 stops at the gate (`failOn: critical`, `onlyFixed: true`). The estate report shows **no** brotli finding: its scans are the ones attached at build time (2026-10-16/17). | Gap A (frozen scans) | The portal was green on a CVE the gate refuses. `estate verify --rescan` (verify Phase B) is the fix: live since 2026-10-26 (verify v0.17.0). |
| The weekly `update-locks` run of 2026-10-19 opened six pin pull requests (platform #8–#13). Nobody merged them for a week, so by 2026-10-23 every platform image was **11 days behind** the newest `wolfi-base` (`maxDaysBehind: 7`) and the estate went red: 7 of 9 images failed. The locks were re-resolved by hand on 2026-10-26 02:15 UTC (they now carry the brotli fix). | Automation needs no hands (Phase B: `auto-merge`) | A pin PR that waits for a human is a pin that never lands. The bot's pull requests must merge themselves once green. |
| Since 2026-10-23 catalog's vulnerability-scan attestation is reported **`failed`** ("not signed by a trusted signer") with the detail "cosign verify-attestation: trusted root is required when using new bundle format". The attestation is stored as OCI referrers (cosign v3's new bundle format), verifies locally with cosign 3.1.3, and the SBOM on the same image verifies in the same run. | "Couldn't check" ≠ "failed" (Phase A, verify #74, unreleased) and new-bundle-format handling (verify Phase B) | A tooling error read as "signed by someone untrusted". Fixed in verify v0.17.0 (live 2026-10-26): a lost trusted root reads `unknown`, and each run fetches Sigstore's trusted root once instead of every cosign process refreshing it at once. |
