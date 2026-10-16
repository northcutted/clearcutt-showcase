# catalog

The catalog team's Python 3.14 HTTP service, on the platform's stack `python:1`, with a C extension (`catalog._feeds`) that validates supplier XML feeds through libxml2.
Built and kept current with [clearcutt-factory](https://github.com/northcutted/clearcutt-factory);
part of the [ClearCutt showcase](https://github.com/<ORG>/showcase).

- `catalog/app.yaml`: the app (a stack reference, labels, a smoke test). Its lock
  (`app.lock.yaml`) pins the stack, build and run images, and the shared org
  profile by digest; `app.Containerfile` is generated from them.
- `factory.org.yaml`: extends the platform's shared profile
  (`ghcr.io/<ORG>/factory/org:1`), adding only the registry.
- `.github/workflows/factory.yml`: pull requests are gated; `main` publishes
  `ghcr.io/<ORG>/apps/catalog`; the fleet rebases it onto each new run image
  (daily, and when the platform publishes) and opens a pull request pinning
  the lock; weekly, and when the platform publishes a stack or profile, a
  pull request moves the lock.
