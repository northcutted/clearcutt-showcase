#!/usr/bin/env bash
# Phase 3 of the ClearCutt showcase (docs/plan.md §9): bring the organization
# up on GitHub from bringup/repos/. Dry run by default: every change is
# printed, nothing is changed. Re-run it as often as you like; each step
# checks what is already there and skips it.
#
#   bringup/bringup.sh --org NAME [--apply] [options]
#
# Options:
#   --org NAME            the GitHub organization (lowercase; create it on the web first)
#   --apply               make the changes (default: dry run)
#   --offline             don't read from GitHub either (dry run of the plan only)
#   --token app|pat       how the workflows open PRs and dispatch: a GitHub App
#                         (CLEARCUTT_APP_ID variable, CLEARCUTT_APP_PRIVATE_KEY secret)
#                         or a fine-grained PAT (CLEARCUTT_BOT_TOKEN secret). Default app
#   --secrets-at org|repo org secrets and variables scoped to the five repositories
#                         (default), or the same in each repository
#   --factory-ref REF     clearcutt-factory release tag or commit SHA (default v0.2.0)
#   --verify-ref REF      clearcutt-verify release tag or commit SHA (default v0.16.0)
#   --verify-version V    clearcutt-verify release to install (default: --verify-ref if
#                         a tag, else "source", which builds that commit)
#   --portal-ref REF      clearcutt-portal release tag or commit SHA (default v0.1.0)
#   --showcase-ref REF    commit of this repository to push as showcase's main (default HEAD)
#   --steps LIST          comma-separated subset of: preflight,org,render,repos,
#                         settings,secrets,platform,apps,showcase,pages,protect
#                         (default all but protect)
#   --protect             also protect main (required checks) and allow auto-merge
#   --wait                after pushing platform, wait for its first publish
#                         (up to 90 minutes) instead of stopping
#   --reset-secrets       set secrets and variables again even if they exist
#   --work DIR            work directory (default bringup/.work/ORG)
#
# Values are read from the environment if set, else asked for (never echoed):
#   CLEARCUTT_APP_ID, CLEARCUTT_APP_PRIVATE_KEY_FILE (path to the App's .pem),
#   CLEARCUTT_BOT_TOKEN.
#
# Exit codes: 0 done (or dry run), 1 error, 2 usage, 3 the organization
# doesn't exist yet, 4 waiting for the platform's first publish (re-run).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

repos=(platform checkout catalog storefront showcase)
apps=(checkout catalog storefront)
org='' token=app secrets_at=org
factory_ref=v0.2.0 verify_ref=v0.16.0 verify_version='' portal_ref=v0.1.0
showcase_ref=HEAD steps='' protect=false wait_publish=false reset_secrets=false work=''

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while (($#)); do
  case $1 in
    --org) org=${2:?}; shift ;;
    --apply) APPLY=true ;;
    --offline) OFFLINE=true ;;
    --token) token=${2:?}; shift ;;
    --secrets-at) secrets_at=${2:?}; shift ;;
    --factory-ref) factory_ref=${2:?}; shift ;;
    --verify-ref) verify_ref=${2:?}; shift ;;
    --verify-version) verify_version=${2:?}; shift ;;
    --portal-ref) portal_ref=${2:?}; shift ;;
    --showcase-ref) showcase_ref=${2:?}; shift ;;
    --steps) steps=${2:?}; shift ;;
    --protect) protect=true ;;
    --wait) wait_publish=true ;;
    --reset-secrets) reset_secrets=true ;;
    --work) work=${2:?}; shift ;;
    -h | --help) usage 0 ;;
    *) printf 'unknown argument: %s\n\n' "$1" >&2; usage 2 ;;
  esac
  shift
done

[[ -n $org ]] || { printf 'needs --org NAME\n\n' >&2; usage 2; }
[[ $org =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "--org $org: use the lowercase name (ghcr.io needs lowercase)" 2
[[ $token == app || $token == pat ]] || die "--token is app or pat" 2
[[ $secrets_at == org || $secrets_at == repo ]] || die "--secrets-at is org or repo" 2
[[ $APPLY == true && $OFFLINE == true ]] && die "--apply needs GitHub; drop --offline" 2
if [[ -z $steps ]]; then
  steps=preflight,org,render,repos,settings,secrets,platform,apps,showcase,pages
  [[ $protect == true ]] && steps+=,protect
fi
step() { [[ ,$steps, == *,$1,* ]]; }
work=${work:-$here/.work/$org}

tag_re='^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
sha_re='^[0-9a-f]{40}$'
for r in "$factory_ref" "$verify_ref" "$portal_ref"; do
  [[ $r =~ $tag_re || $r =~ $sha_re ]] || die "$r: pin a release tag (vX.Y.Z) or a full commit SHA" 2
done
# The image signer's identity ends in the ref factory's workflows are called
# by: a release tag, or the commit SHA they are pinned to (plan §4).
if [[ $factory_ref =~ $tag_re ]]; then
  factory_signer_ref='refs/tags/v\d+\.\d+\.\d+'
else
  factory_signer_ref='[0-9a-f]{40}'
fi
if [[ -z $verify_version ]]; then
  if [[ $verify_ref =~ $tag_re ]]; then verify_version=$verify_ref; else verify_version=source; fi
fi

mode="dry run (nothing changes; --apply to change)"
[[ $APPLY == true ]] && mode=apply
[[ $OFFLINE == true ]] && mode="offline dry run (no GitHub reads either)"
printf '%sClearCutt showcase bring-up%s: org %s, %s\n' "$_b" "$_n" "$org" "$mode"
note "factory $factory_ref, verify $verify_ref (installs $verify_version), portal $portal_ref; token: $token; secrets at: $secrets_at"
note "work directory: $work"

# ---------------------------------------------------------------------------
if step preflight; then
  say "Preflight"
  need git perl jq
  if [[ $OFFLINE != true ]]; then
    need gh
    gh auth status >/dev/null 2>&1 || die "gh isn't logged in: gh auth login"
    scopes=$(gh api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes: //p')
    if [[ -z $scopes ]]; then
      warn "can't read gh's token scopes (a fine-grained token?): it must administer $org and its repositories, write workflows, and read packages"
    else
      missing=()
      # Each needed scope, or one that includes it.
      for s in repo workflow admin:org 'read:packages|write:packages'; do
        found=false
        IFS='|' read -r -a alts <<<"$s"
        for alt in "${alts[@]}"; do [[ ", $scopes," == *", $alt,"* ]] && found=true; done
        [[ $found == true ]] || missing+=("${alts[0]}")
      done
      if ((${#missing[@]})); then
        msg="gh's token lacks ${missing[*]} (has: $scopes); run: gh auth refresh -s $(IFS=,; echo "${missing[*]}")"
        if [[ $APPLY == true ]]; then die "$msg"; else warn "$msg"; fi
      else
        ok "gh token scopes: $scopes"
      fi
    fi
    for pair in "clearcutt-factory $factory_ref" "clearcutt-verify $verify_ref" "clearcutt-portal $portal_ref"; do
      read -r tool ref <<<"$pair"
      if [[ $ref =~ $tag_re ]]; then
        if look gh api "repos/northcutted/$tool/releases/tags/$ref" --jq .tag_name >/dev/null; then
          ok "$tool $ref is released"
        elif [[ $APPLY == true ]]; then
          die "$tool $ref isn't released yet (pin a commit SHA with --${tool#clearcutt-}-ref, or wait for the release)"
        else
          warn "$tool $ref isn't released yet"
        fi
      fi
    done
  fi
  if step platform || step apps; then
    if command -v clearcutt-factory >/dev/null 2>&1 && command -v cosign >/dev/null 2>&1; then
      have=$(clearcutt-factory version 2>/dev/null | head -n 1 || true)
      if [[ $factory_ref =~ $tag_re && $have != *"$factory_ref"* ]]; then
        warn "local clearcutt-factory is '$have', not $factory_ref: locks written with it may not match CI's"
      else
        ok "local clearcutt-factory: $have"
      fi
    elif [[ $APPLY == true ]]; then
      die "the platform and apps steps lock manifests locally: install clearcutt-factory $factory_ref and cosign"
    else
      warn "clearcutt-factory and cosign are needed with --apply (the platform and apps steps lock locally)"
    fi
  fi
  if [[ -n $(git -C "$root" status --porcelain) ]] && step showcase; then
    warn "this repository has uncommitted changes; the showcase step pushes $showcase_ref only"
  fi
fi

# ---------------------------------------------------------------------------
if step org; then
  say "Organization $org"
  if [[ $OFFLINE == true ]]; then
    note "(offline) would check that https://github.com/$org exists"
  elif look gh api "orgs/$org" --jq .login >/dev/null; then
    ok "https://github.com/$org exists"
    if [[ $token == app ]]; then
      installs=$(look gh api "orgs/$org/installations" --jq '.installations[] | "\(.app_slug) (\(.repository_selection))"' || true)
      if [[ -n $installs ]]; then
        ok "GitHub Apps installed: $(paste -sd, - <<<"$installs")"
      else
        warn "no GitHub App installed in $org yet (or this token can't see installations): create and install it (bringup/README.md, step 2)"
      fi
    fi
  else
    printf '\n   %s does not exist. Organizations can only be created on the web:\n' "$org"
    printf '     https://github.com/account/organizations/new?plan=free\n'
    printf '   Name it %s (Free plan), then run this again.\n' "$org"
    exit 3
  fi
fi

# ---------------------------------------------------------------------------
# Render bringup/repos/* into the work directory with the placeholders filled.
render() {
  local r=$1 dst=$work/render/$1
  rm -rf "$dst"
  mkdir -p "$dst"
  cp -R "$here/repos/$r/." "$dst/"
  local f
  while IFS= read -r -d '' f; do
    ORG=$org FACTORY_REF=$factory_ref FACTORY_SIGNER_REF=$factory_signer_ref \
      VERIFY_REF=$verify_ref VERIFY_VERSION=$verify_version PORTAL_REF=$portal_ref \
      perl -pi -e 's/<ORG>/$ENV{ORG}/g; s/<FACTORY_REF>/$ENV{FACTORY_REF}/g;
        s/<FACTORY_SIGNER_REF>/$ENV{FACTORY_SIGNER_REF}/g; s/<VERIFY_REF>/$ENV{VERIFY_REF}/g;
        s/<VERIFY_VERSION>/$ENV{VERIFY_VERSION}/g; s/<PORTAL_REF>/$ENV{PORTAL_REF}/g' "$f"
  done < <(grep -rlE --null '<(ORG|FACTORY_REF|FACTORY_SIGNER_REF|VERIFY_REF|VERIFY_VERSION|PORTAL_REF)>' "$dst" || true)
  if grep -rnE '<(ORG|FACTORY_REF|FACTORY_SIGNER_REF|VERIFY_REF|VERIFY_VERSION|PORTAL_REF)>' "$dst"; then
    die "placeholders left in $dst"
  fi
}

if true; then # every later step reads the rendered files; it only writes the work directory
  say "Render bringup/repos into $work/render"
  for r in "${repos[@]}"; do render "$r"; done
  ok "rendered: $(cd "$work/render" && find . -type f | wc -l | tr -d ' ') files in ${repos[*]}"
fi

# ---------------------------------------------------------------------------
describe() {
  case $1 in
    platform) echo "Platform team: run and build images, stacks, and the shared ClearCutt org profile" ;;
    checkout) echo "Payments team: checkout service (Go, stack go:1)" ;;
    catalog) echo "Catalog team: catalog service (Python 3.14 with a C extension, stack python:1)" ;;
    storefront) echo "Web team: storefront (Node.js 24 TypeScript, stack node:1)" ;;
    showcase) echo "ClearCutt showcase: plan, demo, and the verified estate (clearcutt-verify + clearcutt-portal)" ;;
  esac
}

if step repos; then
  say "Repositories"
  for r in "${repos[@]}"; do
    if look gh repo view "$org/$r" --json name >/dev/null; then
      ok "$org/$r exists"
    else
      act gh repo create "$org/$r" --public --disable-wiki --description "$(describe "$r")"
    fi
  done
fi

# ---------------------------------------------------------------------------
if step settings; then
  say "Settings: Actions may create and approve pull requests; topics; branch cleanup"
  act gh api --method PUT "orgs/$org/actions/permissions/workflow" \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
  allowed=$(look gh api "orgs/$org/actions/permissions" --jq .allowed_actions || true)
  [[ -z $allowed || $allowed == all ]] || warn "$org allows only '$allowed' Actions: the workflows use northcutted/*, actions/*, docker/*, sigstore/*, and anchore/* actions"
  for r in "${repos[@]}"; do
    act gh api --method PUT "repos/$org/$r/actions/permissions/workflow" \
      -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
    act gh repo edit "$org/$r" --delete-branch-on-merge
  done
  for a in "${apps[@]}"; do act gh repo edit "$org/$a" --add-topic clearcutt-app; done
  act gh repo edit "$org/showcase" --homepage "https://$org.github.io/showcase/"
fi

# ---------------------------------------------------------------------------
# set_value KIND NAME VALUE: an Actions secret or variable, at the org (scoped
# to the five repositories) or in each repository.
set_value() {
  local kind=$1 name=$2 value=$3 r
  if [[ $secrets_at == org ]]; then
    act_secret "$value" gh "$kind" set "$name" --org "$org" --visibility selected --repos "$(IFS=,; echo "${repos[*]}")"
  else
    for r in "${repos[@]}"; do act_secret "$value" gh "$kind" set "$name" --repo "$org/$r"; done
  fi
}
# exists KIND NAME: whether the secret or variable is set (everywhere).
exists() {
  local kind=$1 name=$2 r
  [[ $reset_secrets == true ]] && return 1
  if [[ $secrets_at == org ]]; then
    look gh "$kind" list --org "$org" --json name --jq '.[].name' | grep -qx "$name"
  else
    for r in "${repos[@]}"; do look gh "$kind" list --repo "$org/$r" --json name --jq '.[].name' | grep -qx "$name" || return 1; done
  fi
}

if step secrets; then
  say "Credentials for the workflows ($token, at $secrets_at level)"
  if [[ $token == app ]]; then
    if exists variable CLEARCUTT_APP_ID; then ok "variable CLEARCUTT_APP_ID is set"; else
      id=${CLEARCUTT_APP_ID:-}
      [[ -z $id && $APPLY == true ]] && id=$(ask "GitHub App Client ID (or App ID)")
      set_value variable CLEARCUTT_APP_ID "${id:-<client id>}"
    fi
    if exists secret CLEARCUTT_APP_PRIVATE_KEY; then ok "secret CLEARCUTT_APP_PRIVATE_KEY is set"; else
      pem=${CLEARCUTT_APP_PRIVATE_KEY_FILE:-}
      [[ -z $pem && $APPLY == true ]] && pem=$(ask "path to the App's private key (.pem)")
      key=''
      if [[ $APPLY == true ]]; then
        [[ -r $pem ]] || die "can't read $pem"
        key=$(<"$pem")
        [[ $key == *"PRIVATE KEY-----"* ]] || die "$pem doesn't look like a PEM private key"
      fi
      set_value secret CLEARCUTT_APP_PRIVATE_KEY "$key"
    fi
  else
    if exists secret CLEARCUTT_BOT_TOKEN; then ok "secret CLEARCUTT_BOT_TOKEN is set"; else
      bot=${CLEARCUTT_BOT_TOKEN:-}
      [[ -z $bot && $APPLY == true ]] && bot=$(ask_secret "CLEARCUTT_BOT_TOKEN (fine-grained PAT; contents and pull requests read/write on the five repositories)")
      set_value secret CLEARCUTT_BOT_TOKEN "$bot"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# remote_empty REPO: whether the repository has no commits yet. Unknown
# (offline, or not created yet in a dry run) counts as empty.
remote_empty() {
  local out
  if out=$(look gh api "repos/$org/$1/commits?per_page=1" --jq 'length'); then
    [[ $out == 0 ]]
  else
    return 0
  fi
}

# push_new REPO DIR MESSAGE: commit DIR's contents as the first commit of
# REPO's main and push it.
push_new() {
  local r=$1 dir=$2 msg=$3
  act git -C "$dir" init -q -b main
  act git -C "$dir" add -A
  act git -C "$dir" commit -q -m "$msg"
  act git -C "$dir" remote add origin "https://github.com/$org/$r.git"
  git_push "$dir" main
}

# fresh REPO: a copy of the rendered repository to lock and push.
fresh() {
  local dir=$work/push/$1
  rm -rf "$dir"
  mkdir -p "$work/push"
  cp -R "$work/render/$1" "$dir"
  printf '%s' "$dir"
}

if step platform; then
  say "Push platform"
  if ! remote_empty platform; then
    ok "$org/platform already has commits; not pushing (change it with pull requests)"
  else
    dir=$(fresh platform)
    note "lock every platform image (pins wolfi-base, packages, BuildKit; writes each lock and Containerfile)"
    for m in "$dir"/images/*/image.yaml; do act_in "$dir" clearcutt-factory lock -f "${m#"$dir"/}"; done
    push_new platform "$dir" "Bring up the platform: images, stacks, and the shared org profile"
    note "platform.yml now publishes the images, then the stacks and the shared profile:"
    note "  https://github.com/$org/platform/actions"
  fi
fi

# ---------------------------------------------------------------------------
# What the apps need before they can be locked: the shared profile and the
# stacks, published and signed by the platform's workflows.
needed_packages=(factory/org stacks/go stacks/python stacks/node)
missing_packages() {
  local p vis
  for p in "${needed_packages[@]}"; do
    if vis=$(look gh api "orgs/$org/packages/container/${p//\//%2F}" --jq .visibility); then
      [[ $vis == public ]] || warn "ghcr.io/$org/$p is $vis: make it public (Package settings → Change visibility): https://github.com/orgs/$org/packages/container/${p//\//%2F}/settings"
    else
      printf '%s\n' "$p"
    fi
  done
}

if step apps; then
  say "Push the apps (after the platform's first publish)"
  if [[ $OFFLINE == true ]]; then
    note "(offline) would check that ghcr.io/$org/{${needed_packages[*]}} are published"
  else
    waited=0
    while left=$(missing_packages) && [[ -n $left ]]; do
      if [[ $APPLY != true ]]; then
        note "not published yet: $(paste -sd' ' - <<<"$left"); with --apply this step waits for (--wait) or stops at them"
        break
      fi
      if [[ $wait_publish != true ]] || ((waited >= 90)); then
        note "not published yet: $(paste -sd' ' - <<<"$left")"
        note "watch https://github.com/$org/platform/actions, then run this again (or pass --wait)"
        exit 4
      fi
      note "waiting for $(paste -sd' ' - <<<"$left") (${waited}m)"
      sleep 60
      waited=$((waited + 1))
    done
  fi
  for a in "${apps[@]}"; do
    if ! remote_empty "$a"; then
      ok "$org/$a already has commits; not pushing"
      continue
    fi
    dir=$(fresh "$a")
    note "$a: lock (verifies the shared profile and the stack against their signers, pins both)"
    act_in "$dir" clearcutt-factory lock -f "$a/app.yaml"
    push_new "$a" "$dir" "Bring up $a on the platform's stack"
  done
fi

# ---------------------------------------------------------------------------
if step showcase; then
  say "Push showcase (this repository at $showcase_ref, plus bringup/repos/showcase)"
  if ! remote_empty showcase; then
    ok "$org/showcase already has commits; not pushing"
  else
    sha=$(git -C "$root" rev-parse --verify "$showcase_ref^{commit}")
    dir=$work/push/showcase
    rm -rf "$dir"
    mkdir -p "$work/push"
    # A local clone and an overlay commit: the clone is only in the work
    # directory, so this runs in a dry run too.
    git clone -q --no-checkout "$root" "$dir"
    git -C "$dir" checkout -q -B main "$sha"
    git -C "$dir" remote set-url origin "https://github.com/$org/showcase.git"
    cp -R "$work/render/showcase/." "$dir/"
    git -C "$dir" add -A
    git -C "$dir" -c user.name="$(git -C "$root" config user.name || echo bringup)" \
      -c user.email="$(git -C "$root" config user.email || echo bringup@localhost)" \
      commit -q -m "Bring up the showcase estate: clearcutt-verify and clearcutt-portal"
    ok "prepared $dir: $(git -C "$dir" rev-list --count HEAD) commits, top: $(git -C "$dir" log -1 --format=%s)"
    git_push "$dir" main
  fi
fi

# ---------------------------------------------------------------------------
if step pages; then
  say "Pages for showcase: source GitHub Actions"
  if build=$(look gh api "repos/$org/showcase/pages" --jq .build_type); then
    if [[ $build == workflow ]]; then ok "Pages already builds from GitHub Actions"; else
      act gh api --method PUT "repos/$org/showcase/pages" -f build_type=workflow
    fi
  else
    act gh api --method POST "repos/$org/showcase/pages" -f build_type=workflow
  fi
  note "the first estate run deploys https://$org.github.io/showcase/ (dispatched when the apps publish, or: gh workflow run estate.yml -R $org/showcase)"
fi

# ---------------------------------------------------------------------------
# The check runs a reusable workflow's matrix job reports: "<caller job> /
# <called job> (<matrix value>)".
checks_for() {
  local r=$1 m
  if [[ $r == platform ]]; then
    for m in "$work"/render/platform/images/*/image.yaml; do printf 'images / build (%s)\n' "${m#"$work"/render/platform/}"; done
  else
    printf 'images / build (%s/app.yaml)\n' "$r"
  fi
}

if step protect; then
  say "Protect main: the images gate must pass; allow auto-merge"
  for r in platform "${apps[@]}"; do
    body=$(checks_for "$r" | jq -R . | jq -s -c '{required_status_checks: {strict: false, contexts: .},
      enforce_admins: false, required_pull_request_reviews: null, restrictions: null,
      allow_force_pushes: false, allow_deletions: false}')
    printf '%s\n' "$body" >"$work/protection-$r.json"
    note "$r: $(jq -c '.required_status_checks.contexts' <<<"$body")"
    act gh api --method PUT "repos/$org/$r/branches/main/protection" --input "$work/protection-$r.json"
    act gh repo edit "$org/$r" --enable-auto-merge
  done
fi

say "Next"
note "1. https://github.com/$org/platform/actions: platform.yml green (images, stacks, profile, notify)"
note "2. the apps' factory.yml runs green; ghcr.io/$org/{platform,stacks,apps,factory}/* public"
note "3. https://github.com/$org/showcase/actions: estate.yml green; https://$org.github.io/showcase/"
note "4. phases 4-6: bringup/README.md"
