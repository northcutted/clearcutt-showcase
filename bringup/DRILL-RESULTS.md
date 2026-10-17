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
