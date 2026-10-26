# ClearCutt trust model

One page for the question a security reviewer asks first: **who signs what,
who checks it, and what does a green result actually prove?** It covers the
three tools together, using the live showcase as the worked example
(`northcutted/clearcutt-showcase*`, images under
`ghcr.io/northcutted/clearcutt-showcase/`).

## 1. The signer chain

Every signature is a Sigstore keyless signature made by a GitHub Actions
workflow run: its identity is the workflow file at a ref, and its
certificate also names the repository and ref the run belongs to. Nothing in
the chain uses a long-lived key.

| Artifact | Signed by (certificate identity) | Bound to | Checked by | Where that trust is written |
|---|---|---|---|---|
| clearcutt-factory, -verify, -portal releases | each tool's own release workflow | the tool's repository, a release tag | each tool's GitHub Action, before it runs the binary (`cosign verify-blob` with the release's Sigstore bundle, plus `SHA256SUMS.txt`) | the actions themselves |
| Platform images (`platform/{build,run}-*`) | factory's reusable `images.yml` (built) or `fleet.yml` (rebased), **at a release tag** | the run's repository (`sourceRepository`: the platform repository), its ref (`sourceRef: refs/heads/main`), and the image's own `org.opencontainers.image.source` label (`sourceMatchesImage`) | factory, wherever a stack or app uses the image; verify, for the estate | `org/trust.yaml` in the platform repository, signer `platform-images` |
| App images (`apps/{checkout,catalog,storefront}`) | the same reusable workflows | the app's own repository, `main`, its source label | factory (reproduce, fleet); verify | `org/trust.yaml`, one signer per app repository |
| Stacks (`stacks/{go,python,node}:1`) | the platform's own `stacks.yml` on `main` | — (the identity is the platform's workflow) | factory, every time an app builds or rebases (`requireSignedStacks`) | `org/trust.yaml`, signer `platform-stacks` (role `stack`) |
| The shared profile (`factory/org:1`: the profile, the trust policy, the VEX statements) | the platform's `profile.yml` on `main` | — | factory, every time an app repository loads its profile (`extends.signer`, at the digest the lock pins); the estate workflow, before it reads the trust policy out of it | each app's `factory.org.yaml` (`extends.signer`); the estate workflow (`PROFILE_SIGNER`) |
| SBOM, vulnerability scan, recipe, rebase record, reproduction | the same workflow run that signed the image (cosign attestations) | as the image | verify reads an attestation's content **only** after cosign verified it against a trusted signer | as the image |
| SLSA provenance | GitHub artifact attestations, made inside factory's reusable workflow | the app's repository | verify (signature, plus the source repository and commit it names); `gh attestation verify --repo … --signer-repo northcutted/clearcutt-factory` | — |
| The estate report bundle (`estate:latest`) | the showcase's `estate.yml` on `main` | — | `clearcutt-verify estate pull` refuses an unsigned or otherwise signed bundle (verify v0.17.0 and later) | the estate workflow's `estate pull` flags |
| `repository_dispatch` events between repositories | the GitHub App `clearcutt-showcase-bot` (short-lived installation tokens) | — | nothing needs to: a dispatch is only a hint. The receiver re-resolves tags from the registry and verifies every signature itself, so a forged dispatch can at most start a run that finds nothing new | the App's installation (five repositories) |

**One trust policy, one copy.** `org/trust.yaml` is the only place the
showcase says whom it trusts. factory reads it from the signed shared
profile; so does the estate workflow (it verifies the profile's signature,
then reads the policy out of it). No tool reads it from an unsigned checkout.

**Why one signer per repository, not per owner.** factory's reusable
workflows can be called by any repository on GitHub, so "signed by
`images.yml@v0.3.0`" alone proves nothing about *whose* image it is. Each
signer therefore also names the repository whose runs count, requires the
run to be on `main`, and requires the image to name that repository as its
source. A pull request branch, a fork, or another repository of the same
owner can call the same workflow and still produce nothing the showcase
accepts.

## 2. What each tool's words mean

The three tools report at different levels, so their vocabularies differ.
This is the whole glossary.

### clearcutt-verify: an image's verdict

| Verdict | Meaning |
|---|---|
| `verified` | Every requirement in the policy is met, by evidence a trusted signer vouched for. |
| `failed` | A requirement is not met: required evidence is missing or signed by someone else, or a gate (`failOn`, `maxDaysBehind`) fails on verified evidence. |
| `unverified` | A requirement couldn't be decided: evidence that couldn't be read or checked (a registry or Sigstore outage, an unreadable scan), or that no trusted signer vouched for. Never a pass. |

### clearcutt-verify: one piece of evidence

| Status | Meaning |
|---|---|
| `verified` | cosign verified it against a trusted signer; its content was read from the verified statement. |
| `present` | Found, but not verified (no trusted signer named it, or no way to check it). Its content is not used. |
| `failed` | Found, and signed by someone the policy doesn't trust, or its check failed. |
| `missing` | Not there. |
| `unknown` | Couldn't be read or checked. Never treated as zero or as a pass. |
| `not-applicable` | Doesn't apply to this image. Only one case satisfies a requirement: a rebased image has no recipe of its own, and its *verified* rebase record leads to the recipe of the image it was rebased from. |

### clearcutt-verify: how an image's base was found

| Strength | Rests on |
|---|---|
| `proof` | The image's first layers **are** the base's layers (layer digests compared). |
| `declared` | A digest the build stamped (`org.opencontainers.image.base.digest`, buildpacks metadata). Checked against the layers before it counts. |
| `assisted` | A base *name* the author wrote, without a version. |
| `weak` | The base repository appears in the build history. |

A base is `current`, `stale` (a newer version of it exists in the estate),
or `unknown`.

### clearcutt-portal

The portal shows verify's words, grouped into three colours: **proven**
(verified evidence, a base found by layer digests, a reproduced build),
**claimed** (something an author wrote, not checked), and **unknown**
(couldn't be decided). It never shows a claim as proof.

### clearcutt-factory

factory refuses rather than reports: a build that fails the vulnerability
gate (`failOn`), the policy (non-root, labels, allowed registries and
hosts), or a signature check on a stack or profile stops with an error that
names the field and the fix. A rebase that isn't safe (the new run image
lacks a library the app links, a file the app's layers delete) is *refused*
and becomes a rebuild pull request instead.

## 3. What `verified` does not prove

A `verified` image met the policy, on evidence a trusted signer vouched for,
**as of the evidence's own date**. It does not prove:

- **That the image has no vulnerabilities today.** The vulnerability scan is
  the one attached when the image was built or rebased. Unless the estate
  runs `estate verify --rescan` (verify v0.17.0 and later), a CVE published
  after that date isn't in it. `maxScanAgeDays` in the policy turns an old
  scan into `unverified`. The showcase doesn't set it yet: it will, together
  with `--rescan`, once verify v0.17.0 is released.
- **That there are no Critical vulnerabilities.** `onlyFixed: true` (the
  showcase's setting) gates only on findings with a fix available. Unfixed
  Criticals are reported, not gated.
- **That suppressed findings don't matter.** A VEX statement (`org/vex/`)
  removes a finding from the gate. The report shows which statement
  suppressed what; reviewing those statements is a human job.
- **That the app works.** factory's smoke test runs the image's declared
  test (in the showcase, the service starts and answers its health check).
  It is not a test suite.
- **What built the image, beyond its source.** For SLSA provenance verify
  checks the signature and reads the source repository and commit. It does
  not evaluate the builder ID, the build type, or the materials.
- **Anything about the app's own dependencies beyond the scan.** factory
  locks the OS packages and toolchains; the app's `go.sum`,
  `package-lock.json`, and `requirements.txt` are the app team's, kept
  current by Dependabot.
- **That the estate is complete.** verify reports on the references it was
  given (`estate/refs.txt`) or the namespace it enumerated.

## 4. Off GitHub

The CLIs (factory, verify, the portal's build) run anywhere. What the
showcase gets from GitHub specifically, and what replaces it elsewhere:

| On GitHub | What it gives | Elsewhere |
|---|---|---|
| factory's reusable workflows | the build, rebase, and lock-update pipelines, ready-made | write the pipeline yourself around the same CLI commands (`build --push`, `rebase`, `lock --update`, `verify --image`); factory ships no GitLab or Jenkins templates yet |
| Actions OIDC + Sigstore keyless | signatures bound to the workflow, repository, and ref | GitLab CI's `id_tokens` work with Sigstore keyless too (the certificate carries the project path and ref); or sign with a key (`signing.mode: key`, any cosign KMS URI) |
| GitHub artifact attestations (SLSA provenance) | build provenance from GitHub's attestation API | `cosign attest --type slsaprovenance` from your pipeline; verify reads cosign attestations |
| GHCR enumeration through the Packages API | `registry scan` of a namespace | any registry with `_catalog`, or a refs file |
| The GitHub App and `repository_dispatch` | cross-repository wake-ups | pipeline triggers or webhooks; the payload is only a hint either way |
| Dependabot | app dependency updates and security fixes | Renovate |
| GitHub Pages | hosting the portal | any static host (the portal's build is a plain static site) |
