# ClearCutt showcase

An organization that has adopted every ClearCutt tool, running for real under
[<OWNER>](https://github.com/<OWNER>):

- [clearcutt-factory](https://github.com/northcutted/clearcutt-factory) builds and maintains the images:
  [platform](https://github.com/<OWNER>/<PREFIX>platform) (run and build images, stacks, the shared org profile)
  and three app teams, [checkout](https://github.com/<OWNER>/<PREFIX>checkout) (Go),
  [catalog](https://github.com/<OWNER>/<PREFIX>catalog) (Python with a C extension), and
  [storefront](https://github.com/<OWNER>/<PREFIX>storefront) (Node.js), publishing to `<REGISTRY>/`.
- [clearcutt-verify](https://github.com/northcutted/clearcutt-verify) verifies the estate every day and
  whenever something is published ([`estate/`](estate/), [`estate.yml`](.github/workflows/estate.yml)).
- [clearcutt-portal](https://github.com/northcutted/clearcutt-portal) publishes the result:
  **<PAGES_URL>**

Documents:

- [Plan](docs/plan.md): repositories, registry, images, stacks, apps, trust, automation, settings, and gaps.
- [Demo script](docs/demo-script.md): each step and what it proves, including the CVE drill.
- [Issues filed](docs/issues.md): what each tool must provide.
- [Prototype](prototype/README.md): the whole fleet on one laptop (phase 1), and what it found.
- [Bring-up](bringup/README.md): how this was set up, and the drill driver
  (`bringup/drill-github.sh stage|respond|status`).
