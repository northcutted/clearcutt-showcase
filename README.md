# ClearCutt showcase

An organization that has adopted every ClearCutt tool, running for real under
[northcutted](https://github.com/northcutted):

- [clearcutt-factory](https://github.com/northcutted/clearcutt-factory) builds and maintains the images:
  [platform](https://github.com/northcutted/clearcutt-showcase-platform) (run and build images, stacks, the shared org profile)
  and three app teams, [checkout](https://github.com/northcutted/clearcutt-showcase-checkout) (Go),
  [catalog](https://github.com/northcutted/clearcutt-showcase-catalog) (Python with a C extension), and
  [storefront](https://github.com/northcutted/clearcutt-showcase-storefront) (Node.js), publishing to `ghcr.io/northcutted/clearcutt-showcase/`.
- [clearcutt-verify](https://github.com/northcutted/clearcutt-verify) verifies the estate every day and
  whenever something is published ([`estate/`](estate/), [`estate.yml`](.github/workflows/estate.yml)).
- [clearcutt-portal](https://github.com/northcutted/clearcutt-portal) publishes the result:
  **https://northcutted.github.io/clearcutt-showcase/**

New here? **[Start here](docs/start-here.md)**, then the **[trust model](docs/trust-model.md)**: who signs what, what the verdicts mean, and what they don't prove.

Documents:

- [Plan](docs/plan.md): repositories, registry, images, stacks, apps, trust, automation, settings, and gaps.
- [Demo script](docs/demo-script.md): each step and what it proves, including the CVE drill.
- [Issues filed](docs/issues.md): what each tool must provide, and every fix (the one status table).
- [Assessment](docs/assessment.md): the second independent assessment and the work it set.
- [Prototype](prototype/README.md): the whole fleet on one laptop (phase 1), and what it found.
- [Bring-up](bringup/README.md): how this was set up, and the drill driver
  (`bringup/drill-github.sh stage|respond|status`).
- [CVE drill results](bringup/DRILL-RESULTS.md): the drill run for real, with every run, pull
  request, and timing.
