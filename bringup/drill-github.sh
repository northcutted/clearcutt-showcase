#!/usr/bin/env bash
# The CVE drill (docs/demo-script.md, Act 6) on GitHub: the counterpart of
# prototype/scripts/drill.sh, which ran it against a local registry. Dry run
# by default: changes are printed, not made.
#
#   bringup/drill-github.sh --org NAME [--apply] [options] stage|respond|status
#
#   stage     open a platform pull request labelled DRILL that holds OpenSSL 3
#             (libcrypto3/libssl3 3.6.3-r4, CVE-2026-14456) in every run image
#             and libxml2 2.13.6 (libxml2.so.2) in run-python and build-python,
#             re-locked; wait for its gate and merge it. platform.yml publishes,
#             notify wakes the apps, and their fleets move onto the held images
#             (catalog's rebase is refused and it gets a rebuild PR). That is
#             the "before" state.
#   respond   the same with the holds released ("Release the OpenSSL and
#             libxml2 holds"): the live part of the demo.
#   status    read-only: the last DRILL merge, the platform's publish, and in
#             each app the fleet and image runs, the bot's pull requests, and
#             the image its latest tag holds, timed from that merge.
#
# Options:
#   --org NAME        the showcase organization
#   --apply           make the changes (default: dry run)
#   --offline         don't read from GitHub either
#   --no-merge        stage/respond: open the pull request and stop (merge it
#                     yourself, e.g. live in the browser); status times from
#                     whenever it was merged
#   --merge-bot-prs   stage/respond: after the merge, wait for each app's
#                     factory/rebase/<app> pull request, its checks, and merge
#                     it (so no build from an old lock moves latest back, F6)
#   --work DIR        work directory (default bringup/.work/ORG)
#   --platform-clone URL  clone the platform from URL instead of GitHub (a
#                     local copy, to rehearse the dry run without GitHub)
#
# stage and respond need gh, git, python3, and clearcutt-factory (the release
# the platform uses) to re-lock the held images.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

apps=(checkout storefront catalog)
held_images=(run-go run-python run-node build-python)
holds=$root/prototype/scripts/drill-holds.py
org='' cmd='' merge=true merge_bot_prs=false work='' platform_clone=''

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while (($#)); do
  case $1 in
    --org) org=${2:?}; shift ;;
    --apply) APPLY=true ;;
    --offline) OFFLINE=true ;;
    --no-merge) merge=false ;;
    --merge-bot-prs) merge_bot_prs=true ;;
    --work) work=${2:?}; shift ;;
    --platform-clone) platform_clone=${2:?}; shift ;;
    -h | --help) usage 0 ;;
    stage | respond | status) cmd=$1 ;;
    *) printf 'unknown argument: %s\n\n' "$1" >&2; usage 2 ;;
  esac
  shift
done
[[ -n $org && -n $cmd ]] || usage 2
[[ $APPLY == true && $OFFLINE == true ]] && die "--apply needs GitHub; drop --offline" 2
work=${work:-$here/.work/$org}
platform=$org/platform

mode="dry run (--apply to change)"
[[ $APPLY == true ]] && mode=apply
[[ $OFFLINE == true ]] && mode="offline dry run"
[[ $cmd == status ]] && mode="read-only"
printf '%sCVE drill on GitHub%s: %s in %s, %s\n' "$_b" "$_n" "$cmd" "$org" "$mode"

# ---------------------------------------------------------------------------
# change ACTION TITLE: apply or release the holds in a platform pull request.
change() {
  local action=$1 title=$2 branch dir body
  need git python3
  [[ $OFFLINE == true ]] || need gh
  [[ $APPLY == true ]] && need clearcutt-factory
  branch=drill/$cmd-$(date -u +%Y%m%dT%H%M%SZ)
  dir=$work/drill/platform

  say "Check out $platform main"
  if [[ $OFFLINE == true && -z $platform_clone ]]; then
    note "(offline) would clone or fetch https://github.com/$platform"
    return 0
  fi
  if [[ -d $dir/.git ]]; then
    git -C "$dir" fetch -q origin main
  elif [[ -n $platform_clone ]]; then
    mkdir -p "$(dirname "$dir")"
    git clone -q "$platform_clone" "$dir"
  else
    mkdir -p "$(dirname "$dir")"
    gh repo clone "$platform" "$dir" -- -q
  fi
  git -C "$dir" reset -q --hard
  git -C "$dir" checkout -q -B "$branch" origin/main
  ok "$platform main at $(git -C "$dir" rev-parse --short HEAD); holds: $(python3 -I "$holds" show "$dir")"

  say "$title"
  # The holds edit the working copy only; nothing leaves this machine until
  # the push below, so the diff shows in a dry run too.
  python3 -I "$holds" "$action" "$dir"
  if git -C "$dir" diff --quiet; then
    ok "nothing to change: the holds are already $([[ $action == apply ]] && echo held || echo released) on main"
    return 0
  fi
  git -C "$dir" --no-pager diff --stat | sed 's/^/   /'
  note "re-lock what the holds touch (the PR's gate checks lock and Containerfile are current)"
  for img in "${held_images[@]}"; do act_in "$dir" clearcutt-factory lock -f "images/$img/image.yaml"; done
  act git -C "$dir" add -A
  act git -C "$dir" commit -q -m "$title"
  git_push "$dir" "$branch"

  body=$work/drill/body.md
  {
    echo "**DRILL** (docs/demo-script.md, Act 6): $title."
    echo
    if [[ $action == apply ]]; then
      echo "- OpenSSL 3 (libcrypto3, libssl3) held at 3.6.3-r4 in every run image: CVE-2026-14456 (High), fixed in 3.6.3-r5."
      echo "- libxml2 held at 2.13.6-r3 (libxml2.so.2) in run-python and build-python, instead of libxml2-16 (2.15.x): an ABI hold."
      echo
      echo "Merging publishes the held images; the apps' fleets move onto them (catalog's rebase is refused and gets a rebuild pull request)."
    else
      echo "Releases both holds: OpenSSL 3 and libxml2 resolve to their fixed builds again (the lock diffs show the exact versions)."
      echo
      echo "Merging publishes the fixed images; notify wakes checkout, catalog, and storefront. checkout and storefront are rebased within minutes; catalog's rebase is refused (it links libxml2.so.2) and it gets a rebuild pull request."
    fi
    echo
    echo "Lines marked \`# DRILL hold\` are the holds. Opened by bringup/drill-github.sh in the showcase repository."
  } >"$body"
  act gh label create DRILL --repo "$platform" --color B60205 --description "CVE drill (showcase demo, Act 6)" --force
  act gh pr create --repo "$platform" --head "$branch" --base main --title "$title" --body-file "$body" --label DRILL
  if [[ $merge != true ]]; then
    note "--no-merge: merge it yourself once the gate is green; then: drill-github.sh --org $org status"
    return 0
  fi
  say "Wait for the gate, then merge"
  checks_registered "$platform" "$branch"
  act gh pr checks "$branch" --repo "$platform" --watch --fail-fast
  act gh pr merge "$branch" --repo "$platform" --squash --delete-branch
  note "once merged, platform.yml publishes (about 8 minutes), then notify wakes the apps"
  [[ $merge_bot_prs == true ]] && merge_bot_prs_after "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  return 0
}

# checks_registered REPO PR: wait (up to 3 minutes) until the pull request
# has checks, so `gh pr checks --watch` has something to watch.
checks_registered() {
  [[ $APPLY == true ]] || return 0
  local _
  for _ in $(seq 18); do
    [[ $(look gh pr checks "$2" --repo "$1" --json name --jq length || echo 0) -gt 0 ]] && return 0
    sleep 10
  done
  warn "$1: no checks on $2 after 3 minutes"
}

# merge_bot_prs_after TIME: for each app, wait (up to an hour) for the fleet's
# factory/rebase/<app> pull request updated after TIME, then for its checks,
# and merge it.
merge_bot_prs_after() {
  local since=$1 app branch n deadline
  say "Merge the apps' fleet pull requests as they come"
  for app in "${apps[@]}"; do
    branch=factory/rebase/$app
    if [[ $APPLY != true ]]; then
      act gh pr checks "$branch" --repo "$org/$app" --watch
      act gh pr merge "$branch" --repo "$org/$app" --squash --delete-branch
      continue
    fi
    deadline=$(($(date +%s) + 3600))
    while :; do
      n=$(look gh pr list --repo "$org/$app" --head "$branch" --state open --json number,updatedAt \
        --jq "map(select(.updatedAt >= \"$since\")) | .[0].number // empty" || true)
      [[ -n $n ]] && break
      (($(date +%s) < deadline)) || { warn "$app: no fleet pull request after an hour; skipping"; continue 2; }
      sleep 30
    done
    note "$app: pull request #$n"
    checks_registered "$org/$app" "$n"
    act gh pr checks "$n" --repo "$org/$app" --watch || { warn "$app #$n: checks failed; not merging"; continue; }
    act gh pr merge "$n" --repo "$org/$app" --squash --delete-branch
  done
}

# ---------------------------------------------------------------------------
# status: what happened since the last DRILL merge. Only reads.
status() {
  [[ $OFFLINE == true ]] && { note "(offline) status reads GitHub; nothing to show"; return 0; }
  need gh jq
  local drill t0 held app
  say "Last DRILL pull request in $platform"
  drill=$(look gh pr list --repo "$platform" --label DRILL --state merged --limit 1 --json number,title,mergedAt,url --jq '.[0] // empty' || true)
  if [[ -z $drill ]]; then
    note "no merged DRILL pull request yet; times below are absolute"
    t0=0
  else
    jq -r '"   #\(.number) \(.title)\n   merged \(.mergedAt)  \(.url)"' <<<"$drill"
    t0=$(jq -r '.mergedAt | fromdateiso8601' <<<"$drill")
  fi
  held=$(look gh api "repos/$platform/contents/images/_shared/run.yaml" -H 'Accept: application/vnd.github.raw' | grep -c 'DRILL hold' || true)
  note "holds on platform main: $([[ ${held:-0} -gt 0 ]] && echo held || echo released)"

  # runs REPO WORKFLOW: the workflow's runs since t0, timed from it.
  runs() {
    look gh run list --repo "$1" --workflow "$2" --limit 15 \
      --json event,status,conclusion,createdAt,updatedAt,url,displayTitle \
      --jq "map(select((.createdAt | fromdateiso8601) >= $t0)) | reverse | .[] |
        \"   \(.event | .[0:22] | . + \" \" * (22 - length)) \(.status)/\(.conclusion // \"-\") \" +
        (if $t0 > 0 then \"t+\(((.createdAt | fromdateiso8601) - $t0) / 60 | floor)m → t+\(((.updatedAt | fromdateiso8601) - $t0) / 60 | floor)m\"
         else \"\(.createdAt) → \(.updatedAt)\" end) + \"  \(.url)\"" || true
  }

  say "platform: platform.yml"
  runs "$platform" platform.yml
  for app in "${apps[@]}"; do
    say "$app"
    runs "$org/$app" factory.yml
    look gh pr list --repo "$org/$app" --search "head:factory/" --state all --limit 5 \
      --json number,title,state,createdAt,mergedAt,url \
      --jq "map(select((.createdAt | fromdateiso8601) >= $t0 or .state == \"OPEN\")) | .[] |
        \"   PR #\(.number) \(.state) \(.title)  \(.url)\"" || true
    if command -v crane >/dev/null 2>&1; then
      note "ghcr.io/$org/apps/$app:latest → $(look crane digest "ghcr.io/$org/apps/$app:latest" || echo '(unknown)')"
    fi
  done
  say "showcase: estate.yml"
  runs "$org/showcase" estate.yml
  note "portal: https://$org.github.io/showcase/"
}

case $cmd in
  stage) change apply "DRILL: hold OpenSSL 3 and libxml2 2.13" ;;
  respond) change release "Release the OpenSSL and libxml2 holds" ;;
  status) status ;;
esac
