#!/usr/bin/env bash
# Phase 3 of the ClearCutt showcase (docs/plan.md §9): bring it up on GitHub
# from bringup/repos/. Dry run by default: every change is printed, nothing
# changes, and GitHub is only read (GET). Re-run it as often as you like:
# each step checks what is already there and skips it.
#
#   bringup/bringup.sh [up] --owner NAME --owner-type user|org [--apply] [options]
#   bringup/bringup.sh credentials --owner NAME --owner-type user|org \
#       --app-id ID --app-key-file KEY.pem [--apply]
#
#   up           the repositories, their settings, the credentials (unless
#                --skip-credentials), then push platform, the apps (after the
#                platform's first publish), and the showcase; Pages
#   credentials  only the credentials, e.g. once the GitHub App exists
#   app-from-code  --code CODE: exchange the code GitHub returns after
#                bringup/create-app.html creates the App, keep its private key in
#                ~/.config/clearcutt-showcase/, and set the credentials
#
# Names. A personal account (--owner-type user) gets prefixed repositories,
# unmistakable among its others: PREFIXplatform, PREFIXcheckout,
# PREFIXcatalog, PREFIXstorefront, and the showcase named PREFIX without its
# dash; images under ghcr.io/OWNER/<that name>/. The default prefix is
# clearcutt-showcase-. An organization gets platform, checkout, catalog,
# storefront, and showcase, and ghcr.io/OWNER/ (no prefix).
#
# Options:
#   --owner NAME          the GitHub user or organization (lowercase)
#   --owner-type T        user or org (default org); --org NAME means
#                         --owner NAME --owner-type org
#   --prefix P            repository prefix (see Names)
#   --apply               make the changes (default: dry run)
#   --offline             don't read GitHub either: print the whole plan
#   --token app|pat       app (default): a CLEARCUTT_APP_ID variable and a
#                         CLEARCUTT_APP_PRIVATE_KEY secret; pat: a
#                         CLEARCUTT_BOT_TOKEN secret (fine-grained PAT)
#   --app-id ID           the App's Client ID (or App ID); else $CLEARCUTT_APP_ID,
#                         else asked
#   --app-key-file PEM    the App's private key; else
#                         $CLEARCUTT_APP_PRIVATE_KEY_FILE, else asked. Its content
#                         is never printed or put on a command line
#   --skip-credentials    up: create and push now, set the credentials later
#                         with the credentials subcommand
#   --git-protocol P      https (default: pushes with gh's token, which needs
#                         the workflow scope) or ssh (pushes with your SSH key)
#   --reset-secrets       set secrets again even when they exist
#   --secrets-at org|repo organizations: org secrets and variables scoped to
#                         the five repositories (default), or each repository.
#                         Personal accounts: always each repository
#   --factory-ref REF     clearcutt-factory release tag or commit SHA (default v0.3.0)
#   --verify-ref REF      clearcutt-verify release tag or commit SHA (default v0.16.0)
#   --verify-version V    clearcutt-verify release to install (default: --verify-ref if
#                         a tag, else "source", which builds that commit)
#   --portal-ref REF      clearcutt-portal release tag or commit SHA (default v0.1.0)
#   --showcase-ref REF    commit of this repository to push as the showcase's main (default HEAD)
#   --steps LIST          up: a comma-separated subset of repos, settings,
#                         credentials, platform, apps, showcase, pages, protect
#                         (default: all but protect)
#   --protect             also protect main (required checks) and allow auto-merge
#   --wait                after pushing platform, wait (up to 90 minutes) for its
#                         first publish instead of stopping
#   --work DIR            work directory (default bringup/.work/OWNER)
#
# Exit codes: 0 done (or a clean dry run), 1 error, 2 usage, 3 the owner
# doesn't exist, 4 waiting for the platform's first publish (run it again),
# 5 gh's token lacks a scope (gh auth refresh), 6 a repository name or the
# clearcutt-app topic is taken by a repository outside the showcase. A dry
# run reports 5 and 6 at the end, after printing the whole plan.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

roles=(platform checkout catalog storefront showcase)
app_roles=(checkout catalog storefront)
cmd=up owner='' owner_type=org prefix='' prefix_set=false token=app secrets_at=''
app_id=${CLEARCUTT_APP_ID:-} app_key_file=${CLEARCUTT_APP_PRIVATE_KEY_FILE:-}
factory_ref=v0.3.0 verify_ref=v0.16.0 verify_version='' portal_ref=v0.1.0
showcase_ref=HEAD steps='' protect=false wait_publish=false reset_secrets=false
skip_credentials=false work='' git_protocol=https app_code=''

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while (($#)); do
  case $1 in
    up | credentials | app-from-code) cmd=$1 ;;
    --owner) owner=${2:?}; shift ;;
    --owner-type) owner_type=${2:?}; shift ;;
    --org) owner=${2:?} owner_type=org; shift ;;
    --prefix) prefix=$2 prefix_set=true; shift ;;
    --apply) APPLY=true ;;
    --offline) OFFLINE=true ;;
    --token) token=${2:?}; shift ;;
    --app-id) app_id=${2:?}; shift ;;
    --app-key-file) app_key_file=${2:?}; shift ;;
    --skip-credentials) skip_credentials=true ;;
    --code) app_code=${2:?}; shift ;;
    --git-protocol) git_protocol=${2:?}; shift ;;
    --reset-secrets) reset_secrets=true ;;
    --secrets-at) secrets_at=${2:?}; shift ;;
    --factory-ref) factory_ref=${2:?}; shift ;;
    --verify-ref) verify_ref=${2:?}; shift ;;
    --verify-version) verify_version=${2:?}; shift ;;
    --portal-ref) portal_ref=${2:?}; shift ;;
    --showcase-ref) showcase_ref=${2:?}; shift ;;
    --steps) steps=${2:?}; shift ;;
    --protect) protect=true ;;
    --wait) wait_publish=true ;;
    --work) work=${2:?}; shift ;;
    -h | --help) usage 0 ;;
    *) printf 'unknown argument: %s\n\n' "$1" >&2; usage 2 ;;
  esac
  shift
done

[[ -n $owner ]] || { printf 'needs --owner NAME\n\n' >&2; usage 2; }
[[ $owner =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "--owner $owner: use the lowercase name (ghcr.io needs lowercase)" 2
[[ $owner_type == user || $owner_type == org ]] || die "--owner-type is user or org" 2
[[ $prefix_set == true ]] || prefix=$(default_prefix "$owner_type")
[[ -z $prefix || $prefix =~ ^[a-z0-9][a-z0-9-]*-$ ]] || die "--prefix $prefix: lowercase letters, digits, and dashes, ending in a dash" 2
[[ $token == app || $token == pat ]] || die "--token is app or pat" 2
if [[ $owner_type == user ]]; then
  [[ -z $secrets_at || $secrets_at == repo ]] || die "a personal account has no organization secrets: --secrets-at repo" 2
  secrets_at=repo
else
  secrets_at=${secrets_at:-org}
  [[ $secrets_at == org || $secrets_at == repo ]] || die "--secrets-at is org or repo" 2
fi
[[ $APPLY == true && $OFFLINE == true ]] && die "--apply needs GitHub; drop --offline" 2
if [[ $cmd == app-from-code ]]; then
  token=app
fi
if [[ $cmd == credentials || $cmd == app-from-code ]]; then
  steps=credentials
elif [[ -z $steps ]]; then
  steps=repos,settings,credentials,platform,apps,showcase,pages
  [[ $protect == true ]] && steps+=,protect
fi
[[ $skip_credentials == true && $cmd == up ]] && steps=${steps//credentials/}
step() { [[ ,$steps, == *,$1,* ]]; }

showcase_names "$owner" "$prefix"
work=${work:-$here/.work/$owner}
repos=() app_repos=()
for r in "${roles[@]}"; do repos+=("$(repo_of "$r")"); done
for r in "${app_roles[@]}"; do app_repos+=("$(repo_of "$r")"); done

tag_re='^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
sha_re='^[0-9a-f]{40}$'
for r in "$factory_ref" "$verify_ref" "$portal_ref"; do
  [[ $r =~ $tag_re || $r =~ $sha_re ]] || die "$r: pin a release tag (vX.Y.Z) or a full commit SHA" 2
done
# The image signers' identity ends in the ref factory's workflows are called
# by: a release tag, or the commit SHA they are pinned to (plan §4).
if [[ $factory_ref =~ $tag_re ]]; then
  factory_signer_ref='refs/tags/v\d+\.\d+\.\d+'
else
  factory_signer_ref='[0-9a-f]{40}'
fi
if [[ -z $verify_version ]]; then
  # A release tag: leave the action's version input empty, so it installs
  # the release it is pinned to and a Dependabot bump of the pin moves both.
  if [[ $verify_ref =~ $tag_re ]]; then verify_version=; else verify_version=source; fi
fi

# Exit codes 5 and 6 end an apply at once; a dry run reports them at the end.
final=0
fail_later() { # CODE MESSAGE
  if [[ $APPLY == true ]]; then die "$2" "$1"; fi
  warn "$2"
  ((final != 0)) || final=$1
}

mode="dry run (reads GitHub, changes nothing; --apply to change)"
[[ $APPLY == true ]] && mode=apply
[[ $OFFLINE == true ]] && mode="offline dry run (no GitHub reads either)"
printf '%sClearCutt showcase bring-up%s: %s for %s %s, %s\n' "$_b" "$_n" "$cmd" "$owner_type" "$owner" "$mode"
note "repositories: $(printf "$owner/%s " "${repos[@]}")"
note "images: $REGISTRY/…; Pages: $PAGES_URL"
note "factory $factory_ref, verify $verify_ref (installs ${verify_version:-that release}), portal $portal_ref"
note "credentials: $token, per $secrets_at$([[ $skip_credentials == true ]] && echo ' (skipped: run the credentials subcommand later)')"
note "work directory: $work"

# ---------------------------------------------------------------------------
say "Preflight"
need git perl jq curl
if [[ $OFFLINE != true ]]; then
  need gh
  gh auth status >/dev/null 2>&1 || die "gh isn't logged in: gh auth login -h github.com"
  # What each step needs: repo (repositories, settings, secrets, pushes),
  # workflow (pushing .github/workflows), admin:org (organization settings
  # and secrets). Nothing here pushes packages, so no write:packages.
  needed=(repo)
  # Pushing over SSH authenticates with your SSH key, which OAuth scopes
  # don't limit; over HTTPS gh's token needs workflow for .github/workflows.
  if [[ $git_protocol == https ]] && { step platform || step apps || step showcase; }; then needed+=(workflow); fi
  if [[ $owner_type == org ]] && { step settings || { step credentials && [[ $secrets_at == org ]]; }; }; then needed+=(admin:org); fi
  scopes=$(gh api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes: //p')
  if [[ -z $scopes ]]; then
    warn "can't read gh's token scopes (a fine-grained token?); it needs: ${needed[*]}"
  else
    missing=()
    for s in "${needed[@]}"; do [[ ", $scopes," == *", $s,"* ]] || missing+=("$s"); done
    if ((${#missing[@]})); then
      fail_later 5 "gh's token lacks: ${missing[*]} (has: $scopes). Run: gh auth refresh -h github.com -s $(IFS=,; echo "${missing[*]}")"
    else
      ok "gh token scopes cover: ${needed[*]}"
    fi
  fi
  # Releases the selected steps pin.
  tools=()
  if step platform || step apps || step showcase; then tools+=("clearcutt-factory $factory_ref"); fi
  if step showcase; then tools+=("clearcutt-verify $verify_ref" "clearcutt-portal $portal_ref"); fi
  for pair in ${tools[@]+"${tools[@]}"}; do
    read -r tool ref <<<"$pair"
    [[ $ref =~ $tag_re ]] || continue
    if look gh api "repos/northcutted/$tool/releases/tags/$ref" --jq .tag_name >/dev/null; then
      ok "$tool $ref is released"
    elif [[ $APPLY == true ]]; then
      die "$tool $ref isn't released yet (wait for it, pin a commit SHA, or leave out the steps that use it with --steps)"
    else
      warn "$tool $ref isn't released yet: an apply that pushes $([[ $tool == clearcutt-factory ]] && echo 'platform, the apps, or the showcase' || echo 'the showcase') waits for it"
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
    warn "clearcutt-factory $factory_ref and cosign are needed with --apply (the platform and apps steps lock locally)"
  fi
fi
if step showcase && [[ -n $(git -C "$root" status --porcelain) ]]; then
  warn "this repository has uncommitted changes; the showcase step pushes $showcase_ref only"
fi
if [[ -n $app_key_file ]]; then
  [[ -r $app_key_file ]] || die "--app-key-file $app_key_file: can't read it"
  grep -q 'PRIVATE KEY-----' "$app_key_file" || die "--app-key-file $app_key_file doesn't look like a PEM private key"
  ok "App private key file is readable (not printed)"
fi

# ---------------------------------------------------------------------------
say "Owner $owner ($owner_type)"
if [[ $OFFLINE == true ]]; then
  note "(offline) would check that https://github.com/$owner exists and is a$([[ $owner_type == org ]] && echo 'n organization' || echo ' user')"
elif [[ $owner_type == org ]]; then
  if look gh api "orgs/$owner" --jq .login >/dev/null; then
    ok "https://github.com/$owner is an organization"
  else
    printf '\n   %s does not exist. Organizations can only be created on the web:\n' "$owner"
    printf '     https://github.com/account/organizations/new?plan=free\n'
    printf '   Name it %s (Free plan), then run this again.\n' "$owner"
    exit 3
  fi
else
  type=$(look gh api "users/$owner" --jq .type || true)
  case $type in
    User) ok "https://github.com/$owner is a personal account" ;;
    Organization) die "$owner is an organization: --owner-type org" 2 ;;
    *) printf '   no GitHub account %s\n' "$owner"; exit 3 ;;
  esac
  login=$(look gh api user --jq .login || true)
  [[ $login == "$owner" ]] || die "gh is logged in as '$login': personal repositories can only be created by $owner itself (gh auth switch, or gh auth login)"
fi

# ---------------------------------------------------------------------------
# What each repository is, also the marker that a repository of that name is
# the showcase's (with the clearcutt-showcase topic the settings step adds).
describe() {
  case $1 in
    platform) echo "ClearCutt showcase, platform team: run and build images, stacks, and the shared org profile" ;;
    checkout) echo "ClearCutt showcase, payments team: checkout service (Go, stack go:1)" ;;
    catalog) echo "ClearCutt showcase, catalog team: catalog service (Python 3.14 with a C extension, stack python:1)" ;;
    storefront) echo "ClearCutt showcase, web team: storefront (Node.js 24 TypeScript, stack node:1)" ;;
    showcase) echo "ClearCutt showcase: plan, demo, and the verified estate (clearcutt-verify + clearcutt-portal)" ;;
  esac
}

# state ROLE: free (no such repository), ours, foreign, or unknown (offline).
declare_state() {
  local role=$1 repo info desc topics
  repo=$(repo_of "$role")
  [[ $OFFLINE == true ]] && { echo unknown; return; }
  if ! info=$(look gh repo view "$owner/$repo" --json description,repositoryTopics \
    --jq '[.description // "", ([.repositoryTopics[]?.name] | join(","))] | @tsv'); then
    echo free
    return
  fi
  IFS=$'\t' read -r desc topics <<<"$info"
  if [[ $desc == "$(describe "$role")" || ,$topics, == *,clearcutt-showcase,* ]]; then echo ours; else echo foreign; fi
}

say "Names: repositories and the clearcutt-app topic"
declare -a state=()
for i in "${!roles[@]}"; do
  state[i]=$(declare_state "${roles[i]}")
  case ${state[i]} in
    free) ok "$owner/${repos[i]} is free" ;;
    ours) ok "$owner/${repos[i]} exists and is the showcase's" ;;
    unknown) note "(offline) would check that $owner/${repos[i]} is free or already the showcase's" ;;
    foreign) fail_later 6 "$owner/${repos[i]} exists and isn't the showcase's (no clearcutt-showcase topic, another description): choose another --prefix" ;;
  esac
done
# notify.yml wakes every repository of the owner with the topic clearcutt-app:
# only the three app repositories may carry it.
if [[ $OFFLINE == true ]]; then
  note "(offline) would check that only $(printf '%s ' "${app_repos[@]}")carry the topic clearcutt-app under $owner"
elif tagged=$(look gh search repos --owner "$owner" --topic clearcutt-app --limit 1000 --json fullName --jq '.[].fullName'); then
  others=()
  while IFS= read -r t; do
    [[ -z $t ]] && continue
    mine=false
    for a in "${app_repos[@]}"; do [[ $(lc "$t") == "$owner/$a" ]] && mine=true; done
    [[ $mine == true ]] || others+=("$t")
  done <<<"$tagged"
  if ((${#others[@]})); then
    fail_later 6 "other repositories carry the topic clearcutt-app, so the platform's notify job would dispatch to them: ${others[*]} (remove it there)"
  else
    ok "no repository of $owner outside the showcase carries the topic clearcutt-app"
  fi
else
  warn "couldn't search $owner's repositories by topic"
fi

# ---------------------------------------------------------------------------
# Render bringup/repos/* into the work directory with the placeholders filled.
# Every later step reads it; it only writes the work directory.
render() {
  local role=$1 dst=$work/render/$1 f
  rm -rf "$dst"
  mkdir -p "$dst"
  cp -R "$here/repos/$role/." "$dst/"
  while IFS= read -r -d '' f; do
    OWNER=$OWNER PREFIX=$PREFIX SHOWCASE=$SHOWCASE NAME=$NAME REGISTRY=$REGISTRY PAGES_URL=$PAGES_URL \
      FACTORY_REF=$factory_ref FACTORY_SIGNER_REF=$factory_signer_ref \
      VERIFY_REF=$verify_ref VERIFY_VERSION=$verify_version PORTAL_REF=$portal_ref \
      perl -pi -e 's/<(OWNER|PREFIX|SHOWCASE|NAME|REGISTRY|PAGES_URL|FACTORY_REF|FACTORY_SIGNER_REF|VERIFY_REF|VERIFY_VERSION|PORTAL_REF)>/$ENV{$1}/g' "$f"
  done < <(grep -rlE --null "$placeholders" "$dst" || true)
  if grep -rnE "$placeholders" "$dst"; then die "placeholders left in $dst"; fi
}
placeholders='<(OWNER|PREFIX|SHOWCASE|NAME|REGISTRY|PAGES_URL|FACTORY_REF|FACTORY_SIGNER_REF|VERIFY_REF|VERIFY_VERSION|PORTAL_REF)>'

if [[ $cmd == up ]]; then
  say "Render bringup/repos into $work/render"
  for r in "${roles[@]}"; do render "$r"; done
  ok "rendered: $(cd "$work/render" && find . -type f | wc -l | tr -d ' ') files for $(printf '%s ' "${repos[@]}")"
fi

# ---------------------------------------------------------------------------
if step repos; then
  say "Repositories"
  for i in "${!roles[@]}"; do
    if [[ ${state[i]} == ours ]]; then
      ok "$owner/${repos[i]} exists"
    else
      act gh repo create "$owner/${repos[i]}" --public --disable-wiki --description "$(describe "${roles[i]}")"
    fi
  done
fi

# ---------------------------------------------------------------------------
if step settings; then
  # The bot's pull requests come from the App (or CLEARCUTT_BOT_TOKEN), so
  # the workflow token needs no right to create or approve them; with it off,
  # a missing credential fails loudly instead of falling back.
  say "Settings: read-only workflow token; Dependabot alerts and security updates; topics; branch cleanup"
  if [[ $owner_type == org ]]; then
    act gh api --method PUT "orgs/$owner/actions/permissions/workflow" \
      -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
  fi
  for i in "${!roles[@]}"; do
    r=${repos[i]}
    act gh api --method PUT "repos/$owner/$r/actions/permissions/workflow" \
      -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
    # A CVE in an app's own dependencies is Dependabot's (factory locks the
    # OS and toolchains): alerts, and a fix PR without waiting for the schedule.
    act gh api --method PUT "repos/$owner/$r/vulnerability-alerts"
    act gh api --method PUT "repos/$owner/$r/automated-security-fixes"
    topics=(--add-topic clearcutt-showcase)
    case ${roles[i]} in
      checkout | catalog | storefront) topics+=(--add-topic clearcutt-app) ;;
      showcase) topics+=(--homepage "$PAGES_URL") ;;
    esac
    act gh repo edit "$owner/$r" --delete-branch-on-merge "${topics[@]}"
  done
fi

# ---------------------------------------------------------------------------
# set_value KIND NAME VALUE: an Actions secret or variable, at the
# organization (scoped to the five repositories) or in each repository. A
# variable already holding VALUE is left; a secret already set is left
# unless --reset-secrets.
set_value() {
  local kind=$1 name=$2 value=$3 r have
  if [[ $secrets_at == org ]]; then
    if [[ $reset_secrets != true ]] && look gh "$kind" list --org "$owner" --json name --jq '.[].name' | grep -qx "$name"; then
      ok "$kind $name is set for $owner"
      return
    fi
    act_secret "$value" gh "$kind" set "$name" --org "$owner" --visibility selected --repos "$(IFS=,; echo "${repos[*]}")"
    return
  fi
  for r in "${repos[@]}"; do
    if [[ $kind == variable ]]; then
      have=$(look gh variable get "$name" --repo "$owner/$r" || true)
      if [[ -n $have && ($have == "$value" || -z $value) ]]; then ok "variable $name is set in $r"; continue; fi
    elif [[ $reset_secrets != true ]] && look gh secret list --repo "$owner/$r" --json name --jq '.[].name' | grep -qx "$name"; then
      ok "secret $name is set in $r"
      continue
    fi
    act_secret "$value" gh "$kind" set "$name" --repo "$owner/$r"
  done
}

# missing_somewhere KIND NAME: whether the organization, or any repository,
# lacks the secret or variable (always, with --reset-secrets for secrets).
missing_somewhere() {
  local kind=$1 name=$2 r
  [[ $kind == secret && $reset_secrets == true ]] && return 0
  if [[ $secrets_at == org ]]; then
    if look gh "$kind" list --org "$owner" --json name --jq '.[].name' | grep -qx "$name"; then return 1; fi
    return 0
  fi
  for r in "${repos[@]}"; do
    look gh "$kind" list --repo "$owner/$r" --json name --jq '.[].name' | grep -qx "$name" || return 0
  done
  return 1
}

install_url=''
if [[ $cmd == app-from-code ]]; then
  say "The GitHub App, from create-app.html's code"
  [[ -n $app_code ]] || die "app-from-code needs --code: the code GitHub put in the address bar after create-app.html" 2
  if [[ $APPLY == true ]]; then
    # The code is single-use and expires after an hour. The response holds
    # the App's private key: it goes to a 0600 file and is never printed.
    conv=$(gh api --method POST "app-manifests/$app_code/conversions") ||
      die "GitHub didn't accept the code (it works once, within an hour of creating the App)"
    slug=$(jq -r .slug <<<"$conv")
    app_id=$(jq -r .client_id <<<"$conv")
    keydir=${XDG_CONFIG_HOME:-$HOME/.config}/clearcutt-showcase
    mkdir -p "$keydir" && chmod 700 "$keydir"
    app_key_file=$keydir/$slug.private-key.pem
    (umask 077 && jq -r .pem <<<"$conv" > "$app_key_file")
    unset conv
    ok "created the App $slug (Client ID $app_id); private key in $app_key_file"
    install_url="https://github.com/apps/$slug/installations/new"
  else
    note "would exchange the code (POST /app-manifests/CODE/conversions), keep the private key in ~/.config/clearcutt-showcase/, and set the credentials below"
  fi
fi
if step credentials; then
  say "Credentials for the workflows: $token, per $secrets_at"
  if [[ $APPLY == true ]]; then
    for i in "${!roles[@]}"; do
      [[ $(declare_state "${roles[i]}") == ours ]] || die "$owner/${repos[i]} doesn't exist yet: run up first (with --skip-credentials if the App doesn't exist yet)"
    done
  fi
  if [[ $token == app ]]; then
    # Ask only for what some repository still lacks.
    if [[ -z $app_id && $APPLY == true ]] && missing_somewhere variable CLEARCUTT_APP_ID; then
      app_id=$(ask "GitHub App Client ID (or App ID)")
    fi
    if [[ -z $app_key_file && $APPLY == true ]] && missing_somewhere secret CLEARCUTT_APP_PRIVATE_KEY; then
      app_key_file=$(ask "path to the App's private key (.pem)")
    fi
    key=''
    if [[ -n $app_key_file && $APPLY == true ]]; then
      [[ -r $app_key_file ]] || die "can't read $app_key_file"
      key=$(<"$app_key_file")
      [[ $key == *"PRIVATE KEY-----"* ]] || die "$app_key_file doesn't look like a PEM private key"
    fi
    [[ -n $app_id || $APPLY == true ]] || note "(no --app-id given: the dry run can't tell whether the variable already holds it)"
    set_value variable CLEARCUTT_APP_ID "$app_id"
    set_value secret CLEARCUTT_APP_PRIVATE_KEY "$key"
    note "the App must be installed on all five repositories (README, \"The GitHub App\")"
  else
    bot=${CLEARCUTT_BOT_TOKEN:-}
    [[ -z $bot && $APPLY == true ]] && missing_somewhere secret CLEARCUTT_BOT_TOKEN && bot=$(ask_secret "CLEARCUTT_BOT_TOKEN (fine-grained PAT: contents and pull requests read/write on the five repositories)")
    set_value secret CLEARCUTT_BOT_TOKEN "$bot"
  fi
fi

# ---------------------------------------------------------------------------
# remote_empty REPO: whether the repository has no commits yet. Unknown
# (offline, or not created yet in a dry run) counts as empty.
remote_empty() {
  local out
  if out=$(look gh api "repos/$owner/$1/commits?per_page=1" --jq 'length'); then
    [[ $out == 0 ]]
  else
    return 0
  fi
}

# push_new REPO DIR MESSAGE: commit DIR as the first commit of REPO's main and push it.
push_new() {
  local r=$1 dir=$2 msg=$3
  act git -C "$dir" init -q -b main
  act git -C "$dir" add -A
  act git -C "$dir" commit -q -m "$msg"
  act git -C "$dir" remote add origin "$(remote_url "$owner" "$r")"
  git_push "$dir" main
}

# fresh ROLE: a copy of the rendered repository to lock and push.
fresh() {
  local dir=$work/push/$1
  rm -rf "$dir"
  mkdir -p "$work/push"
  cp -R "$work/render/$1" "$dir"
  printf '%s' "$dir"
}

if step platform; then
  r=$(repo_of platform)
  say "Push $r"
  if ! remote_empty "$r"; then
    ok "$owner/$r already has commits; not pushing (change it with pull requests)"
  else
    dir=$(fresh platform)
    note "lock every platform image (pins wolfi-base, packages, BuildKit; writes each lock and Containerfile)"
    for m in "$dir"/images/*/image.yaml; do act_in "$dir" clearcutt-factory lock -f "${m#"$dir"/}"; done
    push_new "$r" "$dir" "Bring up the platform: images, stacks, and the shared org profile"
    note "platform.yml now publishes the images, then the stacks and the shared profile:"
    note "  https://github.com/$owner/$r/actions"
  fi
fi

# ---------------------------------------------------------------------------
# What the apps need before they can be locked: the shared profile and the
# stacks, published and signed by the platform's workflows. Checked through
# the Packages API when the token can read packages, else anonymously in the
# registry (which sees public packages only).
needed_packages=(factory/org:1 stacks/go:1 stacks/python:1 stacks/node:1)
# shellcheck disable=SC2329 # called through look
registry_has() { # PATH TAG: an anonymous pull of PATH:TAG would find it
  local tok
  tok=$(curl -fsS "https://ghcr.io/token?scope=repository:$1:pull" | jq -r .token) || return 1
  curl -fsS -o /dev/null -I -H "Authorization: Bearer $tok" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/$1/manifests/$2"
}
missing_packages() {
  local p path name api vis
  for p in "${needed_packages[@]}"; do
    path=${REGISTRY#ghcr.io/}/${p%:*}
    name=${path#"$owner"/}
    if [[ $owner_type == org ]]; then api=orgs/$owner; else api=users/$owner; fi
    if vis=$(look gh api "$api/packages/container/${name//\//%2F}" --jq .visibility); then
      [[ $vis == public ]] || warn "ghcr.io/$path is $vis: make it public (Package settings → Danger Zone → Change visibility): https://github.com/$([[ $owner_type == org ]] && echo "orgs/$owner" || echo "users/$owner")/packages/container/${name//\//%2F}/settings"
    elif ! look registry_has "$path" "${p##*:}"; then
      printf '%s\n' "ghcr.io/$path:${p##*:}"
    fi
  done
}

if step apps; then
  say "Push the apps (after the platform's first publish)"
  if [[ $OFFLINE == true ]]; then
    note "(offline) would check that $REGISTRY/{${needed_packages[*]}} are published"
  else
    waited=0
    while left=$(missing_packages) && [[ -n $left ]]; do
      if [[ $APPLY != true ]]; then
        note "not published yet (or private): $(paste -sd' ' - <<<"$left"); an apply waits for them (--wait) or stops (exit 4)"
        break
      fi
      if [[ $wait_publish != true ]] || ((waited >= 90)); then
        note "not published yet (or private): $(paste -sd' ' - <<<"$left")"
        note "watch https://github.com/$owner/$(repo_of platform)/actions, then run this again (or pass --wait)"
        exit 4
      fi
      note "waiting for $(paste -sd' ' - <<<"$left") (${waited}m)"
      sleep 60
      waited=$((waited + 1))
    done
  fi
  for a in "${app_roles[@]}"; do
    r=$(repo_of "$a")
    if ! remote_empty "$r"; then
      ok "$owner/$r already has commits; not pushing"
      continue
    fi
    dir=$(fresh "$a")
    note "$r: lock (verifies the shared profile and the stack against their signers, pins both)"
    act_in "$dir" clearcutt-factory lock -f "$a/app.yaml"
    push_new "$r" "$dir" "Bring up $a on the platform's stack"
  done
fi

# ---------------------------------------------------------------------------
if step showcase; then
  say "Push $SHOWCASE (this repository at $showcase_ref, plus bringup/repos/showcase)"
  if ! remote_empty "$SHOWCASE"; then
    ok "$owner/$SHOWCASE already has commits; not pushing"
  else
    sha=$(git -C "$root" rev-parse --verify "$showcase_ref^{commit}")
    dir=$work/push/showcase
    rm -rf "$dir"
    mkdir -p "$work/push"
    # A local clone and an overlay commit, only in the work directory, so a
    # dry run prepares it too.
    git clone -q --no-checkout "$root" "$dir"
    git -C "$dir" checkout -q -B main "$sha"
    git -C "$dir" remote set-url origin "$(remote_url "$owner" "$SHOWCASE")"
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
  say "Pages for $SHOWCASE: source GitHub Actions"
  if build=$(look gh api "repos/$owner/$SHOWCASE/pages" --jq .build_type); then
    if [[ $build == workflow ]]; then ok "Pages already builds from GitHub Actions"; else
      act gh api --method PUT "repos/$owner/$SHOWCASE/pages" -f build_type=workflow
    fi
  else
    act gh api --method POST "repos/$owner/$SHOWCASE/pages" -f build_type=workflow
  fi
  note "the first estate run deploys $PAGES_URL (dispatched when the apps publish, or: gh workflow run estate.yml -R $owner/$SHOWCASE)"
fi

# ---------------------------------------------------------------------------
# The check runs a reusable workflow's matrix job reports: "<caller job> /
# <called job> (<matrix value>)".
checks_for() {
  local role=$1 m
  if [[ $role == platform ]]; then
    for m in "$work"/render/platform/images/*/image.yaml; do printf 'images / build (%s)\n' "${m#"$work"/render/platform/}"; done
  else
    printf 'images / build (%s/app.yaml)\n' "$role"
  fi
}

if step protect; then
  say "Protect main: the images gate must pass; allow auto-merge"
  for role in platform "${app_roles[@]}"; do
    r=$(repo_of "$role")
    body=$(checks_for "$role" | jq -R . | jq -s -c '{required_status_checks: {strict: false, contexts: .},
      enforce_admins: false, required_pull_request_reviews: null, restrictions: null,
      allow_force_pushes: false, allow_deletions: false}')
    printf '%s\n' "$body" >"$work/protection-$r.json"
    note "$r: $(jq -c '.required_status_checks.contexts' <<<"$body")"
    act gh api --method PUT "repos/$owner/$r/branches/main/protection" --input "$work/protection-$r.json"
    act gh repo edit "$owner/$r" --enable-auto-merge
  done
fi

say "Next"
if [[ -n $install_url ]]; then
  note "now install the App on the five repositories (Only select repositories): $install_url"
fi
if [[ $cmd == credentials || $cmd == app-from-code ]]; then
  note "the workflows pick the credentials up on their next run"
else
  note "1. https://github.com/$owner/$(repo_of platform)/actions: platform green (images, stacks, profile, notify)"
  note "2. the apps' factory runs green; $REGISTRY/{platform,stacks,apps,factory}/* public"
  note "3. https://github.com/$owner/$SHOWCASE/actions: estate green; $PAGES_URL"
  note "4. phases 4-6: bringup/README.md"
fi
if ((final)); then
  printf '\n%sdry run done, but an apply would stop: exit %d (see the warnings above)%s\n' "$_y" "$final" "$_n"
fi
exit "$final"
