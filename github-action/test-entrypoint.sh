#!/usr/bin/env bash
# ============================================================================
# GitHub Action entrypoint — end-to-end smoke test
# ============================================================================
#
# Drives github-action/entrypoint.sh inside an image built from the CURRENT
# tree, the same way action.yml's `docker run` step does, then asserts on the
# $GITHUB_OUTPUT contract (`endpoints` / `passive_results`).
#
# Why this exists: the composite action `docker pull`s a *pre-built,
# published* image, and ci.yml's docker build uses `push: false` and never
# runs the container — so entrypoint.sh had no CI coverage and changes to it
# shipped untested. This harness closes that gap and is the local
# reproduction tool for entrypoint output-contract bugs.
#
# Usage:
#   docker build -t noir-action:local .
#   github-action/test-entrypoint.sh noir-action:local
set -euo pipefail

IMAGE="${1:?usage: test-entrypoint.sh <image-tag>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$REPO_ROOT/spec/functional_test/fixtures/crystal"

fail_count=0
note_pass() { printf '    \033[32m✓\033[0m %s\n' "$1"; }
note_fail() { printf '    \033[31m✗\033[0m %s\n' "$1"; fail_count=$((fail_count + 1)); }

# Run entrypoint.sh in the image the way action.yml does: mount an isolated
# workspace (root-owned container writes stay out of the checkout), point the
# container's $GITHUB_OUTPUT at a workspace file so we can read the promoted
# outputs back, and forward INPUT_* env. Echoes the workspace dir on success,
# or "__FAILED__ <dir>" if the container exited non-zero.
run_action() {
  local scenario="$1"; shift
  local ws; ws="$(mktemp -d)"
  cp -R "$FIXTURE" "$ws/src"
  if docker run --rm \
      -v "$ws":/github/workspace \
      -w /github/workspace \
      -e GITHUB_OUTPUT=/github/workspace/.noir-output \
      -e INPUT_BASE_PATH="src" \
      "$@" \
      --entrypoint /entrypoint.sh \
      "$IMAGE" >"$ws/stdout" 2>"$ws/stderr"; then
    echo "$ws"
  else
    echo "__FAILED__ $ws"
  fi
}

gh_output() { cat "$1/.noir-output" 2>/dev/null || true; }

echo "==> image:   $IMAGE"
echo "==> fixture: ${FIXTURE#"$REPO_ROOT"/}"

# ---------------------------------------------------------------------------
# Scenario 1: format=json + passive scan — the default, most-used contract.
# ---------------------------------------------------------------------------
echo "[1] format=json, passive_scan=true"
ws="$(run_action json -e INPUT_FORMAT=json -e INPUT_PASSIVE_SCAN=true)"
if [[ "$ws" == __FAILED__* ]]; then
  note_fail "entrypoint exited non-zero"
  cat "${ws#__FAILED__ }/stderr" >&2 || true
else
  out="$(gh_output "$ws")"
  # Every emitted line must be a `name=value` pair. A stray continuation
  # line means a multi-line value slipped into $GITHUB_OUTPUT, which breaks
  # the single-line `name=value` format GitHub expects.
  total=$(printf '%s\n' "$out" | grep -c . || true)
  named=$(printf '%s\n' "$out" | grep -cE '^(endpoints|passive_results)=' || true)
  if [[ "$total" -eq 2 && "$named" -eq 2 ]]; then
    note_pass "exactly 2 well-formed output lines"
  else
    note_fail "expected 2 name=value lines, got total=$total named=$named"
  fi
  ep="$(printf '%s\n' "$out" | sed -n 's/^endpoints=//p')"
  if printf '%s' "$ep" | jq -e '.endpoints | length >= 1' >/dev/null 2>&1; then
    note_pass "endpoints is single-line JSON with >=1 endpoint"
  else
    note_fail "endpoints is not valid JSON with a non-empty endpoints[]"
  fi
  pr="$(printf '%s\n' "$out" | sed -n 's/^passive_results=//p')"
  if printf '%s' "$pr" | jq -e 'type == "array"' >/dev/null 2>&1; then
    note_pass "passive_results is a JSON array"
  else
    note_fail "passive_results is not a JSON array"
  fi
fi

# ---------------------------------------------------------------------------
# Scenario 2: non-JSON format (yaml) — outputs must degrade to the documented
# empty contract, never to malformed JSON that breaks a downstream `jq`.
# ---------------------------------------------------------------------------
echo "[2] format=yaml (non-JSON contract)"
ws="$(run_action yaml -e INPUT_FORMAT=yaml)"
if [[ "$ws" == __FAILED__* ]]; then
  note_fail "entrypoint exited non-zero"
  cat "${ws#__FAILED__ }/stderr" >&2 || true
else
  out="$(gh_output "$ws")"
  if grep -qxF 'endpoints=' <<<"$out"; then
    note_pass "endpoints is empty"
  else
    note_fail "endpoints should be empty for a non-JSON format"
  fi
  if grep -qxF 'passive_results=[]' <<<"$out"; then
    note_pass "passive_results is []"
  else
    note_fail "passive_results should be [] for a non-JSON format"
  fi
fi

# ---------------------------------------------------------------------------
# Scenario 3: diff_ref + fail_on. The workspace is a git repository whose
# only commit predates the fixture, so every endpoint is new. That exercises
# git inside the image (including the root-vs-runner "dubious ownership"
# refusal the entrypoint has to lift), the exit code a fail_on match ends
# with, and that the outputs are still written when it does.
# ---------------------------------------------------------------------------
# $1: label, $2: where the repository sits in the workspace ("." or a
# subdirectory, like `actions/checkout` with `path:`), $3: base_path.
diff_scenario() {
  local label="$1" repo_dir="$2" base="$3"
  echo "$label"
  local ws; ws="$(mktemp -d)"
  local repo="$ws/$repo_dir"
  local src="$ws/$base"
  mkdir -p "$src"
  touch "$src/.keep"
  git -C "$repo" init -q
  git -C "$repo" add -A
  git -C "$repo" -c user.email=ci@noir -c user.name=ci -c commit.gpgsign=false commit -q -m base
  local base_sha; base_sha="$(git -C "$repo" rev-parse HEAD)"
  cp -R "$FIXTURE/." "$src/"
  local rc=0
  docker run --rm \
    -v "$ws":/github/workspace \
    -w /github/workspace \
    -e GITHUB_OUTPUT=/github/workspace/.noir-output \
    -e INPUT_BASE_PATH="$base" \
    -e INPUT_FORMAT=json \
    -e INPUT_DIFF_REF="$base_sha" \
    -e INPUT_FAIL_ON=added \
    --entrypoint /entrypoint.sh \
    "$IMAGE" >"$ws/stdout" 2>"$ws/stderr" || rc=$?
  if [[ "$rc" -eq 3 ]]; then
    note_pass "exits 3 when fail_on matches"
  else
    note_fail "expected exit 3, got $rc"
    cat "$ws/stderr" >&2 || true
  fi
  local ep; ep="$(sed -n 's/^endpoints=//p' "$ws/.noir-output" 2>/dev/null || true)"
  if printf '%s' "$ep" | jq -e '(.added | length >= 1) and (.removed | length == 0)' >/dev/null 2>&1; then
    note_pass "diff document is written and lists the new endpoints as added"
  else
    note_fail "endpoints output is not a diff document with added endpoints"
  fi
}

diff_scenario "[3] diff_ref + fail_on=added" "." "src"
# The repository is not the mount point, so git's ownership check has to
# accept a repository root other than the working directory.
diff_scenario "[4] diff_ref with the repository in a subdirectory" "app" "app/src"

# NOTE: format=jsonl is intentionally not asserted here yet — the current
# entrypoint mishandles the multi-object JSONL stream (emits multi-line
# values that corrupt $GITHUB_OUTPUT). Add a jsonl scenario together with the
# fix for that (stability review, finding M1).

echo
if [[ "$fail_count" -eq 0 ]]; then
  echo "All action entrypoint checks passed."
else
  echo "$fail_count action entrypoint check(s) failed." >&2
  exit 1
fi
