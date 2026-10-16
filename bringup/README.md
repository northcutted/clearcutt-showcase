# Bring-up (phase 3)

Everything needed to create the showcase organization on GitHub with one
script, once the owner has made the decisions in [plan §10](../docs/plan.md#10-decisions-needed)
and the tool releases exist. Nothing in this directory has been run against
GitHub; it was prepared and checked locally (see [Checked so far](#checked-so-far)).

| Path | What it is |
|---|---|
| [`repos/`](repos/) | The exact initial contents of the five repositories, with placeholders (`<ORG>`, `<FACTORY_REF>`, …) the script fills in. Locks and Containerfiles are not here: the script writes them with `clearcutt-factory lock` just before pushing, because they pin digests that only exist then |
| [`bringup.sh`](bringup.sh) | Creates the repositories, applies the settings, sets the credentials, and pushes. Dry run by default; idempotent |
| [`drill-github.sh`](drill-github.sh) | The CVE drill on GitHub (`stage`, `respond`, `status`); the counterpart of [`prototype/scripts/drill.sh`](../prototype/scripts/drill.sh) |
| `lib.sh` | Helpers both scripts share |
| `.work/` | (ignored) what the scripts render, lock, and push |

## 1. Decisions (plan §10), with recommended answers

| # | Decision | Recommended | Script input |
|---|---|---|---|
| 1 | Organization name | `clearcutt-showcase` (Free plan). The script checks it exists | `--org` |
| 2 | Repositories | `platform`, `checkout`, `catalog`, `storefront`, `showcase`, all public | (fixed) |
| 3 | Credentials for the bot's pull requests and dispatches | A **GitHub App** (factory #36, F8): tokens expire within the hour and belong to no person. Its Client ID as an org variable `CLEARCUTT_APP_ID` and its key as an org secret `CLEARCUTT_APP_PRIVATE_KEY`, both scoped to the five repositories. A fine-grained PAT (`CLEARCUTT_BOT_TOKEN`) still works as the fallback | `--token app` (or `pat`), `--secrets-at org` (or `repo`) |
| 4 | Settings | Allow Actions to create and approve pull requests (org and each repository); Pages from GitHub Actions on `showcase`; branch protection and auto-merge later | `--protect` when wanted |
| 5 | Drill staging | Hold OpenSSL 3 at 3.6.3-r4 in every run image and libxml2 at 2.13.6-r3 in `run-python`/`build-python`, in a platform PR labelled **DRILL** ([demo-script Act 6](../docs/demo-script.md#act-6-cve-drill)) | `drill-github.sh stage` |
| 6 | Tool versions | Release tags: clearcutt-factory **v0.2.0**, clearcutt-verify **v0.16.0**, clearcutt-portal **v0.1.0**. Commit SHAs work for a rehearsal before the releases (the image signer's identity then ends in `@<sha>`; see [Pinning](#pinning)) | `--factory-ref`, `--verify-ref`, `--portal-ref` |
| 7 | What `showcase` starts from | This repository's history (plan §1: "this local repository becomes `showcase`"), plus one commit adding [`repos/showcase/`](repos/showcase/) | `--showcase-ref` (default `HEAD`) |

## 2. Before running

**Releases** (the script refuses `--apply` with an unreleased tag):

- clearcutt-factory: merge [#49](https://github.com/northcutted/clearcutt-factory/pull/49)
  (lands #30, #31, #32, #33, #34, #36, #45, #46, #47, #48) and [#50](https://github.com/northcutted/clearcutt-factory/pull/50)
  (shared org profiles), then release **v0.2.0**. The workflows here need
  #36 (App tokens, `notify.yml`, `images.yml`'s `published` output,
  reproduction attestations), #46 (build stage as root: the F9 workaround is
  gone), #30 and #45 (the drill's refused rebase and tags), #48 (idempotent
  `stack push`), and #50 (`profile push`, `extends`).
- clearcutt-verify: merge [#68](https://github.com/northcutted/clearcutt-verify/pull/68),
  [#69](https://github.com/northcutted/clearcutt-verify/pull/69), [#71](https://github.com/northcutted/clearcutt-verify/pull/71),
  then release **v0.16.0** (approve its release gate).
- clearcutt-portal: merge [#3](https://github.com/northcutted/clearcutt-portal/pull/3),
  [#4](https://github.com/northcutted/clearcutt-portal/pull/4), [#8](https://github.com/northcutted/clearcutt-portal/pull/8),
  [#9](https://github.com/northcutted/clearcutt-portal/pull/9), then release **v0.1.0**.

**Manual, on the web** (no API for these):

1. **Create the organization**: <https://github.com/account/organizations/new?plan=free>,
   named as decided (recommended `clearcutt-showcase`). The script stops with
   this URL (exit 3) until it exists.
2. **Create the GitHub App** (with `--token app`): organization settings →
   Developer settings → GitHub Apps → New GitHub App. Any name and homepage;
   clear **Webhook → Active**; **Repository permissions**: Contents *read and
   write*, Pull requests *read and write*, Metadata *read* (nothing else);
   "Only on this account". Note the **Client ID**; **Generate a private key**
   (a `.pem`). Then **Install** it on **All repositories** of the
   organization, so the repositories the script creates are included. (This is
   factory's [adopting guide](https://github.com/northcutted/clearcutt-factory/blob/main/docs/adopting.md#a-github-app-for-the-automation).)
   With `--token pat` instead: a fine-grained PAT, resource owner the
   organization, the five repositories (create them first with
   `--steps preflight,org,repos`), Contents and Pull requests *read and write*.

**On this machine**: `gh` logged in with the scopes `repo`, `workflow`,
`admin:org`, `read:packages` (`gh auth refresh -s workflow,admin:org,read:packages`;
add `delete_repo` for a rollback), `git`, `jq`, `perl`, and for the push
steps `clearcutt-factory` (the same release as `--factory-ref`) and
`cosign`; `python3` for the drill.

## 3. Run it

```sh
bringup/bringup.sh --org clearcutt-showcase --offline   # the whole plan, no GitHub at all
bringup/bringup.sh --org clearcutt-showcase             # dry run: reads GitHub, changes nothing
bringup/bringup.sh --org clearcutt-showcase --apply --wait
```

Each step checks what is already there and skips it, so the script can be
run again after any failure. With `--apply`, values are taken from
`CLEARCUTT_APP_ID`, `CLEARCUTT_APP_PRIVATE_KEY_FILE`, or `CLEARCUTT_BOT_TOKEN`
if set, else asked for; secrets are never echoed or put on a command line.

| Step | What it does |
|---|---|
| `preflight` | Tools, `gh` scopes, the three releases exist, the local factory matches `--factory-ref` |
| `org` | The organization exists (else prints the creation URL and exits 3); with `--token app`, an App is installed |
| (render) | Copies `repos/*` to `.work/ORG/render/`, filling the placeholders; fails if any is left |
| `repos` | Creates the five public repositories (`gh repo create`) |
| `settings` | Org and per-repository Actions workflow permissions: read by default, **may create and approve pull requests**; delete merged branches; topic `clearcutt-app` on the apps; `showcase`'s homepage |
| `secrets` | `CLEARCUTT_APP_ID` (variable) and `CLEARCUTT_APP_PRIVATE_KEY` (secret), or `CLEARCUTT_BOT_TOKEN`, at the org scoped to the five repositories (or in each); skipped if set (`--reset-secrets` sets them again) |
| `platform` | Locks the six platform images, commits, pushes `main`. `platform.yml` then publishes the images, the stacks, and the shared profile |
| `apps` | Waits (`--wait`, up to 90 minutes) or stops (exit 4) until `factory/org`, `stacks/{go,python,node}` are published, and warns about any that are private. Then for each app: lock (which verifies the shared profile and the stack against their signers), commit, push |
| `showcase` | Clones this repository at `--showcase-ref` into `.work`, adds `repos/showcase/` as one commit, pushes it as `main` |
| `pages` | Pages source: GitHub Actions |
| `protect` | Only with `--protect`: requires the `images / build (…)` checks on `main` (admins can still bypass), allows auto-merge |

A repository that already has commits is never pushed to again; change it
with pull requests.

## 4. What stays manual

- Creating the organization and the GitHub App, and installing the App (above).
- Approving clearcutt-verify's release gate for v0.16.0.
- **Package visibility.** GHCR may create the first packages private. The
  `apps` step warns and links each package's settings; make the platform,
  stack, profile, and app packages public there (the web is the only way).
  Public packages need no read grant across repositories (plan §6).
- Merging the bot's pull requests (pin, rebuild, lock updates), or
  `drill-github.sh --merge-bot-prs`, or auto-merge once `--protect` is on.

## 5. Check each phase

**Phase 3, bring-up.**

1. `https://github.com/ORG/platform/actions`: `platform` green. The `images`
   jobs publish six images and the second runner reproduces each; `stacks`
   and `profile` push and sign; `notify-*` dispatch to the three apps.
2. From any machine:
   ```sh
   cosign verify ghcr.io/ORG/platform/run-go:1 \
     --certificate-identity-regexp '^https://github\.com/northcutted/clearcutt-factory/\.github/workflows/images\.yml@' \
     --certificate-github-workflow-repository ORG/platform \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   cosign verify ghcr.io/ORG/stacks/go:1 \
     --certificate-identity https://github.com/ORG/platform/.github/workflows/stacks.yml@refs/heads/main \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   cosign verify ghcr.io/ORG/factory/org:1 \
     --certificate-identity https://github.com/ORG/platform/.github/workflows/profile.yml@refs/heads/main \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   gh api orgs/ORG/packages?package_type=container --jq '.[] | "\(.name) \(.visibility)"'
   ```
3. Each app's `factory` workflow green on its first push (images, then
   fleet: "already on the newest base"); `ghcr.io/ORG/apps/<app>:latest`.
4. `showcase`'s `estate` workflow green, and the site up (phase 6).

**Phase 4, coordination: a dispatch rebases within minutes.**

```sh
# Plumbing: a dispatch starts the fleet (nothing new: "already on the newest base").
gh api repos/ORG/checkout/dispatches -f event_type=clearcutt.run-image-published
gh run list -R ORG/checkout --workflow factory.yml --limit 1
# End to end (demo Act 3): propose lock updates, merge one run image's PR.
gh workflow run update-locks.yml -R ORG/platform
gh pr list -R ORG/platform
```

Merging, say, `run-node`'s pull request publishes it; `notify-images`
dispatches; storefront's fleet rebases and opens `factory/rebase/storefront`.
Target: the pin pull request within about 5 minutes of the publish (the
prototype's rebases took 13–29 s). Time it from the runs' timestamps.

**Phase 5, the drill.**

```sh
bringup/drill-github.sh --org ORG stage                          # dry run: the PR it would open
bringup/drill-github.sh --org ORG --apply --merge-bot-prs stage  # before the audience: the "before" state
bringup/drill-github.sh --org ORG status                         # read-only, timed from the DRILL merge
bringup/drill-github.sh --org ORG --apply respond                # live: release the holds
bringup/drill-github.sh --org ORG status
```

Expected after `respond` (demo-script Act 6): checkout and storefront rebased
(`safe to rebase` on both platforms) with pin pull requests; catalog's fleet
job red with `needs libxml2.so.2` and a rebuild pull request that moves the
build image too (factory #30), whose CI passes. Copy the `t+…m` timings from
`status` into the demo script's table. `--no-merge` stops at the pull request
so it can be merged live in the browser.

**Phase 6, verify and portal.** `https://ORG.github.io/showcase/` shows the
nine images, their evidence (signature, SBOM, scan, recipe or rebase record,
provenance on built images, reproduction attestations), the base graph, the
stacks with their signatures, and a history entry per run;
`ghcr.io/ORG/estate:latest` holds the bundle, signed by `estate.yml`.

## 6. Roll back

Deleting the repositories doesn't delete their packages (they belong to the
organization). With the `delete_repo` and `delete:packages` scopes:

```sh
for r in platform checkout catalog storefront showcase; do gh repo delete ORG/$r --yes; done
gh api 'orgs/ORG/packages?package_type=container' --paginate --jq '.[].name' |
  while read -r p; do gh api --method DELETE "orgs/ORG/packages/container/${p//\//%2F}"; done
gh variable delete CLEARCUTT_APP_ID --org ORG
gh secret delete CLEARCUTT_APP_PRIVATE_KEY --org ORG   # or CLEARCUTT_BOT_TOKEN
```

Then uninstall and delete the GitHub App, and if wanted the organization
(both on the web). Signatures already in the public transparency log (Rekor)
stay there; they name the deleted repositories.

## 7. How this differs from the prototype, and why

- **Keyless signing, one trust policy.** `platform/org/trust.yaml` is read by
  factory (through `signing.trustPolicy`, in the platform's profile and the
  shared one) and by clearcutt-verify (`showcase/estate/policy.yaml`). Images:
  factory's `images.yml` or `fleet.yml` at a release tag, **called from a
  repository of ORG** (`sourceRepositoryOwner`), the one the image names as
  its source (`sourceMatchesImage`), on `main` (`sourceRef`). Stacks: only
  `ORG/platform/.github/workflows/stacks.yml@refs/heads/main`. The shared
  profile: only `…/profile.yml@refs/heads/main`, named in each app's
  `extends.signer`. Stacks and the profile get their own identities by being
  workflow files of their own, called from `platform.yml`.
- **Shared org profile (factory #50).** Apps extend `ghcr.io/ORG/factory/org:1`
  and add only `registry` and `tags`; they can't loosen the gate or policy.
  The platform's own `factory.org.yaml` repeats the shared settings, because
  it can't extend a profile it publishes after its own first build. Keep the
  two in step.
- **Apps live in a subdirectory** (`checkout/checkout/app.yaml`, …). With
  `app.yaml` at the repository root, factory's fleet and lock-update jobs
  name their branch `factory/rebase/.`, which git refuses (F17 below).
- **Workarounds dropped**: F9 (world-writable `/out` and `/src` in build
  images; factory #46 runs the build stage as root), F12 (a second profile to
  sign stacks; keyless stacks are signed by `stacks.yml`'s identity), F11 (a
  BuildKit mirror for a local registry), F14 (explicit excludes of factory's
  own files; #46). The go stack keeps `GOCACHE` in `/tmp` as validated.
- **Estate policy** requires signature, SBOM, scan, and recipe, not
  provenance: a rebased app carries a rebase record instead of SLSA
  provenance, and clearcutt-verify counts provenance as missing there (V13
  below). The upstream `wolfi-base` is left out of `estate/refs.txt`: it has
  none of factory's evidence, so it would fail the policy forever.
- **Cross-repository refresh.** Besides `notify.yml` (platform → apps), the
  platform and each app send `clearcutt.estate-changed` to `showcase` after
  publishing or rebasing (not after the daily fleet run, which the estate's
  own daily run follows).
- **Concurrency**: one fleet run and one lock update at a time per
  repository (`fleet-<repo>`, `update-locks-<repo>`), waiting, never
  cancelling; one estate run at a time.

### Pinning

`<FACTORY_REF>` pins every factory reusable workflow and the action, and is
passed as `factory-version` (a tag installs that signed release; a SHA builds
that commit). The trust policy's image identity ends in
`refs/tags/v\d+\.\d+\.\d+` for a tag, or `[0-9a-f]{40}` for a SHA, so moving
from SHA to tag means re-signing (republishing) everything. `<VERIFY_REF>`
pins the verify action (a SHA installs the release tagged there; with no
such release pass `--verify-version source`). `<PORTAL_REF>` pins
`portal.yml` and is passed as `portal-version`.

## 8. Found while preparing (not filed)

- **F17 (factory, Medium).** `fleet.yml` and `update-locks.yml` name their
  branch after the manifest's directory with `tr '/' '-'`. For a manifest at
  the repository root that is `.`, and `factory/rebase/.` isn't a valid ref,
  so neither job can open its pull request. Worked around with the
  subdirectory layout; fix: name the branch after the manifest's
  `metadata.name`, or map `.` to it.
- **V13 (verify, Medium).** A rebased image has no SLSA provenance (it was
  never built), but `required: [provenance]` counts it as missing rather
  than not-applicable, so every rebased app fails. Worked around by not
  requiring provenance; fix: treat provenance like the recipe on rebased
  images (follow the rebase record to the original's provenance, or mark it
  not applicable).

## Checked so far

Locally, without GitHub (2026-10-16), with factory built from
`feat/shared-org-profile` (#50 on #49) and verify from
`fix/nearest-base-stacks-reproduction` (#71):

- `actionlint` 1.7.12 (with shellcheck) on every workflow, rendered with tag
  pins and again with commit-SHA pins: clean.
- `shellcheck` 0.11 on `bringup.sh`, `drill-github.sh`, `lib.sh`: clean.
  Both scripts run under bash 3.2 (macOS) and 5.
- `clearcutt-factory lock` and `render --check` of all six platform images
  with the rendered keyless profile and trust policy (tag and SHA variants).
- The drill's holds on the bring-up manifests: `drill-holds.py apply`, then
  `lock` resolves libcrypto3/libssl3 3.6.3-r4 and libxml2 2.13.6-r3;
  `release` restores the manifests byte for byte.
- `profile push` of the shared profile to a throwaway in-memory registry
  (`crane registry serve`): accepted, two files (profile and trust policy).
  An app's `factory.org.yaml` merged over it with factory's own loader:
  accepted (registry and tags added); a copy that turns
  `requireSignedStacks` off is refused.
- `clearcutt-verify estate verify` with `showcase/estate/policy.yaml` and the
  rendered trust policy (both pin variants): the policy loads and its
  identity checks pass.
- `bringup.sh` dry runs: `--offline` prints every step; online it reads
  GitHub only and stops at the missing organization (exit 3).
  `drill-github.sh stage`/`respond` rehearsed against a local copy of the
  platform (`--platform-clone`).

Not checkable before bring-up: keyless signing and caller binding in real
runs, notify and dispatch across repositories, GHCR package visibility, the
check names `--protect` requires, and Pages deployment.
