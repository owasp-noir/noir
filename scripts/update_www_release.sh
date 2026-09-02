#!/usr/bin/env bash
# Add a released version to the OWASP project page's version list and open a
# pull request against the upstream OWASP repository.
#
# The page at https://owasp.org/www-project-noir/ renders the download tab from
# _data/release.yml, a plain list of the most recent tags. Keeping it current
# used to be a manual web-UI edit after every release; this script does the same
# edit through the owasp-noir fork so the change arrives as a reviewable PR.
#
# Usage: scripts/update_www_release.sh <tag> [--keep N] [--dry-run]
#
#   <tag>       Release tag, with or without the leading "v" (e.g. v1.3.1).
#   --keep N    How many versions the list keeps; older ones are dropped from
#               the bottom (default: 5, matching the list as it stands today).
#   --dry-run   Print the resulting diff and stop before pushing or opening a PR.
#
# Re-running for a tag that is already listed is a no-op, so a re-published
# release or a retried workflow will not produce a second pull request.
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
  a classic token needs the 'repo' scope. Opening the PR against $UPSTREAM_REPO
  needs no extra permission beyond that."
fi

# Opening the pull request writes to a repository the OWASP Foundation
# enterprise owns, and that enterprise applies its own token policy on top of
# the token's own permissions. Probe it here so the log says up front whether
# the last step can work; the edit and the push to the fork are worth doing
# either way, since the pull request can then be opened from a browser.
upstream_probe="$(gh api "repos/$UPSTREAM_REPO" --jq '.id' 2>&1 >/dev/null || true)"
if [[ -n "$upstream_probe" ]]; then
  echo "warning: the token cannot read $UPSTREAM_REPO, so opening the pull request will likely fail:" >&2
  echo "  $upstream_probe" >&2
fi

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "==> Syncing $FORK_REPO from $UPSTREAM_REPO"
gh repo sync "$FORK_REPO" --source "$UPSTREAM_REPO" --branch "$BASE_BRANCH"

# A still-open PR from an earlier release means the fork's main does not yet
# carry that version, so this run would silently drop it from the list.
open_prs="$(gh pr list --repo "$UPSTREAM_REPO" --state open --json headRefName,url \
  --jq ".[] | select(.headRefName | startswith(\"release/\")) | .url" 2>/dev/null || echo "")"
if [[ -n "$open_prs" ]]; then
  echo "warning: release PRs are still open upstream; their versions are not in the base yet:" >&2
  while IFS= read -r pr; do echo "  $pr" >&2; done <<<"$open_prs"
fi

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
  echo "==> Dry run: stopping before push and pull request."
  exit 0
fi

git config user.email >/dev/null 2>&1 || git config user.email "$DEFAULT_COMMIT_EMAIL"
git config user.name >/dev/null 2>&1 || git config user.name "$DEFAULT_COMMIT_NAME"

BRANCH="release/$TAG"
git checkout -q -b "$BRANCH"
git add "$DATA_FILE"
git commit -q -m "Add $TAG to release.yml" -m "Co-authored-by: $COAUTHOR"

# Authenticate the push through the throwaway clone's remote so no credential
# helper is installed on the machine running this and no token reaches argv.
token="$(gh auth token)"
git remote set-url --push origin "https://x-access-token:${token}@github.com/${FORK_REPO}.git"

echo "==> Pushing $BRANCH to $FORK_REPO"
git push -q --force-with-lease origin "$BRANCH"

echo "==> Opening pull request against $UPSTREAM_REPO"
pr_body="Adds \`$TAG\` to the version list rendered on the project page.

Released at https://github.com/owasp-noir/noir/releases/tag/$TAG

Opened automatically from the noir release workflow."

if pr_url="$(gh pr create \
  --repo "$UPSTREAM_REPO" \
  --base "$BASE_BRANCH" \
  --head "$FORK_OWNER:$BRANCH" \
  --title "Add $TAG to release.yml" \
  --body "$pr_body" 2>&1)"; then
  echo "$pr_url"
else
  # A retry after a partial failure finds the pull request already open.
  existing_pr="$(gh pr list --repo "$UPSTREAM_REPO" --state open \
    --head "$FORK_OWNER:$BRANCH" --json url --jq '.[0].url' 2>/dev/null || echo "")"
  if [[ -n "$existing_pr" ]]; then
    echo "==> Pull request already open: $existing_pr"
  else
    # The commit is already on the fork, so the work is not lost: opening the
    # pull request by hand is one click away. Creating it through the API needs
    # pull-request write access to a repository the token's owner does not own,
    # which a fine-grained token cannot hold - that is a token choice, not
    # something this script can retry its way out of.
    echo "$pr_url" >&2
    echo "" >&2
    echo "The branch is pushed. Open the pull request here:" >&2
    echo "  https://github.com/$UPSTREAM_REPO/compare/$BASE_BRANCH...$FORK_OWNER:$BRANCH?expand=1" >&2
    die "failed to open the pull request"
  fi
fi
