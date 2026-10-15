# Issues filed for the showcase

Plan IDs are the ones in [plan.md §8](plan.md#8-what-each-tool-must-provide).
Phase 1 (the local prototype) statuses are as of 2026-10-14; evidence and
repro steps for each are in [`prototype/FINDINGS.md`](../prototype/FINDINGS.md).

## clearcutt-factory

| Plan | Issue | Status |
|---|---|---|
| F1 | [#11](https://github.com/northcutted/clearcutt-factory/issues/11): reusable-workflow signatures don't match the identity `init` writes | Fixed in v0.1.1 |
| F2 | [#12](https://github.com/northcutted/clearcutt-factory/issues/12): `requireSignedStacks` uses the image signer | Fixed in v0.1.1; phase 1 used a separate stack key |
| F3 | [PR #30](https://github.com/northcutted/clearcutt-factory/pull/30): refused rebase keeps the old build image | **Confirmed in phase 1** on main; fix in PR #30 (open) |
| F4 | [#13](https://github.com/northcutted/clearcutt-factory/issues/13): cross-repository fleet notification | Prototype in showcase |
| F5 | [#14](https://github.com/northcutted/clearcutt-factory/issues/14): share one org profile across repositories | Proposal |
| F6 | [#15](https://github.com/northcutted/clearcutt-factory/issues/15): a push before the pin PR merges can move `latest` back | **Reproduced in phase 1** on main; fix in [PR #32](https://github.com/northcutted/clearcutt-factory/pull/32) (open) |
| F7 | [#16](https://github.com/northcutted/clearcutt-factory/issues/16): attest the second-runner reproduction | Proposal |
| F8 | [#17](https://github.com/northcutted/clearcutt-factory/issues/17): GitHub App credentials for the reusable workflows | Proposal |
| F9 | Not filed yet: non-root stack build images break app builds (`mkdir -p /out`, root-owned source and caches) | Found in phase 1 (High); worked around |
| F10 | Not filed yet: a rebased image never equals the rebuild of its pinned lock (base layer annotations) | Found in phase 1 (Medium) |
| F11 | Not filed yet: no BuildKit config or network for local or plain-HTTP registries | Found in phase 1 (Medium); worked around |
| F12–F16 | Not filed yet: one signing key per profile; trust-policy key paths; factory files in the app context; cosign 3 `--tlog-upload` deprecation; `stack push` re-signs unchanged stacks | Found in phase 1 (Low) |

## clearcutt-verify

| Plan | Issue |
|---|---|
| V1 | [#48](https://github.com/northcutted/clearcutt-verify/issues/48): trust policy for reusable-workflow signers (caller binding, signer roles) |
| V2, V7 | [#49](https://github.com/northcutted/clearcutt-verify/issues/49): verify factory evidence (recipe, rebase, CycloneDX, vuln, GitHub provenance, reproduction) |
| V3 | [#50](https://github.com/northcutted/clearcutt-verify/issues/50): enumerate GHCR through the GitHub Packages API |
| V4, V5 | [#51](https://github.com/northcutted/clearcutt-verify/issues/51): stacks as entities; dependents output for automation |
| V6 | [#52](https://github.com/northcutted/clearcutt-verify/issues/52): run in GitHub Actions (verified install, auth, history) |
| V8–V12 | Not filed yet (phase 1): key-signed evidence without a tlog can't be verified (V8); trust-policy key paths (V9); **an observed upstream base steals every app's base edge, so `estate dependents` is empty (V10, High)**; rebased apps lose their stack (V11); `--reproduce` and key signers (V12, unconfirmed) |

## clearcutt-portal

P1–P7 (plan §8) are not filed yet. Phase 1 built a site from a local report
bundle; P7 (pages for what verify's newer contract adds: stacks,
`packagesSource`, per-image history) is the gap it found.
