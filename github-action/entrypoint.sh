#!/bin/sh -l

# Argument positions (kept in sync with action.yml `runs.args`):
#   $1  base_path
#   $2  url
#   $3  format
#   $4  output_file
#   $5  techs
#   $6  exclude_techs
#   $7  passive_scan
#   $8  passive_scan_severity
#   $9  use_all_taggers
#   $10 use_taggers
#   $11 include_path
#   $12 verbose
#   $13 debug
#   $14 concurrency
#   $15 exclude_codes
#   $16 status_codes
#
# The script builds an argv list with `set --` and execs it directly,
# never `eval`s a string. That way values with shell metacharacters
# (quotes, semicolons, backticks) cannot inject extra commands.

error_exit() {
    echo "Error: $1" >&2
    exit "$2"
}

# ==============================================================================
# Initialize Variables
# ==============================================================================

base_path="$1"
url="$2"
format="${3:-json}"
output_file="${4:-/tmp/noir_output.json}"
techs="$5"
exclude_techs="$6"
passive_scan="$7"
passive_scan_severity="$8"
use_all_taggers="$9"
use_taggers="${10}"
include_path="${11}"
verbose="${12}"
debug="${13}"
concurrency="${14}"
exclude_codes="${15}"
status_codes="${16}"

# ==============================================================================
# Build noir argv safely
# ==============================================================================
#
# Snapshot the action inputs into named variables above, then build
# noir's argv in $@ via `set --`. Using positional parameters for the
# command lets us exec it with the runtime's quoting preserved, so
# values containing whitespace, quotes, or shell metacharacters can
# never break out of their slot.

set -- noir -b "$base_path" --no-log -f "$format" -o "$output_file"

[ -n "$url" ]           && set -- "$@" -u "$url"
[ -n "$techs" ]         && set -- "$@" -t "$techs"
[ -n "$exclude_techs" ] && set -- "$@" --exclude-techs "$exclude_techs"

if [ "$passive_scan" = "true" ]; then
    set -- "$@" -P
    [ -n "$passive_scan_severity" ] && set -- "$@" --passive-scan-severity "$passive_scan_severity"
fi

[ "$use_all_taggers" = "true" ] && set -- "$@" -T
[ -n "$use_taggers" ]           && set -- "$@" --use-taggers "$use_taggers"
[ "$include_path" = "true" ]    && set -- "$@" --include-path
[ "$verbose" = "true" ]         && set -- "$@" --verbose
[ "$debug" = "true" ]           && set -- "$@" -d
[ -n "$concurrency" ]           && set -- "$@" --concurrency "$concurrency"
[ -n "$exclude_codes" ]         && set -- "$@" --exclude-codes "$exclude_codes"
[ "$status_codes" = "true" ]    && set -- "$@" --status-codes

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

if [ "$format" = "json" ] || [ "$format" = "jsonl" ]; then
    if command -v jq >/dev/null 2>&1; then
        jq empty "$output_file" 2>/dev/null || error_exit "Invalid JSON output from Noir" 1

        endpoints_output=$(jq -c . "$output_file")
        passive_results=$(jq -c '.passive_results // []' "$output_file")

        echo "endpoints=$endpoints_output" >> "$GITHUB_OUTPUT"
        echo "passive_results=$passive_results" >> "$GITHUB_OUTPUT"
    else
        endpoints_output=$(tr -d '\n' < "$output_file")
        echo "endpoints=$endpoints_output" >> "$GITHUB_OUTPUT"
        echo "passive_results=[]" >> "$GITHUB_OUTPUT"
    fi
else
    # Non-JSON formats (plain, yaml, oas3, mermaid, ...) don't fit
    # the JSON contract of the `endpoints` / `passive_results`
    # outputs. Emit them as empty so downstream `jq` calls don't
    # choke on plain text. The raw output file is still on disk —
    # upload it with `actions/upload-artifact` per README.
    echo "endpoints=" >> "$GITHUB_OUTPUT"
    echo "passive_results=[]" >> "$GITHUB_OUTPUT"
fi

# ==============================================================================
# Summary
# ==============================================================================

echo "Noir analysis completed successfully"
echo "Output format: $format"
echo "Output file:   $output_file"
