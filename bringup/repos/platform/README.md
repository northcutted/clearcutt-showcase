# platform

The <ORG> platform team's repository: what every app builds and runs on,
built and published with [clearcutt-factory](https://github.com/northcutted/clearcutt-factory).
Part of the [ClearCutt showcase](https://github.com/<ORG>/showcase).

| Path | What it is | Published as |
|---|---|---|
| `images/{build,run}-{go,python,node}/` | Build (toolchain) and run images: manifest, lock, Containerfile. Shared settings in `images/_shared/` | `ghcr.io/<ORG>/platform/<name>:<line>` |
| `stacks/{go,python,node}.yaml` | How to build each kind of app: build image, steps, run image | `ghcr.io/<ORG>/stacks/<name>:1`, signed by `stacks.yml` |
| `org/profile.yaml`, `org/trust.yaml` | The shared org profile every app repository extends, and the trust policy (who signs images and stacks) that factory and clearcutt-verify share | `ghcr.io/<ORG>/factory/org:1`, signed by `profile.yml` |
| `factory.org.yaml` | This repository's own profile (same gate, policy, and trust) | |

Workflows: `platform.yml` (pull requests gate; `main` publishes images, then
stacks and the profile, then notifies the repositories with the topic
`clearcutt-app`), `update-locks.yml` (weekly lock updates, or on demand).
