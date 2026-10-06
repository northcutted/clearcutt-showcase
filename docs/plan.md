# ClearCutt showcase: plan

An organization that has adopted the whole ClearCutt family, running for real:

- a platform team that owns images, stacks, and policy;
- three app teams, each in its own repository and language;
- a security view of the whole estate.

It is also the first real cross-repository consumer of
[clearcutt-factory](https://github.com/northcutted/clearcutt-factory). Every gap
it hits becomes a focused fix upstream or an issue on the tool that owns it.

Status: **proposal**. Nothing has been created on GitHub yet. Open decisions
are collected in [§10](#10-decisions-needed).

## 1. Organization and repositories

Use a dedicated GitHub organization, **`clearcutt-showcase`** (the name is free;
Free plan, all repositories public). A dedicated org gives us:

- a clean registry namespace (`ghcr.io/clearcutt-showcase/…`);
- org-level secrets and Actions policy, instead of five copies;
- a realistic "an organization adopts ClearCutt" story;
- no mixing with your personal packages.

| Repository | Plays the role of | Contains |
|---|---|---|
| `platform` | Platform team, with security | The org profile (`factory.org.yaml`), build and run images per language, stacks, VEX statements, and workflows that publish images, push stacks, update locks weekly, and notify dependents |
| `checkout` | Payments team | A Go HTTP service on stack `go:1` |
| `catalog` | Catalog team | A Python HTTP service on stack `python:1`, with a small C extension that validates supplier XML feeds through libxml2 |
| `storefront` | Web team | A Node.js (TypeScript) HTTP service on stack `node:1` |
| `showcase` | Security / governance; also this plan | Docs, the demo script and drill drivers, the estate inventory and policy, the scheduled clearcutt-verify run, and the clearcutt-portal site on GitHub Pages |

This local repository becomes `clearcutt-showcase/showcase`.

## 2. Registry layout

```
ghcr.io/clearcutt-showcase/
├── platform/build-go      platform/run-go         # toolchain (stack build) and run images,
├── platform/build-python  platform/run-python     # one pair per language, tagged by line
├── platform/build-node    platform/run-node       # (run-python:3.14, run-node:24, run-go:1)
├── stacks/go:1  stacks/python:1  stacks/node:1    # signed stack artifacts; apps name these
└── apps/checkout  apps/catalog  apps/storefront   # app images (latest + digests)
```

Each package is linked to its repository through
`org.opencontainers.image.source` and inherits that repository's (public)
visibility.

- **Keep old run images.** A rebase needs the old base's manifest, so no
  package-cleanup policy.
- **Use line tags, not `latest`, on platform images.** Distribution or ABI
  lines get new tags and new stack majors, as factory recommends.

## 3. Images, stacks, and apps

All images are Wolfi-based, built for `linux/amd64` and `linux/arm64`, run as
non-root `65532`, and smoke-tested on both platforms. Shared settings live in
`images/_shared/{build,run}.yaml` and are applied with `extends:`.

| Image | Packages (beyond wolfi-base) | Notes |
|---|---|---|
| `build-go` | `go-1.27`, `git` | Stack build image. Cross-compiles. |
| `run-go` | `ca-certificates-bundle`, `tzdata` | Static Go binaries need nothing else. |
| `build-python` | `python-3.14`, `py3.14-pip`, `py3.14-setuptools`, `build-base`, `pkgconf`, `libxml2-dev` | Builds wheels and C extensions. |
| `run-python` | `python-3.14`, `ca-certificates-bundle`, `tzdata`, `libxml2` | `libxml2` is here because catalog asked for it. Anything an app needs from the OS goes in the run image. |
| `build-node` | `nodejs-24`, `npm` | |
| `run-node` | `nodejs-24`, `ca-certificates-bundle`, `tzdata` | |

| Stack | Build → run | Steps (in `/src`, output to `/out`) |
|---|---|---|
| `go:1` | `build-go` → `run-go` | `crossCompile: true`, `CGO_ENABLED=0`, `go build -trimpath …` (like factory's example) |
| `python:1` | `build-python` → `run-python` | `crossCompile: false` (runs under emulation). First `pip install --require-hashes --no-deps --no-compile --target /out/lib -r requirements.txt`, then `pip install --no-deps --no-build-isolation --no-compile --target /out/lib .`. Env `PYTHONPATH=/app/lib`, `PYTHONDONTWRITEBYTECODE=1`. Entrypoint `python3 -m {{name}}`. |
| `node:1` | `build-node` → `run-node` | `crossCompile: false`. Runs `npm ci`, `npm run build`, `npm prune --omit=dev`, then copies `dist/`, `node_modules/`, and `package.json` to `/out`. Entrypoint `node /app/dist/server.js`. |

| App | Language | Dependencies (all pinned by the app's own lockfile) | Smoke test |
|---|---|---|---|
| `checkout` | Go | stdlib `net/http`, plus a couple of modules (`go.sum`) | `http: {port: 8080, path: /healthz}` |
| `catalog` | Python 3.14 | Starlette and uvicorn (pure Python, `requirements.txt` with hashes), plus the `catalog._feeds` C extension linked against `libxml2.so.N`, which is imported at startup | `http: {port: 8080, path: /healthz}` |
| `storefront` | Node 24, TypeScript | Fastify (`package-lock.json`) | `http: {port: 8080, path: /healthz}` |

Each `app.yaml` is about ten lines: a stack reference, env, a smoke test, and
the source label. App sources stay well under the 2 MiB that factory embeds in
the recipe, so `verify --image` can rebuild apps from the signed recipe alone.

## 4. Signing and trust

| Artifact | Fulcio SAN (who signed) | Caller repository (Fulcio GitHub Workflow Repository) |
|---|---|---|
| Platform images | `northcutted/clearcutt-factory/.github/workflows/images.yml@refs/tags/v0.x.y` | `clearcutt-showcase/platform` |
| App images (built) | same as above | `clearcutt-showcase/<app>` |
| App images (rebased) | `…/clearcutt-factory/.github/workflows/fleet.yml@refs/tags/v0.x.y` | `clearcutt-showcase/<app>` |
| Stacks | `clearcutt-showcase/platform/.github/workflows/stacks.yml@refs/heads/main` | `clearcutt-showcase/platform` |
| SLSA provenance | GitHub artifact attestations (signer workflow: factory `images.yml`) | `clearcutt-showcase/<repo>` |

**Who signs, and why the caller repository matters.** Inside a reusable
workflow, the certificate's SAN names the *called* workflow (factory's
`images.yml`), not the caller. Anyone who calls factory's workflow gets that
same SAN. Trust therefore has to bind the caller repository too, through the
GitHub Workflow Repository or Source Repository Owner extensions.

**Factory today.** Factory v0.1.0 doesn't handle this. `init` writes
`certificateIdentityRegexp: ^https://github\.com/<caller>/`, which never
matches a reusable-workflow signature, with three consequences:

- `verify --image` fails in the second-runner and fleet jobs;
- `publish` can't see the existing attestations, so it republishes unchanged
  images on every run;
- `policy.requireSignedStacks` checks stacks against the same identity, so a
  stack signed by `platform` can't pass in an app repository.

See [§8](#8-what-each-tool-must-provide) (F1, F2).

**The org profile we want.** The platform team owns it. Each app repo carries a
copy until factory can reference a published one (F5):

```yaml
signing:
  mode: keyless
  verify:                      # this repository's images
    certificateIdentityRegexp: ^https://github\.com/northcutted/clearcutt-factory/\.github/workflows/(images|fleet)\.yml@refs/tags/v0\.\d+\.\d+$
    certificateOIDCIssuer: https://token.actions.githubusercontent.com
    githubWorkflowRepository: clearcutt-showcase/checkout   # F1 (today: args: [--certificate-github-workflow-repository, …])
  stacks:                      # F2: who may sign the stacks apps build on
    certificateIdentity: https://github.com/clearcutt-showcase/platform/.github/workflows/stacks.yml@refs/heads/main
    certificateOIDCIssuer: https://token.actions.githubusercontent.com
vulnerabilities: {scanner: grype, failOn: critical, onlyFixed: true}
policy:
  requireNonRoot: true
  requiredLabels: [org.opencontainers.image.source]
  requireSignedStacks: true
  allowTOFU: false
  allowedRegistries: [cgr.dev/chainguard/, ghcr.io/clearcutt-showcase/, docker.io/moby/, docker.io/docker/]
```

**Security team artifacts.** `platform/vex/` holds the security team's
OpenVEX triage, which factory applies to every scan.

**Unpinned workflows before a release.** Until fixes ship in a factory release,
the showcase pins factory's workflows and action by **commit SHA** (the action
builds from source at a non-tag ref). The identity regexp then also has to
accept `@<sha>`. I'll ask before cutting `v0.1.1`.

## 5. Automation

### Per repository

**`platform/.github/workflows/platform.yml`**
- On pull requests: factory `images.yml` builds, smoke-tests, scans, and gates.
- On `main`, `images.yml` pushes, signs, attests, adds provenance, and checks
  reproducibility on a second runner. Then:
  - `stacks`: `stack push` for each stack whose file changed, signed by this
    workflow's own identity;
  - `notify` (below).
- Separate caller jobs run factory `update-locks.yml` weekly, and on dispatch
  for the demo.

**App repositories (`checkout`, `catalog`, `storefront`): `factory.yml`**

| Trigger | What runs |
|---|---|
| Pull request | `images.yml` (gate) |
| `main` | `images.yml` (publish and reproduce), then `fleet.yml` |
| Weekly | `update-locks.yml` |
| Daily | `fleet.yml` |
| `repository_dispatch: clearcutt.run-image-published` | `fleet.yml` |
| `repository_dispatch: clearcutt.stack-published` | `update-locks.yml` |

`concurrency: fleet-${{ github.repository }}` serializes fleet runs, so a
dispatch and the daily run can't race on the same pin branch.

**`showcase/.github/workflows/estate.yml`**
- Triggers: daily, `repository_dispatch: clearcutt.estate-changed`, and manual.
- Runs clearcutt-verify over the inventory, which produces a report bundle.
- clearcutt-portal builds the site from that bundle and deploys it to Pages
  ([§7](#7-clearcutt-verify-and-clearcutt-portal-integration)).

### Cross-repository coordination

factory's `fleet.yml` only rebases apps in its own repository. The showcase
closes the loop:

```
platform main ──images.yml──▶ run-python@new published
      │ notify: read the result.json artifacts images.yml uploads; for each newly
      │ published run/build image or stack, find dependents and send
      ▼
POST /repos/clearcutt-showcase/<app>/dispatches  {event_type, client_payload:{image, digest}}
      ▼
<app> factory.yml ──fleet.yml──▶ rebase -f app.yaml --push --update-lock ──▶ pin PR (or rebuild PR)
      └─▶ dispatch clearcutt.estate-changed to showcase ──▶ verify + portal refresh
```

**Finding dependents.**
- **v1:** every repository in the org with the topic `clearcutt-app`. App teams
  opt in, and there's no central list to maintain.
- **v2:** clearcutt-verify's report. Images whose proven base (by layer digest)
  is the repository just published, mapped to their `source` repository (V5).
  Only real dependents are woken.

**Payloads are advisory.** Receivers re-resolve tags from the registry and
verify signatures, so a forged dispatch can only cause a no-op run.

**Upstream.** Once this works, propose it to factory (F4): `images.yml` outputs
or a `notify` reusable workflow, and `repository_dispatch` in the init
template.

## 6. Settings and secrets (I'll ask before each change)

| Where | Setting / secret | Why |
|---|---|---|
| Org | Create `clearcutt-showcase` | §1 |
| Org | Actions → workflow permissions: read by default; **allow GitHub Actions to create and approve pull requests** (repositories inherit it) | Weekly and fleet jobs open PRs |
| Org (or each repo) | Secret **`CLEARCUTT_BOT_TOKEN`**: a fine-grained PAT. Resource owner `clearcutt-showcase`; repositories `platform`, `checkout`, `catalog`, `storefront`, `showcase`; permissions **Contents: RW**, **Pull requests: RW** (metadata read is implied). An org secret scoped to those five repos is one secret instead of five. | PRs that start CI, plus `repository_dispatch` to other repos (which needs Contents: write on the target) |
| `platform`, `checkout`, `catalog`, `storefront` | Uses the secret above | Lock-update, pin, and rebuild PRs; dispatch |
| `showcase` | Uses the secret above (for dispatch-free reruns only); **Pages source: GitHub Actions** | Portal |
| App repos | Topic `clearcutt-app` | Dependents, v1 |
| Optional, later | Branch protection on `main` (require the `images` checks) and "Allow auto-merge" | Bot pin PRs merge themselves once green (see F6) |

GHCR needs no secret: workflows push with `GITHUB_TOKEN`, and public packages
need no read grant across repositories. If the org were private, each platform
package would need read access granted to each app repository.

## 7. clearcutt-verify and clearcutt-portal integration

clearcutt-verify is being renamed and its contract is still being written, so
this is designed now and built when they are ready.

**Inventory: `showcase/estate/estate.yaml`.**
- Sources: `ghcr.io/clearcutt-showcase/{platform,apps,stacks}/*` (enumerated
  through the GitHub Packages API, V3), plus the upstream
  `cgr.dev/chainguard/wolfi-base`.
- Several tags per base repository, so drift is measurable.

**Policy.**
- Trusted signers as in §4, bound to `clearcutt-showcase/*` callers (V1).
- Required evidence: signature, SBOM, vulnerability scan, provenance, and recipe
  (or a rebase record).
- `failOn: critical`, `onlyFixed: true`, `maxDaysBehind: 7`, `reproduce: true`.

**Run.**
- In `estate.yml` with the released, signature-verified clearcutt-verify (V6).
- Output: the versioned report bundle (`contract/` in clearcutt-verify).
- History persists as an OCI artifact at `ghcr.io/clearcutt-showcase/estate`,
  so each run appends without a git commit.

**Portal.** clearcutt-portal builds a static site from the bundle and deploys it
to `https://clearcutt-showcase.github.io/showcase/`.

**What the drill needs from them.**
- Package index: which images ship `libxml2 2.13.x` or the vulnerable OpenSSL,
  including those that only inherit it from their base.
- Base graph: run image → apps, proven by layer digest.
- Rebase records verified.
- History: before-and-after across the drill.

## 8. What each tool must provide

Issues are filed on the owning repositories; links are in [`issues.md`](issues.md).

**clearcutt-factory.** I may open focused PRs here.

| # | Gap | Kind | Status |
|---|---|---|---|
| F1 [#11](https://github.com/northcutted/clearcutt-factory/issues/11) | Reusable-workflow signatures carry factory's SAN. `init`'s identity never matches, which breaks `verify --image` (reproduce, fleet) and makes `publish` republish unchanged images. Needs the caller-repository binding (`githubWorkflowRepository`) and a correct `init` template. | bug | Confirmed in code. PR first. |
| F2 [#12](https://github.com/northcutted/clearcutt-factory/issues/12) | `requireSignedStacks` verifies stacks with the image identity. Stacks are published from another repository, so they need their own signer (`signing.stacks`). | gap | Confirmed in code. PR. |
| F3 | When a rebase is refused, `--update-lock` moves only the run image. The rebuild then uses the old build image and can link against libraries the new run image lacks (the drill's case). The rebuild PR should re-resolve the stack's build image too. | gap | Expected; confirm in the drill prototype, then PR. |
| F4 [#13](https://github.com/northcutted/clearcutt-factory/issues/13) | Cross-repository fleet: callers can't tell what `images.yml` published (no outputs), and nothing notifies dependents. | feature | Prototype in the showcase, then propose. |
| F5 [#14](https://github.com/northcutted/clearcutt-factory/issues/14) | One org profile shared across repositories (publish and reference it, signed, like stacks), so app repos can't drift from or weaken it. | feature | Issue. |
| F6 [#15](https://github.com/northcutted/clearcutt-factory/issues/15) | Until the pin PR merges, any push to an app's `main` rebuilds from the old lock. `publish` finds that digest "already published" and **moves `latest` back to the unpatched image**. | hazard | Confirmed in code; reproduce, then issue/PR. |
| F7 [#16](https://github.com/northcutted/clearcutt-factory/issues/16) | The second-runner reproduction is only a CI job result. Attest it, so verifiers and the portal can show "independently reproduced". | feature | Issue. |
| F8 [#17](https://github.com/northcutted/clearcutt-factory/issues/17) | Reusable workflows only take a static `CLEARCUTT_BOT_TOKEN`. Support GitHub App credentials (`app-id` and private key) for short-lived tokens. | feature | Issue. |

**clearcutt-verify** (issues [#48–#52](https://github.com/northcutted/clearcutt-verify/issues); mapping in issues.md):

| # | Need |
|---|---|
| V1 | Trust policy for reusable-workflow signers. Bind the caller repository or owner (Fulcio extensions), not just a SAN regexp. Support several signer roles (images versus stacks). |
| V2 | Read and verify factory evidence: `recipe/v1` and `rebase/v1` predicates, CycloneDX SBOM attestations, cosign `vuln` attestations, and GitHub artifact attestations (SLSA). |
| V3 | Enumerate a GHCR org namespace through the GitHub Packages API (GHCR has no `_catalog`). |
| V4 | Stacks as estate entities (artifact type `application/vnd.clearcutt.factory.stack.v1+yaml`), and app → stack digest from the recipe's lock. |
| V5 | A machine-readable "dependents of base repository X" output with source repositories, to drive cross-repository rebases. |
| V6 | CI distribution: signed release binaries and a GitHub Action, plus persisted history between runs. |
| V7 | Reproducibility: consume factory's reproduction evidence (F7), or rebuild. Distinguish `recipe-rebuild` from `rebase-repeat`. |

**clearcutt-portal.** The repository doesn't exist yet; these will be filed
once it does.
- P1: build from a report bundle plus history.
- P2: a GitHub Pages action.
- P3: per-image evidence pages with copy-paste verify commands.
- P4: the base graph.
- P5: package search ("who ships libxml2 < 2.14").
- P6: a timeline that diffs reports (the drill before and after).

## 9. Phases

0. **Plan and issues.** This document.
1. **Local prototype.** Under `~/…`, with a local registry container. Build every
   image, the stacks, and the apps. Prove the non-Go stacks reproduce under
   emulation. Rehearse the drill: safe rebases, catalog's refusal, and F3.
2. **Factory fixes.** F1 and F2 (and F3 and F6 if confirmed) as focused PRs with
   tests, CHANGELOG, and schemas. The showcase pins factory by SHA until you
   choose to release.
3. **Bring-up**, after your approval. Create the org and repos, apply the
   settings, add the secret, push, and get publishing green in `platform`, then
   in each app.
4. **Coordination.** The notify and dispatch workflows. Then end-to-end: a run
   image published leads to apps rebased within minutes.
5. **Drill.** Script it (`demo/drill.sh stage|respond|status`), rehearse it, and
   time it.
6. **Verify and portal.** Wire `estate.yml` once both tools have releases.

## 10. Decisions needed

1. **Org:** create `clearcutt-showcase`, or use another name?
2. **Repos:** create `platform`, `checkout`, `catalog`, `storefront`, and
   `showcase` (all public) in it?
3. **Token:** one fine-grained PAT as an org secret scoped to those five repos,
   or a repository secret in each? (The permissions are in §6.)
4. **Settings:** allow Actions to create and approve PRs (org-wide); Pages for
   `showcase`. Branch protection and auto-merge can come later.
5. **Drill staging:** see [demo-script.md](demo-script.md#act-6--cve-drill). The
   "before" state is created by holding two packages at their last vulnerable
   builds, clearly labelled as a drill.
