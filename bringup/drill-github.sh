#!/usr/bin/env bash
# The CVE drills (docs/demo-script.md, Act 6, and drill 2 in
# bringup/DRILL-RESULTS.md) on GitHub: the counterpart of
# prototype/scripts/drill.sh, which ran the first against a local registry.
# Dry run by default: changes are printed, not made.
#
#   bringup/drill-github.sh --owner NAME --owner-type user|org [--apply] [options] COMMAND
#
# Drill 1 (OpenSSL and libxml2 in the run images):
#   stage     open a platform pull request labelled DRILL that holds OpenSSL 3
#             (libcrypto3/libssl3 3.6.3-r4, CVE-2026-14456) in every run image
#             and libxml2 2.13.6 (libxml2.so.2) in run-python and build-python,
#             re-locked; wait for its gate and merge it. platform.yml publishes,
#             notify wakes the apps, and their fleets move onto the held images
#             (catalog's rebase is refused and it gets a rebuild PR). That is
#             the "before" state.
#   respond   the same with the holds released ("Release the OpenSSL and
#             libxml2 holds"): the live part of the demo.
#
# Drill 2 (run it with --auto-merge --follow: nobody merges anything):
#   toolchain-stage    hold Go at 1.27.2 in build-go (GO-2026-6809): the
#             platform publishes build-go and stack go:1, notify sends
#             clearcutt.build-image-published and clearcutt.stack-published,
#             and checkout's update-locks opens "Rebuild checkout on the
#             newest build image", which auto-merges and publishes
#   toolchain-respond  release the Go hold, the same way
#   critical-stage     hold brotli at 1.2.0-r3 in build-node (CVE-2026-111497,
#             Critical): the pull request's gate fails, as it should; nothing
#             merges
#   critical-vex       add a drill VEX statement (org/vex/drill.openvex.json,
#             scoped to build-node) to that pull request, re-lock every image
#             to the new profile, and let it merge once the gate passes
#   critical-respond   release the brotli hold and remove the drill VEX
#   forge     send a forged clearcutt.run-image-published to each app, naming
#             a digest that isn't the run image's (--forge-digest, default
#             the run image of another stack), and check that the fleets ran
#             and changed nothing
#
#   untrusted-stage    act 5: add bringup/drill-untrusted.yml to the showcase
#             repository and run it (push REGISTRY/drill/untrusted:1 signed by
#             a throwaway key without a transparency log; build on it with
#             clearcutt-factory), name the image in estate/refs.txt, run the
#             estate
#   untrusted-cleanup  remove the workflow, the refs line, and the package
#
#   continue  pick up the latest DRILL pull request where a command left it
#             (after --no-merge, or an interruption): merge it once green
#             (or let auto-merge), then follow it through with the same options
#   status    read-only: the last DRILL merge, the platform's publish, and in
#             each app the fleet and image runs, the bot's pull requests, and
#             the image its latest tag holds, timed from that merge.
#
# Options:
#   --owner NAME      the showcase's owner, as for bringup.sh
#   --owner-type T    user or org (default org); --org NAME means --owner NAME --owner-type org
#   --prefix P        repository prefix, as for bringup.sh (default clearcutt-showcase-
#                     for a personal account, none for an organization)
#   --apply           make the changes (default: dry run)
#   --offline         don't read from GitHub either
#   --no-merge        open the pull request and stop (merge it yourself, e.g.
#                     live in the browser); status times from whenever it was
#                     merged
#   --auto-merge      turn on GitHub auto-merge (merge commit) for the DRILL
#                     pull request, so it merges when the platform's required
#                     check passes, instead of merging it here
#   --wake-apps       after the merge, wait for the platform's publish, then
#                     start each app's fleet with workflow_dispatch (what
#                     notify's repository_dispatch does when the GitHub App
#                     exists; without it notify can't reach the apps)
#   --merge-bot-prs   then wait for each app's factory/rebase/<app> pull
#                     request, its checks, and merge it (so no build from an
#                     old lock moves latest back, F6), and wait for the publish
#                     that follows. A pull request the workflow's own token
#                     opened (no App) gets no CI until a person acts, so it is
#                     closed and reopened first
#   --follow          with the GitHub App and auto-merge: wait for every run
#                     the platform's dispatches start in the apps, then for
#                     each bot pull request they open or update to merge
#                     itself (or fail), then for the publishes that follow,
#                     then for the estate refresh those trigger. Merges nothing
#   --estate          last, run the showcase's estate workflow (verify and
#                     portal) by hand and wait for it
#   --forge-digest D  forge: the digest the forged event names
#   --git-protocol P  https (default; gh's token) or ssh, to clone and push the
#                     platform repository
#   --work DIR        work directory (default bringup/.work/ORG)
#   --platform-clone URL  clone the platform from URL instead of GitHub (a
#                     local copy, to rehearse the dry run without GitHub)
#
# The commands that change the platform need gh, git, python3, and
# clearcutt-factory v0.4.1 or later (lock --update-package; image-scoped VEX).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

apps=(checkout storefront catalog)
holds=$root/prototype/scripts/drill-holds.py
owner='' owner_type=org prefix='' prefix_set=false cmd='' merge=true merge_bot_prs=false work='' platform_clone=''
wake_apps=false estate=false git_protocol=https t0=0 auto_merge=false follow=false forge_digest=''

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while (($#)); do
  case $1 in
    --owner) owner=${2:?}; shift ;;
    --owner-type) owner_type=${2:?}; shift ;;
    --org) owner=${2:?} owner_type=org; shift ;;
    --prefix) prefix=$2 prefix_set=true; shift ;;
    --apply) APPLY=true ;;
    --offline) OFFLINE=true ;;
    --no-merge) merge=false ;;
    --merge-bot-prs) merge_bot_prs=true ;;
    --wake-apps) wake_apps=true ;;
    --estate) estate=true ;;
    --auto-merge) auto_merge=true ;;
    --follow) follow=true ;;
    --forge-digest) forge_digest=${2:?}; shift ;;
    --git-protocol) git_protocol=${2:?}; shift ;;
    --work) work=${2:?}; shift ;;
    --platform-clone) platform_clone=${2:?}; shift ;;
    -h | --help) usage 0 ;;
    stage | respond | continue | status | forge | untrusted-stage | untrusted-cleanup) cmd=$1 ;;
    toolchain-stage | toolchain-respond | critical-stage | critical-vex | critical-respond) cmd=$1 ;;
    *) printf 'unknown argument: %s\n\n' "$1" >&2; usage 2 ;;
  esac
  shift
done
[[ -n $owner && -n $cmd ]] || usage 2
[[ $owner_type == user || $owner_type == org ]] || die "--owner-type is user or org" 2
[[ $prefix_set == true ]] || prefix=$(default_prefix "$owner_type")
showcase_names "$owner" "$prefix"
[[ $APPLY == true && $OFFLINE == true ]] && die "--apply needs GitHub; drop --offline" 2
work=${work:-$here/.work/$owner}
platform=$OWNER/$(repo_of platform)

mode="dry run (--apply to change)"
[[ $APPLY == true ]] && mode=apply
[[ $OFFLINE == true ]] && mode="offline dry run"
[[ $cmd == status ]] && mode="read-only"
printf '%sCVE drill on GitHub%s: %s in %s (%s, %s…), %s\n' "$_b" "$_n" "$cmd" "$OWNER" "$platform" "$PREFIX" "$mode"

# held_packages DIR IMAGE: the drill's packages that IMAGE's manifest lists
# (outside comments) or its lock pins (a package's name:), the only ones lock
# --update-package accepts, comma-separated: OpenSSL 3 in the run images,
# libxml2 under either name in run-python and build-python.
held_packages() {
  local p out=() m=$1/images/$2/image.yaml l=$1/images/$2/image.lock.yaml
  for p in $(python3 -I "$holds" packages x "${3:-cve}"); do
    if sed 's/#.*//' "$m" | grep -qE "(^|[^A-Za-z0-9_.-])$p([^A-Za-z0-9_.-]|\$)" ||
      grep -qE "^ *(- )?name: $p\$" "$l"; then out+=("$p"); fi
  done
  (IFS=,; printf '%s' "${out[*]}")
}

# ---------------------------------------------------------------------------
# checkout_platform BRANCH [BASE]: the platform clone in $work/drill/platform,
# on a fresh BRANCH from BASE (default origin/main). Sets dir.
checkout_platform() {
  local branch=$1 base=${2:-origin/main}
  dir=$work/drill/platform
  say "Check out $platform ${base#origin/}"
  if [[ -d $dir/.git ]]; then
    [[ -n $platform_clone ]] || git -C "$dir" remote set-url origin "$(remote_url "$OWNER" "$(repo_of platform)")"
    git -C "$dir" fetch -q origin
  else
    mkdir -p "$(dirname "$dir")"
    git clone -q "${platform_clone:-$(remote_url "$OWNER" "$(repo_of platform)")}" "$dir"
  fi
  git -C "$dir" reset -q --hard
  git -C "$dir" clean -fdq
  git -C "$dir" checkout -q -B "$branch" "$base"
  ok "$platform ${base#origin/} at $(git -C "$dir" rev-parse --short HEAD)"
}

# relock_all: re-lock every platform image, keeping every pin: after the
# shared profile changed (a VEX document added or removed), each lock pins
# the profile's new digest; nothing else moves, so unchanged images keep
# their digests and aren't republished.
relock_all() {
  local m
  note "re-lock every image to the changed profile (pins kept: only the profile digest moves)"
  for m in "$dir"/images/*/image.yaml; do
    act_in "$dir" clearcutt-factory lock -f "images/$(basename "$(dirname "$m")")/image.yaml"
  done
}

# change ACTION TITLE [SET] [VEX]: apply or release SET's holds (default
# cve) in a platform pull request; VEX add or remove also adds or removes
# the drill VEX statement.
change() {
  local action=$1 title=$2 set=${3:-cve} vex=${4:-} branch body img
  local -a held_images
  need git python3
  [[ $OFFLINE == true ]] || need gh
  [[ $APPLY == true ]] && need clearcutt-factory
  branch=drill/$cmd-$(date -u +%Y%m%dT%H%M%SZ)
  read -r -a held_images <<<"$(python3 -I "$holds" images x "$set")"

  if [[ $OFFLINE == true && -z $platform_clone ]]; then
    note "(offline) would clone or fetch https://github.com/$platform"
    return 0
  fi
  checkout_platform "$branch"
  note "holds ($set): $(python3 -I "$holds" show "$dir" "$set"); drill VEX: $(python3 -I "$holds" vex-show "$dir")"

  say "$title"
  # The holds edit the working copy only; nothing leaves this machine until
  # the push below, so the diff shows in a dry run too.
  python3 -I "$holds" "$action" "$dir" "$set"
  [[ -z $vex ]] || python3 -I "$holds" "vex-$vex" "$dir"
  if git -C "$dir" diff --quiet && [[ -z $(git -C "$dir" status --porcelain) ]]; then
    ok "nothing to change: the holds are already $([[ $action == apply ]] && echo held || echo released) on main"
    return 0
  fi
  git -C "$dir" --no-pager diff --stat | sed 's/^/   /'
  [[ -z $vex ]] || relock_all
  note "re-lock only the held packages (lock --update-package), so the PR moves nothing else"
  for img in "${held_images[@]}"; do
    act_in "$dir" clearcutt-factory lock -f "images/$img/image.yaml" --update-package "$(held_packages "$dir" "$img" "$set")"
  done
  act git -C "$dir" add -A
  act git -C "$dir" commit -q -m "$title"
  git_push "$dir" "$branch"

  body=$work/drill/body.md
  {
    echo "**DRILL**: $title."
    echo
    case $set:$action in
      cve:apply)
        echo "- OpenSSL 3 (libcrypto3, libssl3) held at 3.6.3-r4 in every run image: CVE-2026-14456 (High), fixed in 3.6.3-r5."
        echo "- libxml2 held at 2.13.6-r3 (libxml2.so.2) in run-python and build-python, instead of libxml2-16 (2.15.x): an ABI hold."
        echo
        echo "Merging publishes the held images; the apps' fleets move onto them (catalog's rebase is refused and gets a rebuild pull request)."
        ;;
      cve:release)
        echo "Releases both holds: OpenSSL 3 and libxml2 resolve to their fixed builds again (the lock diffs show the exact versions)."
        echo
        echo "Merging publishes the fixed images; notify wakes checkout, catalog, and storefront. checkout and storefront are rebased within minutes; catalog's rebase is refused (it links libxml2.so.2) and it gets a rebuild pull request."
        ;;
      toolchain:apply)
        echo "Drill 2, act 1 (a toolchain CVE, gap B): Go held at **1.27.2** in build-go, the toolchain of stack go:1. Go 1.27.2's standard library has GO-2026-6809 (CVE-2026-111943, crypto/x509; grype severity Unknown, so the Critical gate passes it), fixed in 1.27.3."
        echo
        echo "Merging publishes build-go and stack go:1; notify sends clearcutt.build-image-published and clearcutt.stack-published; checkout's update-locks opens \"Rebuild checkout on the newest build image\", which merges itself once its gate passes, and the rebuilt checkout carries the old standard library. No run image changes, so no rebase can help: only a rebuild can."
        ;;
      toolchain:release)
        echo "Drill 2, act 1: releases the Go hold; build-go resolves Go 1.27.3 again. Merging rebuilds checkout the same way, without GO-2026-6809."
        ;;
      critical:apply)
        echo "Drill 2, act 3: brotli held at **1.2.0-r3** in build-node: CVE-2026-111497 (Critical, fixed in 1.2.0-r7). The gate (failOn: critical, onlyFixed) must refuse build-node: this pull request is expected to stay red until a VEX statement covers it."
        ;;
      critical:release)
        echo "Drill 2, act 3, clean-up: releases the brotli hold in build-node and removes the drill VEX statement (org/vex/drill.openvex.json) from the shared profile. Every lock pins the profile's new digest; only build-node changes."
        ;;
    esac
    echo
    echo "Lines marked \`# DRILL hold\` are the holds. Opened by bringup/drill-github.sh in the showcase repository; results in bringup/DRILL-RESULTS.md."
  } >"$body"
  act gh label create DRILL --repo "$platform" --color B60205 --description "CVE drill (showcase drills)" --force
  act gh pr create --repo "$platform" --head "$branch" --base main --title "$title" --body-file "$body" --label DRILL
  [[ $set:$action == critical:apply ]] && { expect_red "$branch"; return 0; }
  finish "$branch"
}

# expect_red PR: wait for the DRILL pull request's checks and report that the
# gate refused it (the point of critical-stage); never merges.
expect_red() {
  local pr=$1
  say "Wait for the gate: it should fail"
  if [[ $APPLY != true ]]; then note "would wait for the checks of $platform $pr"; return 0; fi
  if wait_checks "$platform" "$pr"; then
    warn "the gate passed: the Critical didn't stop build-node"
  else
    ok "the gate refused it: $(look gh pr checks "$pr" --repo "$platform" --json name,bucket --jq '[.[] | select(.bucket == "fail") | .name] | join(", ")' || true)"
  fi
  note "next: drill-github.sh … critical-vex (adds the drill VEX statement to this pull request)"
}

# critical_vex: add the drill VEX statement to the open critical-stage pull
# request, re-locked; then let it merge and follow it.
critical_vex() {
  local pr head
  pr=$(look gh pr list --repo "$platform" --label DRILL --state open --json number,headRefName \
    --jq 'map(select(.headRefName | startswith("drill/critical-stage"))) | .[0].number // empty' || true)
  [[ -n $pr || $APPLY != true ]] || die "no open critical-stage DRILL pull request in $platform"
  head=$(look gh pr view "$pr" --repo "$platform" --json headRefName --jq .headRefName || echo drill/critical-stage)
  checkout_platform "$head" "origin/$head"
  say "Add the drill VEX statement (security-owned, org/vex/drill.openvex.json)"
  python3 -I "$holds" vex-add "$dir"
  relock_all
  act git -C "$dir" add -A
  act git -C "$dir" commit -q -m "DRILL: VEX statement: CVE-2026-111497 doesn't affect build-node"
  git_push "$dir" "$head"
  act gh pr edit "$pr" --repo "$platform" --title "DRILL: hold brotli 1.2.0-r3 in build-node, with a drill VEX statement"
  finish "$pr"
}

# wait_profile_published SHA: wait for the platform's push run for SHA to
# have published the shared profile (its profile / push job succeeded).
wait_profile_published() {
  local sha=$1 id='' _ c
  [[ $APPLY == true ]] || { note "would wait for the platform's profile job"; return 0; }
  for _ in $(seq 60); do
    id=$(look gh run list --repo "$platform" --workflow platform.yml --event push --commit "$sha" --limit 1 --json databaseId --jq '.[0].databaseId // empty' || true)
    [[ -n $id ]] && break
    sleep 10
  done
  [[ -n $id ]] || { warn "no platform run for $sha"; return 1; }
  for _ in $(seq 120); do
    c=$(look gh run view "$id" --repo "$platform" --json jobs --jq '.jobs[] | select(.name | test("^profile")) | select(.status == "completed") | .conclusion' | head -1 || true)
    [[ -n $c ]] && break
    sleep 15
  done
  [[ $c == success ]] || { warn "the profile job: ${c:-not finished}"; return 1; }
  tnote "shared profile published: $(look crane digest "$REGISTRY/factory/org:1" || echo '?')"
}

# estate_vex add|remove: list the drill VEX document in the estate's policy
# (estate/policy.yaml in the showcase repository), or take it out, and push
# to main. The estate reads VEX documents from the signed shared profile by
# file name, so the policy must name the drill document while the profile
# carries it, and not after: a named file the profile lacks stops the run.
estate_vex() {
  local action=$1 clone=$work/push/showcase f=estate/policy.yaml
  say "Estate policy: $action the drill VEX document"
  [[ -d $clone/.git ]] || die "no clone of $OWNER/$SHOWCASE at $clone"
  act git -C "$clone" pull -q --ff-only origin main
  if [[ $APPLY == true ]]; then
    python3 -I - "$clone/$f" "$action" <<'PY'
import pathlib, sys
p, action = pathlib.Path(sys.argv[1]), sys.argv[2]
without = "vex: [.profile/vex/catalog.openvex.json]\n"
with_drill = "vex: [.profile/vex/catalog.openvex.json, .profile/vex/drill.openvex.json]  # DRILL (drill 2, act 3): removed when the drill ends\n"
text = p.read_text()
src, dst = (without, with_drill) if action == "add" else (with_drill, without)
if dst not in text:
    if src not in text:
        sys.exit(f"{p}: expected text not found: {src!r}")
    p.write_text(text.replace(src, dst))
PY
  fi
  if git -C "$clone" diff --quiet; then ok "nothing to change"; return 0; fi
  git -C "$clone" --no-pager diff | sed 's/^/   /'
  act git -C "$clone" commit -q -am "DRILL: estate $([[ $action == add ]] && echo applies || echo stops applying) the drill VEX statement (drill 2, act 3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  act git -C "$clone" push -q origin main
  tnote "estate policy: drill VEX $([[ $action == add ]] && echo listed || echo unlisted)"
}

# untrusted_stage: act 5. Add bringup/drill-untrusted.yml to the showcase
# repository and run it: it pushes $REGISTRY/drill/untrusted:1 signed by a
# throwaway key (no transparency log), then builds on it with
# clearcutt-factory. estate/refs.txt names the image, and the estate runs.
untrusted_stage() {
  local clone=$work/push/showcase repo=$OWNER/$SHOWCASE ref=$REGISTRY/drill/untrusted:1 after id
  need gh jq git
  [[ -d $clone/.git ]] || die "no clone of $repo at $clone"
  t0=$(date +%s)
  say "Add the drill workflow and name the image in estate/refs.txt"
  act git -C "$clone" pull -q --ff-only origin main
  act cp "$here/drill-untrusted.yml" "$clone/.github/workflows/drill-untrusted.yml"
  if [[ $APPLY == true ]] && ! grep -qxF "$ref" "$clone/estate/refs.txt"; then
    printf '# DRILL (drill 2, act 5): signed by an untrusted key; removed when the drill ends.\n%s\n' "$ref" >>"$clone/estate/refs.txt"
  fi
  act git -C "$clone" add .github/workflows/drill-untrusted.yml estate/refs.txt
  act git -C "$clone" commit -q -m "DRILL: an untrusted-signed image in the namespace (drill 2, act 5)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  act git -C "$clone" push -q origin main
  [[ $APPLY == true ]] && sleep 10
  say "Push and sign the image with an untrusted key"
  after=$(date +%s)
  act gh workflow run drill-untrusted.yml --repo "$repo" -f step=publish
  [[ $APPLY == true ]] && sleep 10
  wait_run "$repo" drill-untrusted.yml '' workflow_dispatch "$after" || die "the drill image wasn't published"
  say "Ask clearcutt-factory to build on it"
  after=$(date +%s)
  act gh workflow run drill-untrusted.yml --repo "$repo" -f step=factory
  [[ $APPLY == true ]] && sleep 10
  wait_run "$repo" drill-untrusted.yml '' workflow_dispatch "$after" || true
  if [[ $APPLY == true ]]; then
    id=$(look gh run list --repo "$repo" --workflow drill-untrusted.yml --limit 1 --json databaseId --jq '.[0].databaseId' || true)
    look gh run view "$id" --repo "$repo" --log | grep -E 'factory exit status|error|refus|wrote |built ' | sed 's/^/   /' | tail -15 || true
  fi
  say "Run the estate"
  after=$(date +%s)
  act gh workflow run estate.yml --repo "$repo"
  [[ $APPLY == true ]] && sleep 10
  wait_run "$repo" estate.yml '' workflow_dispatch "$after" || note "(expected: the estate gate fails on the drill image)"
}

# untrusted_cleanup: take act 5 out again: the workflow, the refs line, and
# the image (its package).
untrusted_cleanup() {
  local clone=$work/push/showcase repo=$OWNER/$SHOWCASE ref=$REGISTRY/drill/untrusted:1 pkg
  say "Remove the drill workflow, the estate ref, and the image"
  act git -C "$clone" pull -q --ff-only origin main
  if [[ $APPLY == true ]]; then
    grep -vxF "$ref" "$clone/estate/refs.txt" | grep -v '^# DRILL (drill 2, act 5)' >"$clone/estate/refs.txt.new"
    mv "$clone/estate/refs.txt.new" "$clone/estate/refs.txt"
  fi
  act git -C "$clone" rm -q --ignore-unmatch .github/workflows/drill-untrusted.yml
  act git -C "$clone" commit -q -am "DRILL: remove the untrusted-signed image (drill 2, act 5 clean-up)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  act git -C "$clone" push -q origin main
  pkg=${REGISTRY#ghcr.io/"$OWNER"/}/drill/untrusted
  if [[ $owner_type == user ]]; then
    act gh api --method DELETE "/user/packages/container/${pkg//\//%2F}"
  else
    act gh api --method DELETE "/orgs/$OWNER/packages/container/${pkg//\//%2F}"
  fi
}

# forge: a forged clearcutt.run-image-published to each app (sent with gh's
# token, not the App), naming run-go with a digest that isn't run-go's. The
# fleets should run, re-resolve the run images from the registry, verify,
# and change nothing: no rebase, no pull request, no tag moved.
forge() {
  local app repo run digest now i
  local -a was=()
  need gh jq crane
  run=$REGISTRY/platform/run-go
  digest=${forge_digest:-$(look crane digest "$REGISTRY/platform/run-node:24" || echo sha256:0000000000000000000000000000000000000000000000000000000000000000)}
  say "Forge clearcutt.run-image-published: $run@$digest (run-go:1 is $(look crane digest "$run:1" || echo unknown))"
  for i in "${!apps[@]}"; do
    was[i]=$(look crane digest "$REGISTRY/apps/${apps[i]}:latest" || echo unknown)
    note "${apps[i]}:latest before: ${was[i]}"
  done
  t0=$(date +%s)
  for app in "${apps[@]}"; do
    repo=$OWNER/$(repo_of "$app")
    jq -n --arg image "$run@$digest" --arg repository "$run" --arg digest "$digest" --arg source "$platform" \
      '{event_type: "clearcutt.run-image-published", client_payload: {image: $image, repository: $repository, digest: $digest, tags: ["1"], roles: ["run"], source: $source, drill: "forged: this digest is not run-go:1"}}' >"$work/drill/forge.json"
    act gh api --method POST "repos/$repo/dispatches" --input "$work/drill/forge.json"
  done
  tnote "forged events sent"
  [[ $APPLY == true ]] || return 0
  sleep 15
  for app in "${apps[@]}"; do
    wait_run "$OWNER/$(repo_of "$app")" factory.yml '' repository_dispatch "$((t0 - 5))" || warn "$app: the fleet run didn't succeed"
  done
  say "What changed"
  for i in "${!apps[@]}"; do
    app=${apps[i]} repo=$OWNER/$(repo_of "${apps[i]}")
    now=$(look crane digest "$REGISTRY/apps/$app:latest" || echo unknown)
    if [[ $now == "${was[i]}" ]]; then ok "$app:latest unchanged ($now)"; else warn "$app:latest moved: ${was[i]} → $now"; fi
    look gh pr list --repo "$repo" --search "head:factory/" --state all --limit 5 --json number,title,createdAt,updatedAt \
      --jq "map(select((.updatedAt | fromdateiso8601) >= $t0)) | if length == 0 then \"   no bot pull request opened or updated\" else .[] | \"   PR #\\(.number) \\(.title) (updated)\" end" || true
  done
}

# finish PR: merge the platform's DRILL pull request once its gate is green
# (unless it is merged already), then follow it through: the platform's
# publish, the apps' fleets, their pull requests, and the estate, as the
# options ask.
finish() {
  local pr=$1 state merged since sha
  state=$(look gh pr view "$pr" --repo "$platform" --json state --jq .state || echo OPEN)
  if [[ $state == MERGED ]]; then
    merged=$(look gh pr view "$pr" --repo "$platform" --json mergedAt --jq .mergedAt)
    t0=$(jq -rn --arg t "$merged" '$t | fromdateiso8601')
    note "$platform#$pr was merged at $merged"
  else
    if [[ $merge != true ]]; then
      note "--no-merge: merge it yourself once the gate is green; then: drill-github.sh --owner $OWNER --owner-type $owner_type continue"
      return 0
    fi
    if [[ $auto_merge == true ]]; then
      say "Turn on auto-merge: GitHub merges it when the required check passes"
      act gh pr merge "$pr" --repo "$platform" --auto --merge
      wait_merged "$platform" "$pr" || die "$platform $pr didn't merge (its gate failed, or auto-merge is off)"
      merged=$(look gh pr view "$pr" --repo "$platform" --json mergedAt --jq .mergedAt || true)
      t0=$(jq -rn --arg t "$merged" '$t | fromdateiso8601' 2>/dev/null || date +%s)
    else
      say "Wait for the gate, then merge"
      wait_checks "$platform" "$pr" || die "the gate didn't pass on $platform $pr"
      merge_pr "$platform" "$pr" || die "couldn't merge $platform $pr"
      t0=$(date +%s)
    fi
  fi
  since=$(jq -rn --argjson t "$t0" '$t | todate')
  tnote "merged $platform: $(look gh pr view "$pr" --repo "$platform" --json url --jq .url || echo "$pr")"
  note "platform.yml publishes (about 8 minutes), then notify wakes the apps (with the GitHub App)"
  if [[ $cmd == critical-vex || $cmd == critical-respond ]]; then
    sha=$(look gh pr view "$pr" --repo "$platform" --json mergeCommit --jq .mergeCommit.oid || true)
    say "Wait for the shared profile, then match the estate policy to it"
    wait_profile_published "$sha" && estate_vex "$([[ $cmd == critical-vex ]] && echo add || echo remove)"
  fi
  if [[ $wake_apps == true || $merge_bot_prs == true || $estate == true || $follow == true ]]; then
    sha=$(look gh pr view "$pr" --repo "$platform" --json mergeCommit --jq .mergeCommit.oid || true)
    say "Wait for the platform's publish"
    wait_run "$platform" platform.yml "$sha" push || return 1
  fi
  if [[ $wake_apps == true ]]; then
    say "Wake the apps' fleets (workflow_dispatch, in place of notify)"
    for app in "${apps[@]}"; do act gh workflow run factory.yml --repo "$OWNER/$(repo_of "$app")" -f run=fleet; done
    tnote "fleets dispatched"
  fi
  [[ $merge_bot_prs == true ]] && merge_bot_prs_after "$since"
  [[ $follow == true ]] && follow_apps
  if [[ $estate == true ]]; then
    say "Refresh the estate: verify and portal"
    act gh workflow run estate.yml --repo "$OWNER/$SHOWCASE"
    [[ $APPLY == true ]] && sleep 10
    wait_run "$OWNER/$SHOWCASE" estate.yml '' workflow_dispatch || true
    note "portal: $PAGES_URL"
  fi
  return 0
}

# wait_merged REPO PR: poll (up to an hour) until the pull request is merged;
# fails when it is closed unmerged, a required check failed, or time runs out.
wait_merged() {
  local repo=$1 pr=$2 state _
  [[ $APPLY == true ]] || { note "would wait for $repo $pr to merge"; return 0; }
  for _ in $(seq 120); do
    state=$(look gh pr view "$pr" --repo "$repo" --json state --jq .state || true)
    case $state in
      MERGED) return 0 ;;
      CLOSED) return 1 ;;
    esac
    if [[ $(look gh pr checks "$pr" --repo "$repo" --required --json bucket --jq '[.[].bucket] | any(. == "fail" or . == "cancel")' || true) == true ]]; then
      return 1
    fi
    sleep 30
  done
  return 1
}

# runs_since REPO WORKFLOW EVENT AFTER: the workflow's runs for EVENT created
# at or after the epoch AFTER, one JSON object per line.
runs_since() {
  look gh run list --repo "$1" --workflow "$2" --event "$3" --limit 20 \
    --json databaseId,createdAt,updatedAt,status,conclusion,url,displayTitle \
    --jq ".[] | select((.createdAt | fromdateiso8601) >= $4) | tostring" || true
}

# follow_apps: what the platform's dispatches did, with nobody merging: wait
# for every app run they started, then for each bot pull request opened or
# updated since the merge to merge itself (auto-merge) or fail, then for the
# publishes those merges start, then for the estate refresh.
follow_apps() {
  local app repo _ pending pr state last=0 sha n
  [[ $APPLY == true ]] || { note "would follow the apps' runs, bot pull requests, publishes, and the estate"; return 0; }
  say "Follow the apps: the runs the dispatches started"
  for app in "${apps[@]}"; do
    repo=$OWNER/$(repo_of "$app")
    for _ in $(seq 120); do
      pending=$(runs_since "$repo" factory.yml repository_dispatch "$t0" | jq -s '[.[] | select(.status != "completed")] | length')
      [[ $pending == 0 ]] && break
      sleep 30
    done
    runs_since "$repo" factory.yml repository_dispatch "$t0" | jq -r --argjson t0 "$t0" \
      '"   \(.displayTitle // "dispatch" | .[0:40]): \(.conclusion) t+\(((.createdAt | fromdateiso8601) - $t0) / 60 | floor)m → t+\(((.updatedAt | fromdateiso8601) - $t0) / 60 | floor)m \(.url)"' |
      sed "s|^|   $app|"
  done
  say "Follow the bot's pull requests (auto-merge; nothing is merged here)"
  for app in "${apps[@]}"; do
    repo=$OWNER/$(repo_of "$app")
    for pr in $(look gh pr list --repo "$repo" --search "head:factory/" --state all --limit 10 --json number,updatedAt \
      --jq "map(select((.updatedAt | fromdateiso8601) >= $t0)) | .[].number" || true); do
      tnote "$app: $(look gh pr view "$pr" --repo "$repo" --json url,title,autoMergeRequest --jq '"\(.url) (\(.title)); auto-merge \(if .autoMergeRequest then "on" else "off" end)"' || echo "#$pr")"
      if wait_merged "$repo" "$pr"; then
        tnote "$app: #$pr merged by $(look gh pr view "$pr" --repo "$repo" --json mergedBy --jq .mergedBy.login || echo '?')"
        sha=$(look gh pr view "$pr" --repo "$repo" --json mergeCommit --jq .mergeCommit.oid || true)
        wait_run "$repo" factory.yml "$sha" push "$t0" || warn "$app: the publish after #$pr didn't succeed"
        n=$(date +%s); ((n > last)) && last=$n
      else
        state=$(look gh pr view "$pr" --repo "$repo" --json state --jq .state || true)
        warn "$app: #$pr is $state and didn't merge itself: $(look gh pr checks "$pr" --repo "$repo" --json name,bucket --jq '[.[] | select(.bucket != "pass" and .bucket != "skipping") | "\(.name)=\(.bucket)"] | join(", ")' || true)"
      fi
    done
  done
  say "Wait for the estate refresh (clearcutt.estate-changed)"
  ((last)) || last=$t0
  sleep 20
  local id
  for _ in $(seq 40); do
    id=$(runs_since "$OWNER/$SHOWCASE" estate.yml repository_dispatch "$((last - 900))" | jq -rs 'sort_by(.createdAt) | last | .databaseId // empty')
    [[ -n $id ]] && break
    sleep 15
  done
  if [[ -z $id ]]; then warn "no estate run after the last publish"; return 0; fi
  wait_run "$OWNER/$SHOWCASE" estate.yml '' repository_dispatch "$((last - 900))" || true
  note "portal: $PAGES_URL"
}

# tnote TEXT: a note timed from the merge.
tnote() {
  if ((t0)); then
    local d=$(($(date +%s) - t0))
    note "$(printf '[t+%dm%02ds] %s' $((d / 60)) $((d % 60)) "$*")"
  else
    note "$*"
  fi
}

# wait_run REPO WORKFLOW SHA EVENT [AFTER]: wait (up to 10 minutes) for
# WORKFLOW's run for commit SHA (any, if empty) and EVENT, created at or after
# the epoch AFTER (default: a minute before the merge), then for it to
# finish; fails if it didn't succeed.
wait_run() {
  local repo=$1 wf=$2 sha=$3 event=$4 after=${5:-$((t0 - 60))} id='' _ conclusion url failed
  if [[ $APPLY != true ]]; then
    note "would wait for $repo's $wf run ($event${sha:+, $sha})"
    return 0
  fi
  for _ in $(seq 60); do
    id=$(look gh run list --repo "$repo" --workflow "$wf" --event "$event" ${sha:+--commit "$sha"} --limit 1 \
      --json databaseId,createdAt --jq ".[] | select((.createdAt | fromdateiso8601) >= $after) | .databaseId" || true)
    [[ -n $id ]] && break
    sleep 10
  done
  [[ -n $id ]] || { warn "$repo: no $wf run for ${sha:-$event} after 10 minutes"; return 1; }
  url=$(look gh run view "$id" --repo "$repo" --json url --jq .url || true)
  tnote "$repo: $wf running: $url"
  # Poll (up to 2 hours) rather than gh run watch, so a dropped connection
  # only costs one poll.
  for _ in $(seq 240); do
    [[ $(look gh run view "$id" --repo "$repo" --json status --jq .status || true) == completed ]] && break
    sleep 30
  done
  conclusion=$(look gh run view "$id" --repo "$repo" --json conclusion --jq .conclusion || true)
  if [[ $conclusion == success ]]; then
    tnote "$repo: $wf success"
    return 0
  fi
  # Without the GitHub App, notify's dispatches to the apps fail (403): that
  # doesn't undo the publish, which is what the drill waits for.
  failed=$(look gh run view "$id" --repo "$repo" --json jobs \
    --jq '[.jobs[] | select(.conclusion == "failure") | .name] | join(", ")' || true)
  if [[ -n $failed && -z $(tr ',' '\n' <<<"$failed" | sed 's/^ *//' | grep -v '^notify-' || true) ]]; then
    tnote "$repo: $wf published; only $failed failed (no GitHub App to dispatch with)"
    return 0
  fi
  tnote "$repo: $wf $conclusion${failed:+ ($failed)}"
  return 1
}

# merge_pr REPO PR: squash-merge it. The repositories delete merged branches
# themselves (bringup.sh's settings step), so gh needn't; and a dropped
# connection after GitHub merged it isn't a failure: the state decides.
merge_pr() {
  act gh pr merge "$2" --repo "$1" --squash || true
  [[ $APPLY == true ]] || return 0
  local _
  for _ in 1 2 3 4 5 6; do
    [[ $(look gh pr view "$2" --repo "$1" --json state --jq .state || true) == MERGED ]] && return 0
    sleep 10
  done
  return 1
}

# wait_checks REPO PR: poll (up to 2 hours) until the pull request has checks
# and none is pending; fails if one failed or was cancelled. Polling, not gh
# pr checks --watch, so a dropped connection only costs one poll.
wait_checks() {
  local repo=$1 pr=$2 buckets _
  if [[ $APPLY != true ]]; then
    note "would wait for the checks of $repo $pr"
    return 0
  fi
  for _ in $(seq 240); do
    buckets=$(look gh pr checks "$pr" --repo "$repo" --json bucket --jq '[.[].bucket] | unique | join(",")' || true)
    case ,$buckets, in
      ,,) ;; # no checks yet, or a dropped connection
      *,pending,*) ;;
      *,fail,* | *,cancel,*) return 1 ;;
      *) return 0 ;;
    esac
    sleep 30
  done
  return 1
}

# merge_bot_prs_after TIME: the apps' fleet pull requests, all at once: wait
# (up to an hour each) for every app's factory/rebase/<app> pull request
# updated after TIME and start its CI, then merge each whose CI passes, then
# wait for the publishes those merges start.
merge_bot_prs_after() {
  local since=$1 app branch n deadline repo author head after i
  local -a prs=() heads=() afters=() merged=()
  say "Merge the apps' fleet pull requests as they come"
  if [[ $APPLY != true ]]; then
    for app in "${apps[@]}"; do
      branch=factory/rebase/$app
      wait_checks "$OWNER/$(repo_of "$app")" "$branch"
      merge_pr "$OWNER/$(repo_of "$app")" "$branch"
    done
    return 0
  fi
  for i in "${!apps[@]}"; do
    app=${apps[i]} branch=factory/rebase/${apps[i]} repo=$OWNER/$(repo_of "${apps[i]}")
    prs[i]='' heads[i]='' afters[i]=0 merged[i]=''
    deadline=$(($(date +%s) + 3600))
    while :; do
      n=$(look gh pr list --repo "$repo" --head "$branch" --state open --json number,updatedAt \
        --jq "map(select(.updatedAt >= \"$since\")) | .[0].number // empty" || true)
      [[ -n $n ]] && break
      (($(date +%s) < deadline)) || { warn "$app: no fleet pull request after an hour; skipping"; continue 2; }
      sleep 30
    done
    tnote "$app: pull request $(look gh pr view "$n" --repo "$repo" --json url,title --jq '"\(.url) (\(.title))"' || echo "#$n")"
    author=$(look gh pr view "$n" --repo "$repo" --json author --jq .author.login || true)
    head=$(look gh pr view "$n" --repo "$repo" --json headRefOid --jq .headRefOid || true)
    after=$(($(date +%s) - 120))
    if [[ $author == app/github-actions || $author == github-actions* ]]; then
      # Opened with the workflow's own token: its CI doesn't start by itself.
      after=$(date +%s)
      act gh pr close "$n" --repo "$repo" --comment "Reopening so CI runs (opened without the GitHub App)."
      act gh pr reopen "$n" --repo "$repo"
    fi
    prs[i]=$n heads[i]=$head afters[i]=$after
  done
  for i in "${!apps[@]}"; do
    [[ -n ${prs[i]} ]] || continue
    app=${apps[i]} repo=$OWNER/$(repo_of "${apps[i]}") n=${prs[i]}
    wait_run "$repo" factory.yml "${heads[i]}" pull_request "${afters[i]}" || { warn "$app #$n: CI didn't pass; not merging"; continue; }
    tnote "$app: #$n checks green"
    merge_pr "$repo" "$n" || { warn "$app #$n: couldn't merge it"; continue; }
    merged[i]=$(look gh pr view "$n" --repo "$repo" --json mergeCommit --jq .mergeCommit.oid || true)
    tnote "$app: #$n merged"
  done
  for i in "${!apps[@]}"; do
    [[ -n ${merged[i]} ]] || continue
    wait_run "$OWNER/$(repo_of "${apps[i]}")" factory.yml "${merged[i]}" push || warn "${apps[i]}: the publish after #${prs[i]} didn't succeed"
  done
}

# ---------------------------------------------------------------------------
# status: what happened since the last DRILL merge. Only reads.
status() {
  [[ $OFFLINE == true ]] && { note "(offline) status reads GitHub; nothing to show"; return 0; }
  need gh jq
  local drill t0 held app run_yaml
  say "Last DRILL pull request in $platform"
  drill=$(look gh pr list --repo "$platform" --label DRILL --state merged --limit 1 --json number,title,mergedAt,url --jq '.[0] // empty' || true)
  if [[ -z $drill ]]; then
    note "no merged DRILL pull request yet; times below are absolute"
    t0=0
  else
    jq -r '"   #\(.number) \(.title)\n   merged \(.mergedAt)  \(.url)"' <<<"$drill"
    t0=$(jq -r '.mergedAt | fromdateiso8601' <<<"$drill")
  fi
  local f
  for f in images/_shared/run.yaml images/build-go/image.yaml images/build-node/image.yaml org/vex/drill.openvex.json; do
    if run_yaml=$(look gh api "repos/$platform/contents/$f" -H 'Accept: application/vnd.github.raw'); then
      held=$(grep -c 'DRILL' <<<"$run_yaml" || true)
      note "$f on platform main: $([[ ${held:-0} -gt 0 ]] && echo "DRILL (held)" || echo released)"
    else
      note "$f on platform main: absent (or can't read $platform)"
    fi
  done

  # runs REPO WORKFLOW: the workflow's runs since t0, timed from it.
  runs() {
    look gh run list --repo "$1" --workflow "$2" --limit 15 \
      --json event,status,conclusion,createdAt,updatedAt,url,displayTitle \
      --jq "map(select((.createdAt | fromdateiso8601) >= $t0)) | reverse | .[] |
        \"   \(.event | .[0:22] | . + \" \" * (22 - length)) \(.status)/\(.conclusion // \"-\") \" +
        (if $t0 > 0 then \"t+\(((.createdAt | fromdateiso8601) - $t0) / 60 | floor)m → t+\(((.updatedAt | fromdateiso8601) - $t0) / 60 | floor)m\"
         else \"\(.createdAt) → \(.updatedAt)\" end) + \"  \(.url)\"" || true
  }

  say "$(repo_of platform): platform.yml"
  runs "$platform" platform.yml
  for app in "${apps[@]}"; do
    say "$(repo_of "$app")"
    runs "$OWNER/$(repo_of "$app")" factory.yml
    look gh pr list --repo "$OWNER/$(repo_of "$app")" --search "head:factory/" --state all --limit 5 \
      --json number,title,state,createdAt,mergedAt,url \
      --jq "map(select((.createdAt | fromdateiso8601) >= $t0 or .state == \"OPEN\")) | .[] |
        \"   PR #\(.number) \(.state) \(.title)  \(.url)\"" || true
    if command -v crane >/dev/null 2>&1; then
      note "$REGISTRY/apps/$app:latest → $(look crane digest "$REGISTRY/apps/$app:latest" || echo '(unknown)')"
    fi
  done
  say "$SHOWCASE: estate.yml"
  runs "$OWNER/$SHOWCASE" estate.yml
  note "portal: $PAGES_URL"
}

case $cmd in
  stage) change apply "DRILL: hold OpenSSL 3 and libxml2 2.13" ;;
  respond) change release "Release the OpenSSL and libxml2 holds" ;;
  toolchain-stage) change apply "DRILL: hold Go 1.27.2 in build-go (GO-2026-6809)" toolchain ;;
  toolchain-respond) change release "Release the Go hold in build-go" toolchain ;;
  critical-stage) change apply "DRILL: hold brotli 1.2.0-r3 in build-node (CVE-2026-111497, Critical)" critical ;;
  critical-vex) critical_vex ;;
  critical-respond) change release "Release the brotli hold and remove the drill VEX statement" critical remove ;;
  forge) forge ;;
  untrusted-stage) untrusted_stage ;;
  untrusted-cleanup) untrusted_cleanup ;;
  continue)
    [[ $OFFLINE != true ]] || die "continue reads the platform's pull requests: drop --offline" 2
    pr=$(look gh pr list --repo "$platform" --label DRILL --state all --limit 1 --json number --jq '.[0].number // empty' || true)
    [[ -n $pr ]] || die "no DRILL pull request in $platform"
    say "Continue $platform#$pr"
    finish "$pr"
    ;;
  status) status ;;
esac
