# ClearCutt: assessment and next plan (2026-10-18)

A second, independent assessment of clearcutt-factory v0.3.0, clearcutt-verify
v0.16.0, clearcutt-portal v0.1.0, and the live showcase, written after all six
phases of [plan.md](plan.md) were done and the GitHub App was installed. It
follows a first assessment that concluded the platform is ready for an external
pilot. This one agrees on the design and the evidence, and disagrees on the
timing: the fixes below come first, because each is cheap and each contradicts
the project's own pitch.

Items marked **(checked)** were confirmed by reading the cited code. Items
marked **(read)** come from deep reads of each repository and were not
re-confirmed line by line; every one carries a citation to check.

## 1. Verdict

**The design is right and the drill proves the core loop.** Base update →
safe apps rebased in ~7 minutes with no app-team action → an unsafe app refused
with the exact reason and routed to a rebuild → every app patched in ~22
minutes → verified and published. Each of the three tools has a clear job, the
factory's error messages are unusually good, verify's "only read what cosign
verified" discipline is well designed, and the portal escapes everything and
keeps "unknown" honest.

**It is not yet ready for an outside team, for one reason: the pitch is
"honest about what it can prove", and in several places it isn't yet.** None
of these is exotic; a security-minded pilot would find at least one in its
first review, and that would cost more than the drill earned:

| # | Where | What | Status |
|---|---|---|---|
| 1 | verify | An **untrusted** rebase record makes a required `recipe` pass: any non-`missing` rebase status (including `failed`, `present`) sets recipe to `not-applicable`, and `not-applicable` satisfies `required` (`estateverify/build.go:693-697`, `policy.go:172-175`). An image can be `verified` on evidence nobody trusted. | checked |
| 2 | verify | A **non-grype scan reads as clean**: any JSON that unmarshals into `grypeResult` with zero matches (Trivy's cosign-vuln output, for one) passes `failOn` with zero findings (`estateverify/extract.go:62-79`). | checked |
| 3 | factory | **Tags move before signing**: `publish` pushes with tags, then signs; if cosign or Rekor fails, `latest` points at an unsigned image (`factory/build.go:398-421`). Builds heal on re-run; a rebase does not (it sees "already on the newest base" and returns before publish). `supersedes` is applied only on the already-exists path, so a re-run of an older job can move `latest` back, contradicting README "tags only move forward". | checked |
| 4 | factory | **Any branch can publish trusted images**: `PUSH: github.event_name != 'pull_request'` (`images.yml:106`) plus `workflow_dispatch`, and the verify block `init` writes has `sourceRepository` but no `sourceRef` (`init.go:229-235`). The showcase's own `trust.yaml` adds `sourceRef: refs/heads/main`; `init` users don't get it. | checked |
| 5 | factory | **`requireNonRoot` is bypassable** and the Containerfile is injectable: `USER %s`, `WORKDIR %s`, env keys, and the oci tool's paths are printed unescaped (`render/render.go:351,354`), and policy checks the raw string, so `user: "65532\nUSER 0"` passes (`policy/policy.go:21-26`). The heredoc delimiter is the fixed string `FACTORY_EOF` (`:192,613`). | checked |
| 6 | verify | **`estate pull` never verifies the bundle's signature**; it checks only the config media type (`estate/estate.go:200-201`), though the estate workflow signs every push (`estate.yml`). | checked |
| 7 | showcase | **The estate's trust policy comes from an unpinned checkout of the platform's `main`** (`estate.yml:48-55`), while factory reads the same policy from the signed profile. Two delivery paths for "one trust policy", one of them unsigned. | checked |
| 8 | verify | **`GITHUB_TOKEN` is offered to any registry** named in `estate push/pull/history` and `evidence *` (`commands/shared_helpers.go:12-16`), contradicting `registryauth.go:12-13` ("never offered to any other registry"). | checked |
| 9 | verify | **Any read error resets the history**: `estate push` starts an empty index on any error from `remote.Index`, 401/429/5xx included, then overwrites the tag (`estate/history.go:90-92`). | checked |
| 10 | factory | **apk packages are pinned by version only** at build (`render.go:328-342`); the lock's checksum is never enforced, though README says "pinned by version and hash". verify's reproduction would catch a drift; the build won't. | checked |

And two the first assessment named as strengths that need qualifying:

- "The verdict logic's discipline gives the results credibility" — the
  invariant "unknown never passes" is what #1 and #2 break, and neither case
  has a test. Every cosign interaction in verify's tests is a fake; CI never
  runs real cosign against real bundles. The same is true in factory.
- "Zero open issues" across three repos means one person files and fixes
  them. It is not a quality signal. verify v0.16.0 rewrote the trust core two
  days ago; it is the newest code in the project.

## 2. Three structural gaps

These are not bugs; they are places where the system doesn't do what an
operator would assume it does.

**A. The vulnerability picture is frozen at build time (checked).** verify runs
no scanner. It reads the grype report factory attached when the image was
built (`extract.go:16-79`) and nothing else. The estate runs daily, so an
operator sees a fresh report date on a scan that is as old as the image. The
portal does show scan age on the image page, but the overview does not. Today
the live estate's oldest scan is 27 hours old; in a month it would be a month.
factory's README documents "rescanning is not built in yet" (README:590); the
consequence for verify's daily run is not documented anywhere. This is the gap
a pilot would hit first: the next CVE after their build.

**B. A toolchain CVE has no fast path (checked).** `notify.yml` announces
every `kind: image` publish as `clearcutt.run-image-published`
(`notify.yml:112-116`); there is no build-image event. The fleet only rebases
onto run images. Stacks name their images by tag (`manifest/stack.go:188-192`),
so a rebuilt build-go with the same tag leaves the stack artifact unchanged
and no stack event fires either. So a CVE in Go's standard library, npm, or
pip reaches the apps at the Monday lock update. The drill planted its CVE in
the run image, which is the path that works. Also: a CVE in an app's own
dependencies (`go.sum`, `package-lock.json`) is outside factory entirely, and
no template sets up Dependabot or Renovate.

**C. Adoption costs ~30 files and ~33 settings, and verify's reach is narrower
than its pitch (read).** From `bringup/repos/`: 30 files, ~930 non-comment
lines, ~600 of them workflow YAML; 36 `@<FACTORY_REF>` pins across 8 files
with no Dependabot config; each app repo carries a byte-identical 95-line
`factory.yml` with a 31-line inline job that mints an App token and dispatches
to a hard-coded estate repo. Settings: ~6 per repo × 5, plus the App, plus 14
package-visibility changes that are web-only. Adding a fourth app means a
platform PR, a profile republish, and a lock-update PR in every existing app,
because trust is one signer per repository. On the verify side, the "entry
point for teams that didn't build with factory" reads only cosign v2 tags and
Sigstore bundles with grype inside; Notation signatures (ACR, Harbor, ECR),
buildx attestation manifests, and cosign `.sbom` tags are not read, so a team
with existing evidence sees `missing` and `failed`.

## 3. Per-tool findings

### clearcutt-factory (v0.3.0; ~13.4k LOC, ~7.7k test LOC, 130 tests)

Beyond #3, #4, #5, #10 above (read unless marked):

- Attestations can stay half-attached: the "already published" check looks
  only for the recipe/rebase predicate, so a failure after it leaves SBOM/vuln
  attestations missing forever (`build.go:386,429-471`). `result.json` is
  written only at the end, so that image is never reproduced or notified.
- A hand-edited lock goes undetected: `loadLocked` checks `inputsDigest` and
  the profile pin only; refs, URLs and sha256s are read from the lock
  (`factory.go:93-105`, `render.go:280,212,446`). Stacks and profiles have this
  protection; locks don't.
- Policy holes: `allowedHosts` skips apk (`policy.go:57-67`); `from: build`
  has network access with no policy switch; `build --push --no-scan` is
  accepted; `allowedRegistries` is a string prefix (`ghcr.io/acme` matches
  `ghcr.io/acme-evil`, `policy.go:117-121`).
- Rebase check misses whiteouts against the new base (`rebase/check.go:82-89`).
- Lock written before render validates; neither write is atomic
  (`factory.go:181-186`, `lock.go:225-227`).
- Workflows: all third-party actions SHA-pinned, but `setup-qemu-action` pulls
  `tonistiigi/binfmt:latest` unpinned and privileged; `${{ matrix.* }}` in
  `run:` at `images.yml:162,175`, `fleet.yml:165,281`, `update-locks.yml:138`;
  no `persist-credentials: false`; no `timeout-minutes`; no actionlint/zizmor
  in CI. The smoke container has default networking (`smoke.go:92-105`), which
  matters on self-hosted runners.
- Untracked files land in the signed recipe: context copying honours `.git`
  and `/out` but not `.gitignore`/`.dockerignore` (`render.go:502`), and the
  recipe embeds contents ≤2 MiB (`attest.go:48,205-251`). A local `build
  --push` can publish a stray `.env`.
- UX: no `doctor`; every flag has an empty help string; unknown flag prints
  usage twice (`main.go:80,98`); nothing records which factory version wrote a
  lock, so a local/CI version mismatch produces cryptic `KnownFields` errors.
- `internal/diff` (explains reproduction mismatches) has zero tests;
  `internal/container` and `cmd/` likewise.

### clearcutt-verify (v0.16.0; ~13.1k LOC, ~8.7k test LOC, 87% coverage)

Beyond #1, #2, #6, #8, #9 above:

- "Couldn't check" is reported as "failed": a missing cosign, no network, or
  cosign v2 facing v3 bundles comes out as "not signed by a trusted signer"
  (`verify.go:105-111,418-424,786-791`). No `LookPath`, no version check.
- A partially read platform list still gets a verdict (`build.go:279-281`);
  `--platforms` is not recorded in the report.
- `maxDaysBehind` uses drift from non-proof bases, and for label/history edges
  the graph picks the oldest observed version (`graph.go:529-540,612-628`), so
  a claim can manufacture staleness.
- `--reproduce` can skip an image whose recipe/rebase status is `unknown`
  (`build.go:924-926`, `policy.go:241`).
- Image IDs are neither stable nor unique (base name + tag; collision suffix
  depends on input order; `import.go:121-127,177-192`), though the contract
  promises both (`contract/README.md:107`). The portal rejects duplicate IDs.
  This breaks compare-runs.
- `platforms: null` when `remote.Get` fails violates the schema
  (`build.go:233-236`); the portal calls `.find` on it.
- Non-determinism: `reproducibility.checkedAt` is wall-clock even with
  `--generated-at` (`build.go:959`); raw registry/cosign errors land in
  `detail`.
- No timeouts on cosign subprocesses, factory rebuilds, or GitHub API calls;
  no cross-run caching; nothing incremental. Rough cost: tens of seconds per
  attested image at concurrency 4.
- Rebased images show `tests: missing` though factory v0.2.0 now writes
  `test` into the rebase record (`build.go:195-198`; factory CHANGELOG). Live
  now: storefront on the public portal. **(checked)**
- SLSA provenance "verification" is a signature check plus reading the source
  URL and commit; builder ID, buildType and materials are never evaluated
  (`extract.go:394-436`). Not documented.
- v0.16.0 changed what verdicts mean under `clearcutt.dev/v1` (no trusted
  signer: `verified` → `unverified`); the contract says a change of meaning
  needs v2. Nothing would catch this.
- `--verbose`, `--quiet`, and `--format` on `estate verify` are never read.
- CI doesn't run `-race` though `Build` is concurrent; no staticcheck,
  no govulncheck. The fallback-tag discovery path (registries without the
  Referrers API) is uncovered.

### clearcutt-portal (v0.1.0; ~4.2k LOC, ~2.2k test LOC, 151 tests)

- No "fix first": tiles aren't links; failures aren't grouped by reason (200
  images with one cause give 200 cards); no CVE → affected-images page; the
  images table isn't sortable; findings sort by severity then ID, not
  fixable-first; CVE IDs don't link out. The live page says "Every image meets
  every requirement" while 6 bases are stale and 6 Highs exist.
- Contract gating is a weekly byte-diff against verify's latest release
  (`contract-upstream.yml`): a breaking change ships first and is noticed up
  to 7 days later; unknown fields in a newer report are dropped silently.
- Bugs: `entries: []` crashes the history page (`history.astro:85`); a large
  `sourceDateEpoch` throws a RangeError (`images/[id].astro:127`); runs sort
  by `localeCompare` on RFC 3339 strings (`estate.ts:222`), so offsets or
  fractional seconds misorder "latest"; the "Reproduced" tile is green when
  zero images were reproduced (`index.astro:66-71`).
- Scale: no pagination; history is unbounded upstream (12 entries in 37
  hours on the showcase) and comparison output grows O(H²)
  (`timeline.ts:290-297`); `imageRuns` is O(images² × history).
- Accessibility: light-theme status glyphs at 2.1–2.6:1 (`global.css:477-489`);
  status cells not focusable; no browser or axe tests.
- Deployment: version passed twice (`@ref` and `portal-version`); the portal
  never checks the bundle's signature; docs recommend tag pins while the repo
  SHA-pins everything else.

### The showcase and its docs

- Status tables contradict each other: `plan.md:294-309` shows F3/F5/F6 open
  and F9–F11 "to file"; `issues.md` says all merged. `FINDINGS.md`'s summary
  was never updated. `demo-script.md:33-38` has commands against
  `ghcr.io/clearcutt-showcase/…`, which doesn't exist.
- No "start here" for an adopter; the trust model is spread over six places.
  The verdict vocabulary differs by tool (verify: `verified/failed/unverified`
  for images, `proof/declared/assisted/weak` for bases, `verified/present/…`
  for evidence; portal: proven/claimed/unknown); the showcase defines none.
- The drill did not exercise: a CVE in an app's own dependencies; a toolchain
  CVE (gap B); a Critical that fails the gate, or VEX (planned, no `vex/`
  dir exists); a bad signature or forged dispatch; a rollback; the fully
  automated path (App + v0.3.0 together).
- Two Criticals with no recorded fix are silently passed by `onlyFixed: true`;
  five fixable Highs in build-node have no owner.
- `bringup.sh` sets `can_approve_pull_request_reviews=true` on every repo
  though the App makes it unnecessary; `create-app.html` works only for a
  personal account.
- The upstream `wolfi-base` is left out of the inventory because it would
  "fail the policy forever"; there is no observe-only tier.
- W1 (grype blind to Wolfi's `openssl-4.0-*` and libxml2 2.13.x) is not
  filed upstream.
- The local prototype is frozen at pre-v0.2.0 shapes (custom BuildKit image,
  second profile for stack signing) and checks a different policy than CI.

## 4. The plan

Five phases, in order. A is a gate for anything public. B closes the two gaps
a pilot would hit in its first month. C is the cost gate; D the value gate; E
is the test. Sizes: S ≤ 1 day, M ≤ 1 week, L > 1 week, for one person.

### Phase A: make the claims true (~2 weeks)

Each item is done when the cited code path has a test that fails before and
passes after.

| Repo | Item | Size |
|---|---|---|
| verify | #1: recipe is `not-applicable` only when the rebase record is `verified`. Add adversarial table tests for every evidence kind × status (`failed`, `present`, `unknown` must never satisfy `required`). | S |
| verify | #2: parse only grype (require a `matches` key or a grype scanner URI); anything else goes to `unreadableScans`. Document grype-only. | S |
| verify | "Couldn't check" ≠ "failed": `LookPath` + version check for cosign; classify exec/network errors as `unknown`; partial platform read → `unknown`; record `--platforms` in the report. Exit 1, not 2, when tooling is missing. | M |
| verify | #8: scope env tokens to their registry (`GITHUB_TOKEN` → ghcr.io only). #9: start a new history index only on a confirmed not-found; check the existing index's kind. | S |
| verify | #6: `estate pull` verifies the bundle's signature against a signer (flag or policy). | S–M |
| verify | Read the `test` field factory writes into rebase records; rebased images stop showing `tests: missing`. | S |
| factory | #3: publish by digest → sign → attach every attestation → only then `TagIf` the tags. Treat "missing any signature or attestation" as unpublished. Apply `supersedes` on fresh pushes too. Make rebase check the current image is signed before "nothing to do". | M |
| factory | #4: push only when `github.ref` is the default branch (or a `publish-ref` input); `init` writes `sourceRef: refs/heads/main`. | S |
| factory | #5: validate `user`, `workdir`, env keys, oci paths (no whitespace/newlines); random heredoc delimiter; render fuzz test. | S |
| factory | #10: enforce apk checksums at build, or correct the README. Close the policy gaps: `allowedHosts` for apk repos; a policy switch for `from: build`; refuse `--no-scan --push` under a shared profile; `allowedRegistries` as path-segment match. | S–M |
| factory | Workflow hardening: pin the binfmt image; `persist-credentials: false`; every expression through `env:`; `timeout-minutes`; actionlint + zizmor in CI. | S |
| factory | Honour `.gitignore`/`.dockerignore` when copying the app context. | S |
| both | Real-cosign E2E in CI (one job that signs with a key, attests, and verifies real bundles) so a cosign format change can't pass unnoticed. | M |
| showcase | #7: read the estate's trust policy from the signed profile (or pin the checkout by SHA and verify it). | S |
| showcase | Retire the stale status tables in `plan.md`, `FINDINGS.md`, `issues.md`, `bringup/README.md`; fix `demo-script.md`'s commands. | S |

### Phase B: close the structural gaps (~3 weeks)

| Repo | Item | Size |
|---|---|---|
| verify | **Gap A:** `estate verify --rescan` runs grype over each image's *verified* SBOM. Report both: the attested scan (claimed, with its date) and the fresh scan (proven, today). `maxScanAgeDays` becomes meaningful. The portal shows both and the overview shows the oldest scan age. | M |
| factory | **Gap B:** a `clearcutt.build-image-published` event from `notify.yml`. `fleet.yml`/`update-locks.yml` react by re-locking the app's build image and opening a rebuild PR titled as such. Stacks reference images by digest (tag kept for display), so a stack's content changes when its images do and `stack-published` fires. | M |
| factory | A scheduled `reattest` reusable workflow: rescan the SBOM, re-attest, and re-run reproduction for images that have no verified reproduction, not only "newly published" ones (`images.yml:374-384`). | M |
| factory | Attestation healing: "already published" means signed *and* every attestation attached. `result.json` written incrementally. | S |
| showcase | Add a VEX directory and one documented suppression; set an owner for build-node's npm Highs; add an observe-only tier for `wolfi-base`; file W1 upstream. | S |
| showcase | **Re-run the drill, fully automated** (App, v0.3.x, auto-merge on), with: a toolchain CVE (build-go), a CVE in an app's own dependency (Dependabot in the templates), a Critical + VEX, a forged `repository_dispatch`, a bad signature, and a rollback. Record timings for every act. | M |

### Phase C: cut the cost of adoption (~4 weeks)

| Repo | Item | Size |
|---|---|---|
| factory | One reusable `app.yml` (images + reproduce + fleet + update-locks + estate-changed as a notify target), so an app repo is `app.yaml` plus a ~15-line caller. `init --platform`, `--app`, `--estate` generate the three shapes the showcase hand-wrote. | M |
| factory | `doctor`: docker/podman, BuildKit, QEMU, syft, grype, cosign, registry push, App permissions, local-vs-workflow version. A `generator` field in the lock. | M |
| factory | Owner-scoped trust by default (`sourceRepositoryOwner`), so a new app needs no platform PR. Dependents by layer digest (`estate dependents`) instead of topic, so a publish wakes only the apps built on it. Dependabot config in every template for the factory/verify/portal pins. SHA-pinned callers supported in the identity regexp. | M |
| factory | OIDC-federated registry login in the workflows (ECR/GAR/ACR), not only username/password. | M |
| verify | Read Notation signatures, buildx attestation manifests, and cosign `.sbom` tags, at least as `present`. A Trivy parser. `policy init`. Progress output. | M |
| verify | Stable, unique image IDs from the full repository path; no null arrays; deterministic `checkedAt`; validate against the schema before writing. | S–M |
| verify | Timeouts on cosign, factory and GitHub calls; cross-run cache keyed by (digest, evidence-manifest digest); skip unchanged digests. | L |
| showcase | A GitHub-organisation bring-up actually run (not only rendered); the App-manifest form for orgs; stop setting the PR-approval permission when the App is present. | M |
| docs | One family-level **Start here** and one **Trust model** page: the signer chain as a table, the verdict glossary across all three tools, and "what `verified` does not prove" (scan age, `onlyFixed`, `/healthz` smoke tests, provenance content). Move the local loop to v0.3.x releases and document the app-developer loop against live stacks. | M |
| docs | A GitLab reference pipeline, or a plain statement of what's lost off GitHub and what replaces it. | L |

### Phase D: the portal answers "what do I fix first" (~2 weeks)

| Item | Size |
|---|---|
| Fix-first view: failures grouped by reason; a CVE → affected-images page, fixable Critical/High first, with package and advisory links; sortable images table; tiles link to filtered lists; a not-reproduced count; oldest scan age on the overview. | M |
| Contract gate: verify's PR CI runs the released portal's `check` and `build` on fresh output and on the previous release's fixtures; the portal warns at build time and in the footer on unknown fields or a newer generator; schema diff against the last tag. | M |
| Quick fixes: empty history; `sourceDateEpoch` range; sort runs by parsed time; "Reproduced" tile colour; stable comparison links; light-theme contrast; focusable status cells. | S |
| Scale: id → packages and id → history-row indices; window the history (last N runs/comparisons, or trim upstream); a synthetic 500-image / 1k-run build with a time budget. | M |
| Playwright + axe smoke tests for the client scripts. | S–M |
| Accept a signed `bundle-ref` OCI input and verify it; one version input; SHA-pin guidance; concurrency group. | M |

### Phase E: the pilot

One team that is not us, on their own registry, with images they didn't build
with factory. Measure: time to first useful report; number of assists; the
`doctor` findings; one real remediation cycle end to end; what they asked
that the docs didn't answer. Then decide whether factory is the next ask.

## 5. Why this order

- A before anything public, because every item in it is a sentence in the
  README that the code doesn't keep. They are all S–M; together they are two
  weeks.
- B before the pilot, because gap A (frozen scans) is what a pilot hits the
  first time a CVE lands after their build, and gap B (toolchain) is what they
  hit the first time it's in Go or npm. Both are the exact scenario the
  project exists for.
- C before the pilot, because at ~30 files and ~33 settings, a pilot measures
  friction, not value. The single app workflow and `doctor` remove most of it.
- D alongside C: the portal is where a non-expert decides whether this is
  useful, and today it says "all green" with six Highs showing.
- E last, and small: one team, verify first, factory only if asked.
