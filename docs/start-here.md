# Start here

ClearCutt is three tools that share data formats, not code:

| Tool | Job | Start with it when |
|---|---|---|
| [clearcutt-verify](https://github.com/northcutted/clearcutt-verify) | Checks an estate of container images, whoever built them: which image is built on which (by layer digest), how stale each is, what signed evidence each carries, and whether it meets a policy. Writes the estate report. | you have images and want to know what is in them and what is actually proven |
| [clearcutt-portal](https://github.com/northcutted/clearcutt-portal) | Publishes the estate report as a static site. | you want the report where people will read it |
| [clearcutt-factory](https://github.com/northcutted/clearcutt-factory) | Builds images from YAML: every input locked, reproducible, signed, attested; rebases apps onto patched bases without the app team. | you want images you can rebuild bit for bit and patch in minutes |

**See it running first.** The showcase is a fictional organization (a
platform team, three app teams, a security view) running all three on
GitHub: [the portal](https://northcutted.github.io/clearcutt-showcase/),
[the repositories](https://github.com/northcutted?tab=repositories&q=clearcutt-showcase),
and [the drill](../bringup/DRILL-RESULTS.md) in which a CVE in a base
image reached every app, patched, in about 22 minutes.

**Then read the [trust model](trust-model.md)**: who signs what, what each
tool's words mean, and what a green result does not prove.

## The order to adopt in

1. **verify, on the images you already have** (an afternoon). No rebuild,
   no new pipeline: point it at a registry namespace or a list of
   references, and read what it can and cannot prove about them: which
   bases each image is really built on, how far behind they are, and which
   images carry evidence nobody can check.
2. **portal** (an hour). Publish that report on every run, with its
   history.
3. **factory, for one app** (a week). The app team keeps its code; the
   platform team owns the base images and stacks it builds on.
4. **factory for the platform**: run and build images, stacks, and a
   shared signed profile, so a CVE fix in a base reaches every app by
   itself.

## The app developer's loop

An app repository holds the app's code, its `app.yaml` (which stack it
builds on, how to smoke-test it), and the lock factory writes. To build
and test it on a laptop exactly as CI does, with nothing pushed:

```sh
git clone https://github.com/northcutted/clearcutt-showcase-checkout
cd clearcutt-showcase-checkout/checkout
clearcutt-factory build -f app.yaml     # both platforms, smoke test, SBOM, scan, gate
```

It needs `clearcutt-factory` ([install](https://github.com/northcutted/clearcutt-factory/blob/main/docs/adopting.md#1-install)),
Docker or Podman, `syft`, `grype`, and `cosign`. Everything it builds on (the
stack, the build and run images, the shared profile) is pulled from the
registry by the digests the lock pins, and the stack's and profile's
signatures are checked first.

Measured on 2026-10-18 (an Apple-silicon laptop, Podman, factory v0.3.0):
28 seconds with warm caches, and the result was **the same digest CI
published** (`sha256:b2f56e8e…`): the laptop reproduced the release bit
for bit. With Podman on macOS, keep the repository and `--out` under your
home directory: the Podman VM can't see `/tmp`.

What the app team never does: write a Dockerfile, pick a base image, or
chase an OS CVE. When the platform publishes a patched run image, the
app's fleet job rebases it (or, if a rebase isn't safe, opens a rebuild
pull request) without the app team. The app's own dependencies
(`go.mod`, `package.json`, `requirements.txt`) are the team's, kept current
by Dependabot.

## Where things are

| You want | Go to |
|---|---|
| Who signs what; what the verdicts mean | [trust-model.md](trust-model.md) |
| The showcase's plan and its decisions | [plan.md](plan.md) |
| Every issue the showcase found, and its fix | [issues.md](issues.md) |
| The latest independent assessment and the work it set | [assessment.md](assessment.md) |
| Bringing the showcase up in your own account or organization | [bringup/README.md](../bringup/README.md) |
| A 30-minute demo script | [demo-script.md](demo-script.md) |
