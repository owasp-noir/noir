#!/bin/sh
# shellcheck shell=sh
#
# OWASP Noir GitHub Action entrypoint.
#
# Inputs arrive as INPUT_* environment variables — the composite
# action.yml in the repo root forwards `with:` keys via `docker run -e`.
# The legacy positional form (16 ordered $1..${16}) is no longer
# supported because the action shifted from `using: docker` to
# `using: composite`.
#
# The script builds an argv list with `set --` and execs it directly,
# never `eval`s a string. That way values with shell metacharacters
# (quotes, semicolons, backticks) cannot inject extra commands.

error_exit() {
    echo "Error: $1" >&2
    exit "$2"
}

# ==============================================================================
# Read inputs from environment with defaults
# ==============================================================================
#
# Default for `output_file` writes inside the container (/tmp/...).
# The composite action mounts $GITHUB_WORKSPACE at /github/workspace so
# results land outside the container too — see action.yml.

base_path="${INPUT_BASE_PATH:-.}"
url="${INPUT_URL:-}"
format="${INPUT_FORMAT:-json}"
output_file="${INPUT_OUTPUT_FILE:-/tmp/noir_output.json}"
techs="${INPUT_TECHS:-}"
exclude_techs="${INPUT_EXCLUDE_TECHS:-}"
passive_scan="${INPUT_PASSIVE_SCAN:-false}"
passive_scan_severity="${INPUT_PASSIVE_SCAN_SEVERITY:-high}"
use_all_taggers="${INPUT_USE_ALL_TAGGERS:-false}"
use_taggers="${INPUT_USE_TAGGERS:-}"
include_path="${INPUT_INCLUDE_PATH:-false}"
verbose="${INPUT_VERBOSE:-false}"
debug="${INPUT_DEBUG:-false}"
concurrency="${INPUT_CONCURRENCY:-}"
exclude_codes="${INPUT_EXCLUDE_CODES:-}"
status_codes="${INPUT_STATUS_CODES:-false}"
ai_provider="${INPUT_AI_PROVIDER:-}"
ai_model="${INPUT_AI_MODEL:-}"
ai_key="${INPUT_AI_KEY:-}"
ai_agent="${INPUT_AI_AGENT:-false}"
probe="${INPUT_PROBE:-false}"
probe_via="${INPUT_PROBE_VIA:-}"
export_es="${INPUT_EXPORT_ES:-}"
export_webhook="${INPUT_EXPORT_WEBHOOK:-}"
diff_path="${INPUT_DIFF_PATH:-}"
no_log="${INPUT_NO_LOG:-true}"

# ==============================================================================
# Build noir argv safely
# ==============================================================================
#
# Build noir's argv in $@ via `set --`. Using positional parameters for
# the command lets us exec it with the runtime's quoting preserved, so
# values containing whitespace, quotes, or shell metacharacters can
# never break out of their slot.

set -- noir -b "$base_path" -f "$format" -o "$output_file"

[ "$no_log" = "true" ]  && set -- "$@" --no-log
[ -n "$url" ]           && set -- "$@" -u "$url"
[ -n "$techs" ]         && set -- "$@" -t "$techs"
[ -n "$exclude_techs" ] && set -- "$@" --exclude-techs "$exclude_techs"

if [ "$passive_scan" = "true" ]; then
    set -- "$@" -P
    [ -n "$passive_scan_severity" ] && set -- "$@" --passive-scan-severity "$passive_scan_severity"
fi

[ "$use_all_taggers" = "true" ]  && set -- "$@" -T
[ -n "$use_taggers" ]            && set -- "$@" --use-taggers "$use_taggers"
[ "$include_path" = "true" ]     && set -- "$@" --include-path
[ "$verbose" = "true" ]          && set -- "$@" --verbose
[ "$debug" = "true" ]            && set -- "$@" -d
[ -n "$concurrency" ]            && set -- "$@" --concurrency "$concurrency"
[ -n "$exclude_codes" ]          && set -- "$@" --exclude-codes "$exclude_codes"
[ "$status_codes" = "true" ]     && set -- "$@" --status-codes
[ -n "$ai_provider" ]            && set -- "$@" --ai-provider "$ai_provider"
[ -n "$ai_model" ]               && set -- "$@" --ai-model "$ai_model"
[ -n "$ai_key" ]                 && set -- "$@" --ai-key "$ai_key"
[ "$ai_agent" = "true" ]         && set -- "$@" --ai-agent
[ "$probe" = "true" ]            && set -- "$@" --probe
[ -n "$probe_via" ]              && set -- "$@" --probe-via "$probe_via"
[ -n "$export_es" ]              && set -- "$@" --export-es "$export_es"
[ -n "$export_webhook" ]         && set -- "$@" --export-webhook "$export_webhook"
[ -n "$diff_path" ]              && set -- "$@" --diff-path "$diff_path"

# ==============================================================================
# Execute
# ==============================================================================

echo "Executing command: $*"
"$@"
exit_code=$?

[ $exit_code -ne 0 ] && error_exit "Noir command failed with exit code $exit_code" $exit_code
[ ! -f "$output_file" ] && error_exit "Output file $output_file not found" 1

# ==============================================================================
# Process Output
# ==============================================================================

# GITHUB_OUTPUT may be absent when this image is run outside a GitHub
# Action (e.g. ad-hoc `docker run`). Fall back to /dev/null so the
# script still finishes cleanly with the scan results on disk.
github_output="${GITHUB_OUTPUT:-/dev/null}"

if [ "$format" = "json" ] || [ "$format" = "jsonl" ]; then
    if command -v jq >/dev/null 2>&1; then
        jq empty "$output_file" 2>/dev/null || error_exit "Invalid JSON output from Noir" 1

        endpoints_output=$(jq -c . "$output_file")
        passive_results=$(jq -c '.passive_results // []' "$output_file")

        echo "endpoints=$endpoints_output" >> "$github_output"
        echo "passive_results=$passive_results" >> "$github_output"
    else
        endpoints_output=$(tr -d '\n' < "$output_file")
        echo "endpoints=$endpoints_output" >> "$github_output"
        echo "passive_results=[]" >> "$github_output"
    fi
else
    # Non-JSON formats (plain, yaml, oas3, mermaid, ...) don't fit
    # the JSON contract of the `endpoints` / `passive_results`
    # outputs. Emit them as empty so downstream `jq` calls don't
    # choke on plain text. The raw output file is still on disk —
    # upload it with `actions/upload-artifact` per README.
    echo "endpoints=" >> "$github_output"
    echo "passive_results=[]" >> "$github_output"
fi

# ==============================================================================
# Summary
# ==============================================================================

echo "Noir analysis completed successfully"
echo "Output format: $format"
echo "Output file:   $output_file"
