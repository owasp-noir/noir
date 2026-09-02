#!/usr/bin/env bash
# Add a released version to the OWASP project page's version list.
#
# The page at https://owasp.org/www-project-noir/ renders its download tab from
# _data/release.yml in OWASP/www-project-noir, a plain list of the most recent
# tags. This commits the new tag to the owasp-noir fork and prints the compare
# URL for the upstream pull request, which stays a manual click: creating that
# pull request from CI would need a token with write access to a repository the
# OWASP Foundation enterprise owns, and its policy does not hand one out.
#
# Usage: scripts/update_www_release.sh <tag> [--keep N] [--dry-run]
#
#   <tag>       Release tag, with or without the leading "v" (e.g. v1.3.1).
#   --keep N    How many versions the list keeps; older ones are dropped from
#               the bottom (default: 5, matching the list as it stands today).
#   --dry-run   Print the resulting diff and stop before committing.
#
# Re-running for a tag that is already listed is a no-op, so a re-published
# release or a retried workflow will not commit twice.
#
# Requires: gh (authenticated with push access to the fork), git.
set -euo pipefail

UPSTREAM_REPO="OWASP/www-project-noir"
FORK_REPO="owasp-noir/www-project-noir"
FORK_OWNER="${FORK_REPO%%/*}"
BASE_BRANCH="main"
DATA_FILE="_data/release.yml"
COAUTHOR="KSG <6715194+ksg97031@users.noreply.github.com>"
DEFAULT_COMMIT_NAME="hahwul"
DEFAULT_COMMIT_EMAIL="hahwul@gmail.com"

KEEP=5
DRY_RUN=0
TAG=""

die() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)
      KEEP="${2:?--keep needs a number}"
      shift 2
      ;;
    --keep=*)
      KEEP="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      [[ -n "$TAG" ]] && die "unexpected argument: $1"
      TAG="$1"
      shift
      ;;
  esac
done

[[ -n "$TAG" ]] || die "usage: $0 <tag> [--keep N] [--dry-run]"
[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || die "--keep must be a positive integer, got: $KEEP"

# Accept both "1.3.1" and "v1.3.1"; the list is written with the v prefix.
[[ "$TAG" == v* ]] || TAG="v$TAG"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] ||
  die "tag does not look like a release tag: $TAG"

for tool in gh git; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required"
done
gh auth status >/dev/null 2>&1 || die "gh is not authenticated (set GH_TOKEN or run: gh auth login)"

# Fail early and specifically on the most likely misconfiguration: a token that
# can reach GitHub but was scoped to some other repository.
can_push="$(gh api "repos/$FORK_REPO" --jq '.permissions.push' 2>/dev/null || echo "")"
if [[ "$can_push" != "true" ]]; then
  die "the current GitHub token cannot push to $FORK_REPO.
  A fine-grained token must list that repository (Contents: read and write);
  a classic token needs the 'repo' scope. Nothing here touches $UPSTREAM_REPO,
  so no access to the OWASP Foundation's repositories is needed."
fi

# Pick up whatever upstream has merged since the last release. This runs on the
# fork through the merge-upstream API, so it needs no access to $UPSTREAM_REPO.
# It fails when the two have diverged - typically an earlier pull request that
# upstream has not merged yet - and the edit below is still correct in that
# case, since it appends to the list the fork already carries.
echo "==> Syncing $FORK_REPO from $UPSTREAM_REPO"
if ! sync_output="$(gh repo sync "$FORK_REPO" --source "$UPSTREAM_REPO" --branch "$BASE_BRANCH" 2>&1)"; then
  echo "warning: could not sync the fork, continuing on its current $BASE_BRANCH:" >&2
  echo "  $sync_output" >&2
else
  echo "$sync_output"
fi

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "==> Cloning $FORK_REPO"
# Plain git rather than `gh repo clone`: gh resolves the fork's parent over
# GraphQL to attach an upstream remote, and the OWASP Foundation enterprise
# rejects that lookup for tokens its policy does not accept. The fork is
# public, so an unauthenticated shallow clone is all this step needs.
git clone --quiet --depth 1 --branch "$BASE_BRANCH" \
  "https://github.com/${FORK_REPO}.git" "$WORKDIR/repo"
cd "$WORKDIR/repo"

[[ -f "$DATA_FILE" ]] || die "$DATA_FILE not found in $FORK_REPO"

# Parse the version list. The file is tiny and hand-maintained, so instead of
# tolerating any YAML shape we assert the one it actually has and bail out if
# the layout ever changes - a mangled release.yml would break the project page.
indent="    "
versions=()
seen_header=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" == \#* ]] && continue
  if [[ "$seen_header" -eq 0 ]]; then
    [[ "$line" == "versions:" ]] || die "unexpected first line in $DATA_FILE: $line"
    seen_header=1
    continue
  fi
  [[ "$line" =~ ^([[:space:]]+)-[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]] ||
    die "unexpected line in $DATA_FILE: $line"
  indent="${BASH_REMATCH[1]}"
  versions+=("${BASH_REMATCH[2]}")
done <"$DATA_FILE"

[[ "$seen_header" -eq 1 ]] || die "no 'versions:' key in $DATA_FILE"

for existing in "${versions[@]}"; do
  if [[ "$existing" == "$TAG" ]]; then
    echo "==> $TAG is already listed in $DATA_FILE; nothing to do."
    exit 0
  fi
done

kept=("$TAG")
for existing in "${versions[@]}"; do
  [[ "${#kept[@]}" -ge "$KEEP" ]] && break
  kept+=("$existing")
done

dropped=$((${#versions[@]} + 1 - ${#kept[@]}))
echo "==> Adding $TAG (keeping ${#kept[@]} of $((${#versions[@]} + 1)), dropping $dropped oldest)"

{
  echo "versions:"
  for version in "${kept[@]}"; do
    echo "${indent}- $version"
  done
} >"$DATA_FILE"

git --no-pager diff -- "$DATA_FILE"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "==> Dry run: stopping before commit and push."
  exit 0
fi

git config user.email >/dev/null 2>&1 || git config user.email "$DEFAULT_COMMIT_EMAIL"
git config user.name >/dev/null 2>&1 || git config user.name "$DEFAULT_COMMIT_NAME"

git add "$DATA_FILE"
git commit -q -m "Add $TAG to release.yml" -m "Co-authored-by: $COAUTHOR"

# Authenticate the push through the throwaway clone's remote so no credential
# helper is installed on the machine running this and no token reaches argv.
token="$(gh auth token)"
git remote set-url --push origin "https://x-access-token:${token}@github.com/${FORK_REPO}.git"

echo "==> Pushing to $FORK_REPO $BASE_BRANCH"
git push -q origin "$BASE_BRANCH"

compare_url="https://github.com/$UPSTREAM_REPO/compare/$BASE_BRANCH...$FORK_OWNER:$BASE_BRANCH?expand=1"

echo ""
echo "==> Done. Open the pull request against $UPSTREAM_REPO here:"
echo "  $compare_url"

# Under Actions the link is the whole point of the run, so put it on the run
# page instead of leaving it buried in the step log.
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### $TAG added to the project page fork"
    echo ""
    echo "[Open the pull request against $UPSTREAM_REPO]($compare_url)"
  } >>"$GITHUB_STEP_SUMMARY"
fi
