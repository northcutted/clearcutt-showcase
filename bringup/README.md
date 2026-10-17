# Bring-up (phase 3)

Everything needed to bring the showcase up on GitHub with one script. The
decisions in [plan §10](../docs/plan.md#10-decisions) are made: a **personal
account, `northcutted`**, with prefixed repositories, and a **GitHub App** for
the automation. Nothing in this directory has been run against GitHub yet;
it was prepared and checked locally and with read-only (GET) calls (see
[Checked so far](#checked-so-far)).

| Path | What it is |
|---|---|
| [`repos/`](repos/) | The exact initial contents of the five repositories, with placeholders (`<OWNER>`, `<PREFIX>`, `<REGISTRY>`, `<FACTORY_REF>`, …) the script fills in. Locks and Containerfiles are not here: the script writes them with `clearcutt-factory lock` just before pushing, because they pin digests that only exist then |
| [`bringup.sh`](bringup.sh) | `up`: creates the repositories, applies the settings, sets the credentials, and pushes. `credentials`: only the credentials. Dry run by default (GET only); idempotent |
| [`drill-github.sh`](drill-github.sh) | The CVE drill on GitHub (`stage`, `respond`, `status`); the counterpart of [`prototype/scripts/drill.sh`](../prototype/scripts/drill.sh) |
| `lib.sh` | Helpers both scripts share |
| `.work/` | (ignored) what the scripts render, lock, and push |

## 1. Decisions

| # | Decision | Decided | Script input |
|---|---|---|---|
| 1 | Owner | The personal account **`northcutted`** (not a new organization) | `--owner northcutted --owner-type user` |
| 2 | Repositories | Five public repositories with an unmistakable prefix (below) | `--prefix` (default `clearcutt-showcase-` for a personal account) |
| 3 | Credentials | A **GitHub App**: a `CLEARCUTT_APP_ID` variable and a `CLEARCUTT_APP_PRIVATE_KEY` secret in each of the five repositories (a personal account has no organization secrets). Its tokens expire within the hour and belong to no person. `--token pat` (`CLEARCUTT_BOT_TOKEN`) remains as a fallback | `--app-id`, `--app-key-file` |
| 4 | Settings | Each repository: Actions may create and approve pull requests; Pages from GitHub Actions on the showcase. Branch protection and auto-merge later | `--protect` when wanted |
| 5 | Drill staging | A platform PR labelled **DRILL** holds OpenSSL 3 at 3.6.3-r4 and libxml2 at 2.13.6-r3 ([demo-script Act 6](../docs/demo-script.md#act-6-cve-drill)) | `drill-github.sh stage` |
| 6 | Tool versions | clearcutt-factory **v0.3.0** and clearcutt-portal **v0.1.0** (released); clearcutt-verify **v0.16.0** (at its release gate) | `--factory-ref`, `--portal-ref`, `--verify-ref` (these are the defaults) |
| 7 | What the showcase repository starts from | This repository's history (plan §1), plus one commit adding [`repos/showcase/`](repos/showcase/) | `--showcase-ref` (default `HEAD`) |

### Names in a personal account

`northcutted` owns unrelated repositories and packages too, so everything
the showcase creates carries the prefix:

| Role | Repository | Publishes |
|---|---|---|
| Platform team | `northcutted/clearcutt-showcase-platform` | `ghcr.io/northcutted/clearcutt-showcase/platform/{run,build}-{go,python,node}`, `…/stacks/{go,python,node}:1`, `…/factory/org:1` (the shared profile) |
| Payments team | `northcutted/clearcutt-showcase-checkout` | `ghcr.io/northcutted/clearcutt-showcase/apps/checkout` |
| Catalog team | `northcutted/clearcutt-showcase-catalog` | `ghcr.io/northcutted/clearcutt-showcase/apps/catalog` |
| Web team | `northcutted/clearcutt-showcase-storefront` | `ghcr.io/northcutted/clearcutt-showcase/apps/storefront` |
| Security, docs, portal | `northcutted/clearcutt-showcase` | `ghcr.io/northcutted/clearcutt-showcase/estate:latest`; the site at **https://northcutted.github.io/clearcutt-showcase/** |

Trust is bound to these exact repositories, not to the owner: the trust
policy (`clearcutt-showcase-platform/org/trust.yaml`) has one image signer per
repository (factory's `images.yml`/`fleet.yml` at a release tag, run in that
repository, on `main`, for an image that names that repository as its
source), and the stack and shared-profile signers are the platform
repository's own `stacks.yml` and `profile.yml` on `main`. A repository of
`northcutted` outside the showcase that calls factory's workflows can't
produce anything the showcase accepts.

Only the three app repositories carry the topic `clearcutt-app`, which the
platform's `notify` job searches (`user:northcutted topic:clearcutt-app`); the
script refuses to proceed (exit 6) if another repository of the owner carries
it, or if a repository with one of the five names exists and isn't the
showcase's. All five get the topic `clearcutt-showcase`.

## 2. Before running

**Releases.** clearcutt-factory v0.3.0, clearcutt-verify v0.16.0, and
clearcutt-portal v0.1.0 are published (verify v0.16.0 was released on
2026-10-17; the live showcase's `estate.yml` pins it).

**On this machine:**

- `gh`, logged in as `northcutted`, with the scopes **`repo`** and
  **`workflow`** (pushing `.github/workflows`). The current token lacks
  `workflow`; add it with `gh auth refresh -h github.com -s workflow`. The
  script exits 5 when a scope is missing. No `write:packages`: the script
  never pushes packages (the workflows do, with their own token). For a
  rollback, also `delete_repo` (and `delete:packages`, which the token has).
- `git`, `jq`, `perl`, `curl`; `python3` for the drill.
- `clearcutt-factory` **v0.3.0** and `cosign`, for the `lock`s the script
  runs before pushing (factory's [adopting guide](https://github.com/northcutted/clearcutt-factory/blob/v0.3.0/docs/adopting.md#1-install)
  shows how to install the release and check its signature).

### The GitHub App (personal account)

**The quick way (two clicks).** Open [`create-app.html`](create-app.html) in a
browser and press **Create**, then **Create GitHub App** on GitHub. GitHub
redirects to the showcase portal with `?code=…` in the address bar. Then:

```sh
bringup/bringup.sh app-from-code --owner northcutted --owner-type user --code CODE --apply
```

This exchanges the code (single use, valid for an hour) for the App's Client
ID and private key, which it keeps in `~/.config/clearcutt-showcase/` (mode
0600, never printed), and sets the credentials on the five repositories. It
prints the link to **install** the App: choose *Only select repositories* and
pick the five. The manual way follows.


Create it after the repositories exist (step 3 below), so it can be installed
on exactly them:

1. **Settings → Developer settings → GitHub Apps → New GitHub App**
   (<https://github.com/settings/apps/new>).
   - Name: anything unused on GitHub, e.g. `clearcutt-showcase-bot`.
     Homepage URL: `https://github.com/northcutted/clearcutt-showcase`.
   - **Webhook**: clear **Active**.
   - **Repository permissions**: **Contents: Read and write**, **Pull
     requests: Read and write**, **Metadata: Read-only** (always on). Nothing
     else: no account permissions, no events.
   - **Where can this GitHub App be installed?** Only on this account.
2. **Create GitHub App**. Note its **Client ID** (`Iv23…`). Under **Private
   keys**, **Generate a private key**: a `.pem` file downloads. Keep it
   somewhere safe; the script reads it once and never prints it.
3. **Install App** → `northcutted` → **Only select repositories**: the five
   `clearcutt-showcase*` repositories above. (**All repositories** works too,
   but then the App can reach every repository of the account; the workflows
   still ask for tokens scoped to the repositories they need.)

What uses it: the lock-update and fleet jobs open pull requests as the App
(so CI runs on them by itself); the platform's `notify` job dispatches to
the app repositories; the platform and the apps dispatch
`clearcutt.estate-changed` to the showcase.

## 3. The exact sequence

```sh
cd ~/Development/clearcutt/clearcutt-showcase      # branch bringup/phase-3 (or wherever it is merged)
# The defaults pin factory v0.3.0, verify v0.16.0, and portal v0.1.0.

# 0. Once: the gh scope, and the tools.
gh auth refresh -h github.com -s workflow
clearcutt-factory version                          # v0.3.0
cosign version

# 1. Rehearse: the whole plan without GitHub, then with GitHub reads only
#    (exit 0 once nothing would stop an apply).
bringup/bringup.sh --owner northcutted --owner-type user --offline
bringup/bringup.sh --owner northcutted --owner-type user

# 2. Approve clearcutt-verify's v0.16.0 release gate (web), then check:
gh release view v0.16.0 -R northcutted/clearcutt-verify

# 3. Create the five repositories and their settings (no pushes, no credentials yet).
bringup/bringup.sh --owner northcutted --owner-type user --steps repos,settings --apply

# 4. Create the GitHub App and install it on the five repositories (above, web).

# 5. Credentials: CLEARCUTT_APP_ID and CLEARCUTT_APP_PRIVATE_KEY in each repository.
bringup/bringup.sh credentials --owner northcutted --owner-type user \
  --app-id <CLIENT_ID> --app-key-file <PATH_TO_APP_KEY.pem> --apply

# 6. Push platform, wait for its first publish (~15 min), push the apps and
#    the showcase, turn on Pages. Steps already done are skipped.
bringup/bringup.sh --owner northcutted --owner-type user --apply --wait
```

`up` (the default subcommand) runs every step in order; `--skip-credentials`
leaves out the credentials, and `credentials` sets them later. Without
`--wait`, step 6 stops after pushing platform (exit 4); run it again once
`platform` is green. Values the script needs and wasn't given are asked for
(only if some repository still lacks them), never echoed.

| Step | What it does |
|---|---|
| preflight | Tools, gh scopes (exit 5), the pinned releases, the local factory version, the App key file is a readable PEM |
| owner | `northcutted` is a user, and gh is logged in as it (exit 3 if the account doesn't exist) |
| names | Each of the five names is free or already the showcase's; no other repository carries `clearcutt-app` (exit 6) |
| (render) | Copies `repos/*` to `.work/OWNER/render/`, filling the placeholders; fails if any is left |
| `repos` | `gh repo create` the five, public, with descriptions that mark them as the showcase's |
| `settings` | Each repository: Actions workflow permissions (read, **may create and approve pull requests**), delete merged branches, topic `clearcutt-showcase` (and `clearcutt-app` on the apps), the showcase's homepage |
| `credentials` | `CLEARCUTT_APP_ID` (variable; updated if different) and `CLEARCUTT_APP_PRIVATE_KEY` (secret; kept if set unless `--reset-secrets`) in each repository |
| `platform` | Locks the six platform images, commits, pushes `main` |
| `apps` | Waits (`--wait`, up to 90 minutes) or stops (exit 4) until the shared profile and the three stacks are published and public, then locks each app (verifying the profile and stack signatures), commits, pushes |
| `showcase` | Clones this repository at `--showcase-ref`, adds `repos/showcase/` as one commit, pushes it as `main` |
| `pages` | Pages source: GitHub Actions |
| `protect` | Only with `--protect`: the `images / build (…)` checks required on `main` (admins can bypass); auto-merge allowed |

A repository that already has commits is never pushed to again; change it
with pull requests.

**An organization instead**: `--owner NAME --owner-type org` (or `--org
NAME`) uses the plain names (`platform`, …, `showcase`, `ghcr.io/NAME/…`),
sets the Actions permission and the credentials once at the organization
(`--secrets-at org`, scoped to the five repositories), and needs the
`admin:org` scope. The organization must be created on the web first
(<https://github.com/account/organizations/new?plan=free>; the script exits 3
until it exists).

## 4. What stays manual

- Approving clearcutt-verify's v0.16.0 release gate.
- Creating the GitHub App and installing it on the five repositories.
- **Package visibility.** GHCR may create the first packages private. The
  `apps` step warns and links each package's settings; make the platform,
  stack, profile, and app packages public there (the web is the only way).
  Public packages need no read grant across repositories.
- Merging the bot's pull requests (pin, rebuild, lock updates), or
  `drill-github.sh --merge-bot-prs`, or auto-merge once `--protect` is on.

## 5. Check each phase

With `P=northcutted/clearcutt-showcase` and `R=ghcr.io/northcutted/clearcutt-showcase` (single words, so this works in zsh too):

**Phase 3, bring-up.**

1. `https://github.com/$P-platform/actions`: `platform` green: `images`
   publishes six images and the second runner reproduces each; `stacks` and
   `profile` push and sign; `notify-*` dispatch to the three apps.
2. From any machine:
   ```sh
   cosign verify $R/platform/run-go:1 \
     --certificate-identity-regexp '^https://github\.com/northcutted/clearcutt-factory/\.github/workflows/images\.yml@refs/tags/' \
     --certificate-github-workflow-repository $P-platform \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   cosign verify $R/stacks/go:1 \
     --certificate-identity https://github.com/$P-platform/.github/workflows/stacks.yml@refs/heads/main \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   cosign verify $R/factory/org:1 \
     --certificate-identity https://github.com/$P-platform/.github/workflows/profile.yml@refs/heads/main \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   gh api 'user/packages?package_type=container&per_page=100' --paginate \
     --jq '.[] | select(.name | startswith("clearcutt-showcase/")) | "\(.name) \(.visibility)"'
   ```
3. Each app's `factory` workflow green on its first push (images, then the
   fleet: already on the newest base); `$R/apps/<app>:latest` exists.
4. `$P`'s `estate` workflow green, and the site up (phase 6).

**Phase 4, coordination: a dispatch rebases within minutes.**

```sh
# Plumbing: a dispatch starts the fleet (nothing new: already on the newest base).
gh api repos/$P-checkout/dispatches -f event_type=clearcutt.run-image-published
gh run list -R $P-checkout --workflow factory.yml --limit 1
# End to end (demo Act 3): propose lock updates, merge one run image's PR.
gh workflow run update-locks.yml -R $P-platform
gh pr list -R $P-platform
```

Merging, say, `run-node`'s pull request publishes it; `notify-images`
dispatches; storefront's fleet rebases and opens `factory/rebase/storefront`.
Target: the pin pull request within about 5 minutes of the publish (the
prototype's rebases took 13–29 s).

**Phase 5, the drill.**

```sh
bringup/drill-github.sh --owner northcutted --owner-type user stage                          # dry run: the PR it would open
bringup/drill-github.sh --owner northcutted --owner-type user --apply --merge-bot-prs stage  # before the audience: the "before" state
bringup/drill-github.sh --owner northcutted --owner-type user status                         # read-only, timed from the DRILL merge
bringup/drill-github.sh --owner northcutted --owner-type user --apply respond                # live (--no-merge: merge it in the browser)
bringup/drill-github.sh --owner northcutted --owner-type user status
```

Without the GitHub App, add `--wake-apps` (start each app's fleet once the
platform has published, in place of `notify`), `--merge-bot-prs` (which
closes and reopens the bot's pull requests to start their CI, then merges
them when green), and `--estate` (refresh verify and the portal at the end).
`continue` resumes from the latest DRILL pull request after `--no-merge` or
an interruption. The first real run is in [`DRILL-RESULTS.md`](DRILL-RESULTS.md).

Expected after `respond` (demo-script Act 6): checkout and storefront rebased
(`safe to rebase` on both platforms) with pin pull requests; catalog's fleet
job red with `needs libxml2.so.2` and a rebuild pull request that moves the
build image too, whose CI passes. Copy the `t+…m` timings from `status` into
the demo script's table.

**Phase 6, verify and portal.** https://northcutted.github.io/clearcutt-showcase/
shows the nine images, their evidence (signature, SBOM, scan, provenance,
recipe or rebase record, reproduction attestations), the base graph, the
stacks with their signatures, and a history entry per run;
`$R/estate:latest` holds the bundle, signed by `estate.yml`.

## 6. Roll back

Deleting a repository deletes its secrets and variables, but not its
packages: in a personal account they belong to the account, next to
`northcutted`'s other packages, so delete only the `clearcutt-showcase/` ones.
With the `delete_repo` and `delete:packages` scopes:

```sh
for r in clearcutt-showcase-platform clearcutt-showcase-checkout clearcutt-showcase-catalog \
         clearcutt-showcase-storefront clearcutt-showcase; do
  gh repo delete northcutted/$r --yes
done
gh api 'user/packages?package_type=container&per_page=100' --paginate \
  --jq '.[].name | select(startswith("clearcutt-showcase/"))' |
  while read -r p; do gh api --method DELETE "user/packages/container/${p//\//%2F}"; done
```

Then uninstall and delete the GitHub App (Settings → Applications, and
Developer settings → GitHub Apps). Signatures already in the public
transparency log (Rekor) stay there; they name the deleted repositories.

## 7. How this differs from the prototype, and why

- **Keyless signing, one trust policy, bound per repository.** See
  [Names](#names-in-a-personal-account). factory reads the trust policy through
  `signing.trustPolicy` (in the shared profile, which every repository extends),
  clearcutt-verify through `showcase/estate/policy.yaml`. Stacks and the
  profile get their own identities by being workflow files of their own,
  called from `platform.yml`.
- **Shared org profile.** Apps extend `$R/factory/org:1` (factory v0.2.0)
  and add only `registry` and `tags`; they can't loosen the gate or policy.
  The platform extends the same file by path (`extends: {path:
  org/profile.yaml}`, factory v0.3.0, #55), adding its registry and base, so
  it builds under exactly what it publishes, even before the first publish.
  Each lock pins the profile's digest (`profile: {path, digest}`), which
  equals the published one.
- **Apps live in a subdirectory** (`checkout/app.yaml` in
  `clearcutt-showcase-checkout`). This was needed before factory v0.2.0
  (F17, fixed by #51: a root manifest's branch is now `factory/rebase/root-app`);
  it is kept because it reads well and gives the bot's branches the app's name.
- **The estate requires provenance.** factory v0.2.0 attests SLSA
  provenance on rebased images too (#52, which closes V13), so the fleet's
  steady state meets `required: [signature, sbom, vulnerabilityScan,
  provenance, recipe]`. Callers of `fleet.yml` grant `attestations: write`.
- **Workarounds dropped**: F9 (world-writable `/out` and `/src` in build
  images; factory runs the build stage as root), F12 (a second profile to
  sign stacks), F11 (a BuildKit mirror for a local registry), F14 (explicit
  excludes of factory's own files). The go stack keeps `GOCACHE` in `/tmp` as
  validated.
- **Cross-repository refresh.** Besides `notify.yml` (platform → apps), the
  platform and each app send `clearcutt.estate-changed` to the showcase after
  publishing or rebasing (not after the daily fleet run, which the estate's
  own daily run follows). The upstream `wolfi-base` stays out of
  `estate/refs.txt`: it has none of factory's evidence and would fail the
  policy forever.
- **Notify before reproducing** (factory v0.3.0, #60). `images.yml` is
  called twice: once with `reproduce: false`, which publishes, and once
  with that call's `published` output, which only reproduces it on a second
  runner. `notify`, `stacks`, and the fleet need only the first, so the apps
  hear about a publish about 2m20s sooner (the drill's measurement), while
  `estate-changed` also needs the second, so the estate sees the reproduction
  attestations.
- **Focused CVE pull requests** (factory v0.3.0, #59). `drill-github.sh`
  re-locks the held images with `lock --update-package` naming only the held
  packages, so the drill's pull requests move nothing else.
- **Concurrency**: one fleet run and one lock update at a time per
  repository, waiting, never cancelling; one estate run at a time.

### Pinning

`<FACTORY_REF>` pins every factory reusable workflow and the action, and is
passed as `factory-version` (a tag installs that signed release; a SHA builds
that commit). The trust policy's image identity ends in
`refs/tags/v\d+\.\d+\.\d+` for a tag, or `[0-9a-f]{40}` for a SHA, so moving
between them means republishing. `<VERIFY_REF>` pins the verify action (a SHA
installs the release tagged there; with no such release pass
`--verify-version source`). `<PORTAL_REF>` pins `portal.yml` and is passed as
`portal-version`.

## Checked so far

Locally and with GET-only calls (2026-10-17), with clearcutt-factory built
from the **v0.2.0** tag and clearcutt-verify from **main `365c373`** (v0.16.0
to be):

- `actionlint` 1.7.12 (with shellcheck) on all eight workflows, rendered for
  `--owner northcutted --owner-type user` and for an organization: clean.
- `shellcheck` 0.11 on `bringup.sh`, `drill-github.sh`, `lib.sh`: clean; the
  scripts run under bash 3.2 (macOS) and 5.
- Rendered for `northcutted`: `clearcutt-factory lock` and `render --check` of
  all six platform images with the keyless profile and the per-repository
  trust policy; `profile push` of the shared profile to a throwaway
  in-memory registry (accepted: profile and trust policy), and an app's
  `factory.org.yaml` merged over it with factory's own loader (4 image
  signers, 1 stack signer, registry `ghcr.io/northcutted/clearcutt-showcase/apps`);
  `clearcutt-verify estate verify` loads the estate policy (provenance
  required) and the five signers; the drill's holds apply, lock, and release
  cleanly.
- `bringup.sh` dry runs for `northcutted`: offline (every step printed), and
  online with GET only: the account is a user, the five names are free, no
  repository of `northcutted` carries `clearcutt-app`, factory v0.2.0 and
  portal v0.1.0 are released, verify v0.16.0 isn't yet, and the token lacks
  `workflow` (exit 5). The `credentials` subcommand's dry run never prints the
  App ID or key. `drill-github.sh` rehearsed against a local copy of the
  platform (`--platform-clone`), and `status` read-only.

Not checkable before bring-up: keyless signing and caller binding in real
runs, notify and dispatch across repositories, GHCR package visibility, the
check names `--protect` requires, and Pages deployment.
