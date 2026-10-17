#!/usr/bin/env bash
# The CVE drill (docs/demo-script.md, Act 6) on GitHub: the counterpart of
# prototype/scripts/drill.sh, which ran it against a local registry. Dry run
# by default: changes are printed, not made.
#
#   bringup/drill-github.sh --owner NAME --owner-type user|org [--apply] [options] stage|respond|continue|status
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
#   continue  pick up the latest DRILL pull request where stage or respond
#             left it (after --no-merge, or an interruption): merge it once
#             green, then follow it through with the same options
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
#   --no-merge        stage/respond: open the pull request and stop (merge it
#                     yourself, e.g. live in the browser); status times from
#                     whenever it was merged
#   --wake-apps       stage/respond: after the merge, wait for the platform's
#                     publish, then start each app's fleet with workflow_dispatch
#                     (what notify's repository_dispatch does when the GitHub
#                     App exists; without it notify can't reach the apps)
#   --merge-bot-prs   stage/respond: then wait for each app's
#                     factory/rebase/<app> pull request, its checks, and merge
#                     it (so no build from an old lock moves latest back, F6),
#                     and wait for the publish that follows. A pull request the
#                     workflow's own token opened (no App) gets no CI until a
#                     person acts, so it is closed and reopened first
#   --estate          stage/respond: last, run the showcase's estate workflow
#                     (verify and portal) and wait for it
#   --git-protocol P  https (default; gh's token) or ssh, to clone and push the
#                     platform repository
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
owner='' owner_type=org prefix='' prefix_set=false cmd='' merge=true merge_bot_prs=false work='' platform_clone=''
wake_apps=false estate=false git_protocol=https t0=0

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
    --git-protocol) git_protocol=${2:?}; shift ;;
    --work) work=${2:?}; shift ;;
    --platform-clone) platform_clone=${2:?}; shift ;;
    -h | --help) usage 0 ;;
    stage | respond | continue | status) cmd=$1 ;;
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
    [[ -n $platform_clone ]] || git -C "$dir" remote set-url origin "$(remote_url "$OWNER" "$(repo_of platform)")"
    git -C "$dir" fetch -q origin main
  else
    mkdir -p "$(dirname "$dir")"
    git clone -q "${platform_clone:-$(remote_url "$OWNER" "$(repo_of platform)")}" "$dir"
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
  finish "$branch"
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
    say "Wait for the gate, then merge"
    wait_checks "$platform" "$pr" || die "the gate didn't pass on $platform $pr"
    merge_pr "$platform" "$pr" || die "couldn't merge $platform $pr"
    t0=$(date +%s)
  fi
  since=$(jq -rn --argjson t "$t0" '$t | todate')
  tnote "merged $platform: $(look gh pr view "$pr" --repo "$platform" --json url --jq .url || echo "$pr")"
  note "platform.yml publishes (about 8 minutes), then notify wakes the apps (with the GitHub App)"
  if [[ $wake_apps == true || $merge_bot_prs == true || $estate == true ]]; then
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
  if [[ $estate == true ]]; then
    say "Refresh the estate: verify and portal"
    act gh workflow run estate.yml --repo "$OWNER/$SHOWCASE"
    [[ $APPLY == true ]] && sleep 10
    wait_run "$OWNER/$SHOWCASE" estate.yml '' workflow_dispatch || true
    note "portal: $PAGES_URL"
  fi
  return 0
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
  if run_yaml=$(look gh api "repos/$platform/contents/images/_shared/run.yaml" -H 'Accept: application/vnd.github.raw'); then
    held=$(grep -c 'DRILL hold' <<<"$run_yaml" || true)
    note "holds on platform main: $([[ ${held:-0} -gt 0 ]] && echo held || echo released)"
  else
    note "holds on platform main: unknown (can't read $platform)"
  fi

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
  continue)
    [[ $OFFLINE != true ]] || die "continue reads the platform's pull requests: drop --offline" 2
    pr=$(look gh pr list --repo "$platform" --label DRILL --state all --limit 1 --json number --jq '.[0].number // empty' || true)
    [[ -n $pr ]] || die "no DRILL pull request in $platform"
    say "Continue $platform#$pr"
    finish "$pr"
    ;;
  status) status ;;
esac
