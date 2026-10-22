#!/usr/bin/env bash
# ============================================================================
# Resolve which ghcr.io/owasp-noir/noir image tag the action should run,
# from the git ref the consumer pinned the action to (`github.action_ref`).
# ============================================================================
#
# Prints the resolved tag on stdout; degrade warnings go to stderr so the
# stdout capture in action.yml stays clean.
#
# Rules (first match wins):
#   (empty)                  -> latest    local `uses: ./`, or an unpinned
#                                          consumer — action_ref is empty
#   v1.1.0 / 1.1.0 / v1 / v1.1
#                            -> 1.1.0 / 1.1.0 / 1 / 1.1
#                                          semver-ish release ref: strip a
#                                          leading `v` to match the published
#                                          image tags (which are unprefixed)
#   <7-40 hex chars>         -> latest    commit-SHA pin: no per-commit image
#                                          is published, so degrade rather
#                                          than pull a tag that cannot exist.
#                                          Warns; pin a release tag for a
#                                          reproducible image.
#   <anything else>          -> as-is     branch ref (e.g. main -> :main).
#                                          action.yml pulls with a :latest
#                                          fallback, so a branch with no
#                                          published image still degrades
#                                          instead of hard-failing.
#
# The old inline logic in action.yml was `TAG="${REF#v}"`, which stripped a
# leading `v` from *any* ref (so a branch named `validate` became `alidate`)
# and mapped commit-SHA pins to `noir:<sha>` — an image that is never
# published, breaking the security-recommended SHA-pin usage outright.
set -euo pipefail

ref="${1-${GITHUB_ACTION_REF-}}"
warn() { echo "noir-action: $*" >&2; }

if [ -z "$ref" ]; then
  tag="latest"
elif printf '%s' "$ref" | grep -Eq '^v?[0-9]+(\.[0-9]+){0,2}([-+][0-9A-Za-z.-]+)?$'; then
  # semver-ish (optionally v-prefixed): v1, v1.2, v1.2.3, 1.2.3-rc1, ...
  tag="${ref#v}"
elif printf '%s' "$ref" | grep -Eiq '^[0-9a-f]{7,40}$'; then
  warn "pinned to commit SHA '$ref'; no per-commit image is published — using ':latest'. Pin a release tag (e.g. @v1.1.0) for a reproducible image."
  tag="latest"
else
  tag="$ref"
fi

printf '%s\n' "$tag"
