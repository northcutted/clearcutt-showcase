# shellcheck shell=bash
# Helpers shared by bringup.sh and drill-github.sh. Source it; don't run it.
#
# Every command that changes something (on GitHub, in the registry, or in a
# work directory's git repository) goes through `act`: printed, and run only
# with --apply. Commands that only read go through `look`, which runs them
# unless --offline. Nothing here prints a secret: values are read with
# `read -s` and handed to commands on standard input.

APPLY=${APPLY:-false}
OFFLINE=${OFFLINE:-false}

if [[ -t 1 ]]; then
  _b=$'\e[1m' _d=$'\e[2m' _y=$'\e[33m' _r=$'\e[31m' _g=$'\e[32m' _n=$'\e[0m'
else
  _b='' _d='' _y='' _r='' _g='' _n=''
fi

say() { printf '\n%s== %s%s\n' "$_b" "$*" "$_n"; }
note() { printf '   %s\n' "$*"; }
ok() { printf '   %sok%s %s\n' "$_g" "$_n" "$*"; }
warn() { printf '   %swarning:%s %s\n' "$_y" "$_n" "$*" >&2; }
die() { printf '%serror:%s %s\n' "$_r" "$_n" "$1" >&2; exit "${2:-1}"; }

# quoted CMD...: the command as one line you could paste into a shell.
quoted() {
  local out='' a sq="'"
  for a in "$@"; do
    if [[ -n $a && $a =~ ^[A-Za-z0-9_./:=@%+,-]+$ ]]; then out+=" $a"; else out+=" '${a//$sq/$sq\\$sq$sq}'"; fi
  done
  printf '%s' "${out# }"
}

# act CMD...: a change. Printed; run only with --apply.
act() {
  if [[ $APPLY == true ]]; then
    printf '   %s+ %s%s\n' "$_d" "$(quoted "$@")" "$_n"
    "$@"
  else
    printf '   would run: %s\n' "$(quoted "$@")"
  fi
}

# act_in DIR CMD...: act, in DIR.
act_in() {
  local dir=$1; shift
  if [[ $APPLY == true ]]; then
    printf '   %s+ (cd %s) %s%s\n' "$_d" "$(printf '%q' "$dir")" "$(quoted "$@")" "$_n"
    (cd "$dir" && "$@")
  else
    printf '   would run in %s: %s\n' "$dir" "$(quoted "$@")"
  fi
}

# act_secret VALUE CMD...: act, with VALUE on the command's standard input.
# The value is never printed or put on a command line.
act_secret() {
  local value=$1; shift
  if [[ $APPLY == true ]]; then
    printf '   %s+ %s < (hidden)%s\n' "$_d" "$(quoted "$@")" "$_n"
    printf '%s' "$value" | "$@"
  else
    printf '   would run: %s < (hidden)\n' "$(quoted "$@")"
  fi
}

# look CMD...: a read. Runs unless --offline (then fails, so callers treat
# the answer as unknown). Output goes to stdout; errors are discarded.
look() {
  [[ $OFFLINE == true ]] && return 1
  "$@" 2>/dev/null
}

# lc TEXT: TEXT in lowercase (bash 3.2 has no ${v,,}).
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# need TOOL...: fail unless every tool is on PATH.
need() {
  local t missing=()
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
  ((${#missing[@]} == 0)) || die "missing tools: ${missing[*]}"
}

# ask_secret PROMPT: read a value from the terminal without echoing it.
ask_secret() {
  local v
  [[ -r /dev/tty ]] || die "no terminal to ask for $1; set it in the environment instead"
  read -r -s -p "   $1: " v </dev/tty
  printf '\n' >/dev/tty
  printf '%s' "$v"
}

# ask PROMPT: read a (non-secret) value from the terminal.
ask() {
  local v
  [[ -r /dev/tty ]] || die "no terminal to ask for $1; set it in the environment instead"
  read -r -p "   $1: " v </dev/tty
  printf '%s' "$v"
}

# git_push DIR BRANCH: push DIR's BRANCH to its origin, authenticating with gh
# (no change to the global git configuration).
git_push() {
  if [[ ${git_protocol:-https} == ssh ]]; then
    act git -C "$1" push -u origin "$2"
  else
    act git -C "$1" -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -u origin "$2"
  fi
}

# remote_url OWNER REPO: the repository's URL for --git-protocol.
remote_url() {
  case ${git_protocol:-https} in
    ssh) printf 'git@github.com:%s/%s.git' "$1" "$2" ;;
    https) printf 'https://github.com/%s/%s.git' "$1" "$2" ;;
    *) die "--git-protocol is https or ssh, not $git_protocol" ;;
  esac
}

# showcase_names OWNER PREFIX: the names everything else derives from.
#   PREFIX empty (an organization's own repositories): platform, checkout,
#     catalog, storefront, showcase; images under ghcr.io/OWNER.
#   PREFIX set (e.g. clearcutt-showcase- in a personal account): PREFIXplatform,
#     PREFIXcheckout, PREFIXcatalog, PREFIXstorefront, and the showcase named
#     PREFIX without its dash; images under ghcr.io/OWNER/<that name>.
# Sets OWNER, PREFIX, SHOWCASE, NAME (the estate's name), REGISTRY, PAGES_URL
# for the scripts that source this file.
# shellcheck disable=SC2034
showcase_names() {
  OWNER=$1 PREFIX=$2
  if [[ -n $PREFIX ]]; then
    SHOWCASE=${PREFIX%-} NAME=${PREFIX%-}
    REGISTRY=ghcr.io/$OWNER/$SHOWCASE
  else
    SHOWCASE=showcase NAME=$OWNER
    REGISTRY=ghcr.io/$OWNER
  fi
  PAGES_URL=https://$OWNER.github.io/$SHOWCASE/
}

# repo_of ROLE: the repository name of platform, checkout, …, or showcase.
repo_of() { if [[ $1 == showcase ]]; then printf '%s' "$SHOWCASE"; else printf '%s' "$PREFIX$1"; fi; }

# default_prefix OWNER_TYPE: clearcutt-showcase- for a personal account, else none.
default_prefix() { if [[ $1 == user ]]; then printf 'clearcutt-showcase-'; fi; }
