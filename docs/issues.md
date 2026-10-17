# Issues filed for the showcase

Plan IDs are the ones in [plan.md §8](plan.md#8-what-each-tool-must-provide).
Phase 1 (the local prototype) found F9–F16, V8–V12, and P7; evidence and repro
steps are in [`prototype/FINDINGS.md`](../prototype/FINDINGS.md). Statuses are
as of 2026-10-16. "PR" means opened, not yet merged.

**Update 2026-10-17:** every pull request below is merged. clearcutt-factory
v0.2.0 and clearcutt-portal v0.1.0 are released; clearcutt-verify v0.16.0 is
at its release approval.

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
| P2 | GitHub Pages action | Done; usable by other repositories once v0.1.0 is released |
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
| factory | [#57](https://github.com/northcutted/clearcutt-factory/issues/57): a refused rebase's rebuild pull request is titled "Pin … to the newest run image", like a routine pin | Filed |

## Upstream (not filed)

W1 (grype matches nothing for Wolfi's `openssl-4.0-*` packages or for libxml2
2.13.x) belongs to Wolfi's advisories and grype's matching. The drill works
around it (see FINDINGS.md).
