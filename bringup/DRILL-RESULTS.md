# CVE drill on GitHub: results (2026-10-17)

The drill from [demo-script Act 6](../docs/demo-script.md#act-6-cve-drill), run
for real against the live showcase under `northcutted` with
[`drill-github.sh`](drill-github.sh), clearcutt-factory v0.2.0,
clearcutt-verify `365c373` (v0.16.0 to be), and clearcutt-portal v0.1.0.

**There was no GitHub App yet**, which shaped two steps:

- The platform's `notify` job couldn't dispatch to the apps (403, as
  expected), so the platform run is red on `notify-images` only.
  `drill-github.sh --wake-apps` started each app's fleet with
  `workflow_dispatch` once the publish finished. `notify` would have
  dispatched about a minute earlier.
- The fleet opened its pull requests with the workflow's own token, so GitHub
  held their CI runs: a run with no jobs, awaiting approval. `--merge-bot-prs`
  closed and reopened each one, which started CI as the owner, then merged
  it when green.

Times are from the GitHub API (run and pull request timestamps), measured
from each DRILL merge (t = 0). The script's own `t+` stamps came out later
than these, because `gh` kept losing its connection to api.github.com
(`connection reset by peer`). Running it with `GODEBUG=http2client=0` fixed
that.

## Stage: hold OpenSSL 3 and libxml2 2.13

[platform#1](https://github.com/northcutted/clearcutt-showcase-platform/pull/1)
was opened 01:27:16Z; its gate passed in 4m26s
([run](https://github.com/northcutted/clearcutt-showcase-platform/actions/runs/38990922283)).
It was merged at 01:57:43Z (t = 0), 26 minutes late, because the first
`stage` run died on a dropped connection while watching the gate;
`drill-github.sh continue` picked it up.

| t | What happened | Links |
|---|---|---|
| +5m41s | run-go, run-python, run-node, and build-python published with the holds (signed, attested, SLSA provenance) | [platform run](https://github.com/northcutted/clearcutt-showcase-platform/actions/runs/38993020815) |
| +8m03s | all four reproduced on a second runner | |
| +8m13s | `notify-images` failed: 403 to each app (no App) | |
| +8m59s | fleets dispatched by hand (`--wake-apps`) | |
| +9m42s / +9m51s | **catalog refused** (`…/_feeds.cpython-314-{x86_64,aarch64}-linux-gnu.so needs libxml2.so.16`); rebuild PR opened, moving base **and** build image (F3 fix) | [run](https://github.com/northcutted/clearcutt-showcase-catalog/actions/runs/38993628364), [catalog#1](https://github.com/northcutted/clearcutt-showcase-catalog/pull/1) |
| +12m14s | **checkout rebased** (safe on amd64 and arm64, smoke-tested, scanned, signed, rebase repeated: same digest); pin PR | [run](https://github.com/northcutted/clearcutt-showcase-checkout/actions/runs/38993623767), [checkout#1](https://github.com/northcutted/clearcutt-showcase-checkout/pull/1) |
| +12m55s | **storefront rebased**, likewise | [run](https://github.com/northcutted/clearcutt-showcase-storefront/actions/runs/38993625998), [storefront#1](https://github.com/northcutted/clearcutt-showcase-storefront/pull/1) |
| +19m45s | checkout#1 merged (its reopened CI took 2m02s); its build from the pinned lock gave the rebased digest exactly: `is already published; moved its tags` (F10 fix) | [run](https://github.com/northcutted/clearcutt-showcase-checkout/actions/runs/38994341009) |
| +31m30s | storefront#1 merged (CI 3m07s); same re-tag | [run](https://github.com/northcutted/clearcutt-showcase-storefront/actions/runs/38995102785) |
| +54m40s | catalog#1 merged (CI 2m44s); rebuilt on the held build image (`libxml2.so.2`) and published at **+60m35s** | [run](https://github.com/northcutted/clearcutt-showcase-catalog/actions/runs/38996605726) |

The bot pull requests were handled one after another, and the dropped
connections slowed polling, which is why the merges trail CI by minutes.
`drill-github.sh` now starts every pull request's CI at once and polls
instead of watching.

**Before state**: the estate run at 03:57Z
([run](https://github.com/northcutted/clearcutt-showcase/actions/runs/39000752942),
2m39s, verify and portal) and the scheduled 07:17 run agree:

- all 9 images verified and reproduced; every base proven by layer digest;
- fixable Highs **17**, up from the baseline's 5 (npm's bundled packages in
  build-node): CVE-2026-14456 in `libcrypto3`/`libssl3` 3.6.3-r4 in all
  three run images and all three apps;
- the package index lists `libxml2 2.13.6-r3` in build-python, catalog, and
  run-python (grype reports nothing for it, W1);
- checkout and storefront are rebased, with their rebase records verified.

## Respond: release the holds

[platform#2](https://github.com/northcutted/clearcutt-showcase-platform/pull/2)
was opened at 11:48:08Z. Its lock diff shows libcrypto3/libssl3
3.6.3-r4 → 3.6.5-r2 and libxml2 2.13.6-r3 → libxml2-16 2.15.4-r1. It also
picked up openssl-4.0 4.0.3-r6 → r7, because re-locking re-resolves every
package. Its gate passed in 3m40s
([run](https://github.com/northcutted/clearcutt-showcase-platform/actions/runs/39030078638)),
and it was merged at 11:55:48Z (t = 0).

| t | What happened | Links |
|---|---|---|
| +5m10s | the four images published without the holds | [platform run](https://github.com/northcutted/clearcutt-showcase-platform/actions/runs/39030550077) |
| +7m25s | all reproduced on the second runner | |
| +7m35s | `notify-images` 403 (no App) | |
| ~+8m35s | fleets dispatched by hand | |
| +9m35s / +9m45s | **catalog refused**: `…/_feeds.cpython-314-{x86_64,aarch64}-linux-gnu.so needs libxml2.so.2`; its job red; rebuild PR moving run-python `4844ef0e…` → `daf68a5f…` **and** build-python `6d1af765…` → `59b29c2b…` | [run](https://github.com/northcutted/clearcutt-showcase-catalog/actions/runs/39031098711), [catalog#2](https://github.com/northcutted/clearcutt-showcase-catalog/pull/2) |
| +11m58s | **checkout rebased** (`safe to rebase` ×2, smoke-tested, signed, rebase repeated: same digest `2bde717b…`); pin PR | [run](https://github.com/northcutted/clearcutt-showcase-checkout/actions/runs/39031093988), [checkout#2](https://github.com/northcutted/clearcutt-showcase-checkout/pull/2) |
| +12m05s | **storefront rebased** (`cd946e7d…`); pin PR | [run](https://github.com/northcutted/clearcutt-showcase-storefront/actions/runs/39031096208), [storefront#2](https://github.com/northcutted/clearcutt-showcase-storefront/pull/2) |
| +12m21s…+12m31s | the three PRs reopened; CI 2m40s (checkout), 3m39s (storefront), 2m24s (catalog, rebuilt on `libxml2.so.16`) | |
| +15m07s / +16m14s / +16m20s | checkout#2, storefront#2, catalog#2 merged | |
| +19m16s | checkout published (re-tag of the rebased digest) | [run](https://github.com/northcutted/clearcutt-showcase-checkout/actions/runs/39031514153) |
| +21m24s | storefront published (re-tag) | [run](https://github.com/northcutted/clearcutt-showcase-storefront/actions/runs/39031589579) |
| **+21m38s** | **catalog rebuilt and published: all clear** | [run](https://github.com/northcutted/clearcutt-showcase-catalog/actions/runs/39031596076) |
| +27m03s | estate verified and portal deployed (3m07s) | [run](https://github.com/northcutted/clearcutt-showcase/actions/runs/39032081677) |

**After state** (`ghcr.io/northcutted/clearcutt-showcase/estate:latest`,
12:20:33Z; https://northcutted.github.io/clearcutt-showcase/):

- all 9 images verified and reproduced; every base proven and current;
- fixable Highs back to **5** (build-node's npm, as at baseline);
  CVE-2026-14456 is gone from every image;
- the package index lists only libcrypto3/libssl3 3.6.5-r2 and libxml2-16
  2.15.4-r1;
- checkout and storefront are rebased: rebase records verified, **SLSA
  provenance verified on the rebased images too** (factory v0.2.0, #52);
- the history has four runs: baseline 5 → before 17 → (scheduled) 17 →
  after 5, which the portal's history page shows.

## What it confirmed

- **Safe rebases in minutes, no app-team action.** From the platform's
  publish to checkout's and storefront's pin PRs took about 7 minutes. The
  rebase jobs themselves took 3m30s, most of it setup, QEMU, and scanning.
- **Refusal with the exact reason**, in both directions (`needs
  libxml2.so.16` at stage, `needs libxml2.so.2` at respond), routed to a
  rebuild PR that moves the build image too (F3, fixed in v0.2.0), whose CI
  then passes.
- **A rebase equals a rebuild of its pinned lock** (F10, fixed in v0.2.0):
  merging each pin PR re-tagged the rebased digest instead of publishing
  another.
- **End to end, with an operator merging promptly: about 22 minutes** from
  the platform merge to every app patched and published. The demo script's
  estimate was ~25m.

## What needs the GitHub App

- `notify`: today the platform run fails on `notify-images` and the apps
  have to be woken by hand. With the App, the fleets would start at about
  t+7m35s with no person involved.
- CI on the bot's pull requests: without the App, someone has to approve,
  or close and reopen, every pin and rebuild PR.
- `clearcutt.estate-changed`: the apps' and the platform's estate refresh is
  skipped with a warning; the estate was refreshed by hand (and daily).

## Found

The three factory points below were fixed in clearcutt-factory v0.3.0 (#57,
#60, #59), which the showcase now runs: `notify` and the fleet
no longer wait for the reproduction, and the drill re-locks only the held
packages (`lock --update-package`).

- [clearcutt-factory#57](https://github.com/northcutted/clearcutt-factory/issues/57):
  a refused rebase's rebuild PR is titled "Pin catalog to the newest run
  image", like a routine pin, though it is the one that needs a person.
- `notify` runs only after the second-runner reproduction (`images.yml`
  finishes as a whole), which adds 2m15s–2m22s before the apps hear about a
  publish. This is a design choice rather than a bug: dispatch could follow
  the `published` job. Not filed.
- Re-locking to release a hold re-resolves every package of the image, so the
  CVE PR also carried an unrelated openssl-4.0 update (as in the prototype).
  Not filed.
- `gh` against api.github.com dropped connections repeatedly from this
  machine (`connection reset by peer`); `GODEBUG=http2client=0` (HTTP/1.1)
  avoided it. Local, not a tool bug.

## Reproduce it

```sh
export GODEBUG=http2client=0     # only if gh keeps losing its connection
bringup/drill-github.sh --owner northcutted --owner-type user --git-protocol ssh --apply --wake-apps --merge-bot-prs --estate stage
bringup/drill-github.sh --owner northcutted --owner-type user status
bringup/drill-github.sh --owner northcutted --owner-type user --git-protocol ssh --apply --wake-apps --merge-bot-prs --estate respond
# after --no-merge, or if it was interrupted:
bringup/drill-github.sh --owner northcutted --owner-type user --git-protocol ssh --apply --wake-apps --merge-bot-prs --estate continue
```

With the GitHub App installed, drop `--wake-apps` (`notify` does it), and
the bot's PRs get CI without being reopened.

# Drill 2: the fully automated drill (2026-10-29)

The second drill ([assessment.md §4, Phase B](../docs/assessment.md#phase-b-close-the-structural-gaps-3-weeks)),
on the live showcase under `northcutted` with the GitHub App
`clearcutt-showcase-bot`, clearcutt-factory **v0.4.1** (platform and apps),
clearcutt-verify **v0.17.0** (estate, `--rescan`), and clearcutt-portal
**v0.2.0**. It is driven by [`drill-github.sh`](drill-github.sh)
(`toolchain-stage`, `toolchain-respond`, `critical-stage`, `critical-vex`,
`critical-respond`, `forge`) with `--auto-merge --follow`: the script opens
each act's DRILL pull request and turns on auto-merge for it, so GitHub
merges it when the platform's required check (`images / result`) passes;
after that it only watches. Nobody merges a bot's pull request: the App's
pull requests merge themselves, or the act stops and says so.

Times are from the GitHub API, from each DRILL merge (t = 0) unless stated.

## Settings found before the drill

| Repository | Allow auto-merge | Branch protection on `main` | Delete merged branches |
|---|---|---|---|
| clearcutt-showcase-platform | on | required check `images / result` (GitHub Actions), not strict, admins not enforced, no reviews | on |
| clearcutt-showcase-checkout | on | the same | on |
| clearcutt-showcase-catalog | on | the same | on |
| clearcutt-showcase-storefront | on | the same | on |
| clearcutt-showcase (estate) | off | none | on |

Every image repository calls `fleet.yml` and `update-locks.yml` with
`auto-merge: all`. Nothing turns on auto-merge for Dependabot's pull
requests (see act 2). No setting was changed for the drill.

## Baseline (before act 1)

The scheduled [estate run](https://github.com/northcutted/clearcutt-showcase/actions/runs/40834973284)
of 2026-10-29 07:22Z: **9 of 9 verified**, every image rescanned (no
`unknown`), no fixable Critical or High except build-node's npm Highs (8 in
the rescan, 7 attested). checkout reports chi's two Medium advisories and
three Unknown ones (its own dependency, act 2). Digests:

| Image | Digest |
|---|---|
| platform/run-go:1 | `sha256:ed43202dfc75…` |
| platform/build-go:1 | `sha256:cc3bea21a21b…` |
| platform/run-python:3.14 | `sha256:3ec0446df611…` |
| platform/build-python:3.14 | `sha256:6db1544584c2…` |
| platform/run-node:24 | `sha256:5b0a15d5ebd6…` |
| platform/build-node:24 | `sha256:c26523026253…` |
| apps/checkout:latest | `sha256:a32fae8e03e4…` |
| apps/catalog:latest | `sha256:a03d769e0498…` |
| apps/storefront:latest | `sha256:64b37f20b952…` |
| stacks/go:1 | `sha256:e66872c8c10c…` |
| factory/org:1 (shared profile) | `sha256:1bb0b6d38484…` |

## Running log

Kept as the drill runs, so a stopped drill can be resumed from here. To
resume: `drill-github.sh … status` shows the last DRILL pull request and
what followed it; `continue` picks it up.

| UTC | Step |
|---|---|
| 21:39 | baseline read; factory v0.4.1 installed locally (release signature verified) |
| 21:53:52 | act 1 stage: [platform#18](https://github.com/northcutted/clearcutt-showcase-platform/pull/18) opened (Go held at 1.27.2 in build-go), auto-merge on at 21:53:56 |
| 21:57:02 | platform#18 merged by auto-merge (gate green 21:56:44) |
| 22:16:16 | act 1 stage done: checkout rebuilt on Go 1.27.2 and published, estate 9/9 verified, GO-2026-6809 shown in checkout and build-go |
| 22:17 | act 1 respond started (`toolchain-respond`) |


## Act 2: a CVE in an app's own dependency (Dependabot)

Recorded from the live history; nothing was staged. checkout pins
`github.com/go-chi/chi/v5 v5.2.3`. Dependabot security updates are on in
every app repository (`bringup.sh`), and `.github/dependabot.yml` covers
`gomod` in `/checkout`.

| UTC | t | What happened | Links |
|---|---|---|---|
| 2026-10-19 00:27:19 | alert 0 | Dependabot alert #1: GHSA-mqqf-5wvp-8fh8 (Medium, CVSS 4.7, open redirect in `RedirectSlashes`), patched in 5.2.4 | [alert #1](https://github.com/northcutted/clearcutt-showcase-checkout/security/dependabot/1) |
| 2026-10-19 00:32:38 | +5m19s | security update [checkout#6](https://github.com/northcutted/clearcutt-showcase-checkout/pull/6) (chi 5.2.3 → 5.2.4) | |
| 2026-10-19 | | #6's CI (factory v0.3.0 workflows, before `images / result` existed) built, scanned and gated the app: green. Nothing could merge it but the owner; it waited | |
| 2026-10-27 02:23:48 | | the v0.4.1 adoption ([#11](https://github.com/northcutted/clearcutt-showcase-checkout/pull/11)) merges; Dependabot rescans | |
| 2026-10-27 02:23:53 | alert 0 | alert #2: GHSA-j6qf-3m9c-vwj3 (Medium, client IP spoofing in `ClientIPFromXFF`; advisory published 2026-10-23), patched in 5.4.0 | [alert #2](https://github.com/northcutted/clearcutt-showcase-checkout/security/dependabot/2) |
| 2026-10-27 02:24:37 | +44s | security update [checkout#12](https://github.com/northcutted/clearcutt-showcase-checkout/pull/12) (chi 5.2.3 → 5.4.0, fixes both); #6 closed as superseded at 02:24:46 | |
| 2026-10-27 02:27:51 | +3m58s | **#12 green**: `images / result` passed (build, smoke test, scan, gate; 3m05s of CI) | |
| since then | | **waiting for the owner**: auto-merge is not on for #12 | |

**Where it stops: "PR green, waiting for the owner".** The repository allows
auto-merge and requires `images / result`, but nothing turns auto-merge on
for Dependabot's pull requests: `fleet.yml` and `update-locks.yml` turn it on
only for the App's own pull requests, and Dependabot doesn't turn it on
itself. Agents may not merge a bot's pull request, so the act ends here,
with #12 green for 2.8 days at the time of the drill. Both advisories show in
the estate meanwhile: checkout's attested scan and rescan list
GHSA-mqqf-5wvp-8fh8 and GHSA-j6qf-3m9c-vwj3 (Medium, fixable) and three
Unknown chi advisories (GO-2026-5774/5775/5777); none is gated
(`failOn: critical`). Once #12 merges, checkout's `images` job publishes the
rebuilt app, `fleet` follows, and `estate-changed` refreshes the estate, as
in act 1.

What would close the loop without a person: a small workflow in each app
repository that turns on auto-merge for Dependabot's **security** updates
(`dependabot/fetch-metadata`, then `gh pr merge --auto --merge`), so they
merge once the same required check passes. That is a decision for the
owner (it lets a third-party bot's change reach `main` behind CI alone), so
the drill doesn't add it; it is listed in [docs/issues.md](../docs/issues.md).

## Act 1: a toolchain CVE (gap B)

Go's standard library is compiled into every Go binary, so a fix in it
reaches checkout only through a rebuild on a new build image; no rebase can
deliver it. factory v0.4.1 announces a build image as
`clearcutt.build-image-published`, stacks now name their images by digest
(so stack go:1 changes, and `clearcutt.stack-published` fires, whenever
build-go does), and each app answers both with `update-locks.yml`
(`update: stack`, `auto-merge: all`).

The hold: `go-1.27=1.27.2-r0` in build-go, re-locked with
`lock --update-package go-1.27` (only go-1.27 moved). Go 1.27.2 has
**GO-2026-6809** (CVE-2026-111943, crypto/x509 denylist), fixed in 1.27.3.
grype rates it Unknown, so the Critical gate lets the held image out, as a
real toolchain CVE below the gate would be. (Go 1.27.0 and 1.27.1 have two
fixable Criticals, GO-2026-6604 and GO-2026-6612; holding those would have
stopped at the platform's own gate, which is act 3's subject.)

### Stage: hold Go 1.27.2

[platform#18](https://github.com/northcutted/clearcutt-showcase-platform/pull/18)
opened 21:53:52Z, auto-merge on at 21:53:56; its gate (build-go only,
`changed-only`) passed at 21:56:44, and GitHub merged it at **21:57:02Z (t = 0)**.

| t | What happened | Links |
|---|---|---|
| +4m14s | build-go published (signed, attested, SLSA provenance): `2244cff126b0…`; nothing else changed, so nothing else was republished | [platform run](https://github.com/northcutted/clearcutt-showcase-platform/actions/runs/40961998726) |
| +4m35s | `notify-images`: **`clearcutt.build-image-published`** to checkout, catalog, storefront | |
| +5m00s | stack go:1 pushed by digest (`e66872c8…` → `b89a85b2…`) | |
| +5m04s | **checkout#13 "Rebuild checkout on the newest build image"** opened by the App with auto-merge on: `lock --update-stack` moved the build image and the stack, nothing else. catalog's and storefront's `update-locks` ran too and proposed nothing (their stacks hadn't moved) | [checkout#13](https://github.com/northcutted/clearcutt-showcase-checkout/pull/13), [run](https://github.com/northcutted/clearcutt-showcase-checkout/actions/runs/40962601601) |
| +5m12s | `notify-stacks`: **`clearcutt.stack-published`** to the three apps; checkout's second `update-locks` found #13 already current | [run](https://github.com/northcutted/clearcutt-showcase-checkout/actions/runs/40962681573) |
| +6m09s | build-go reproduced on a second runner; platform run green at +6m25s | |
| +6m17s | the platform's `estate-changed` refresh (9/9 verified; build-go now shows GO-2026-6809) | [estate run](https://github.com/northcutted/clearcutt-showcase/actions/runs/40962833622) |
| +8m59s | checkout#13's gate green (build, smoke test, scan, gate: 3m55s from opening) | |
| **+9m39s** | **checkout#13 merged by auto-merge** (`clearcutt-showcase-bot`), 40s after the check | |
| +14m10s | checkout rebuilt on Go 1.27.2 and published: `ddd72341…`; fleet found it on the newest run image (nothing to do) | [run](https://github.com/northcutted/clearcutt-showcase-checkout/actions/runs/40963291302) |
| +15m25s | checkout reproduced on a second runner; `estate-changed` sent | |
| **+19m14s** | **estate verified and portal deployed**: 9 of 9 verified; checkout's attested scan and its rescan both list **GO-2026-6809 (`stdlib` go1.27.2, Unknown, fixed in 1.27.3)**, as does build-go | [estate run](https://github.com/northcutted/clearcutt-showcase/actions/runs/40964068710) |

No person acted after opening the DRILL pull request. One ordering detail:
`notify-images` announces build-go (+4m35s) before `stacks` has pushed the
stack that names it (+5m00s). checkout's first `update-locks` happened to
resolve the stack just after it moved; had it run earlier, it would have
proposed the build image alone, and the `stack-published` event that follows
would have updated the pull request. Either way the second event covers the
first one's race.
