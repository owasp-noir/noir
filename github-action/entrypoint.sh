#!/bin/sh -l

# Arguments mapping:
# $1 : base_path
# $2 : url
# $3 : format
# $4 : output_file
# $5 : techs
# $6 : exclude_techs
# $7 : passive_scan
# $8 : passive_scan_severity
# $9 : use_all_taggers
# $10 : use_taggers
# $11 : include_path
# $12 : verbose
# $13 : debug
# $14 : concurrency
# $15 : exclude_codes
# $16 : status_codes

# ==============================================================================
# Helper Functions
# ==============================================================================

# Add option with value to command if value is not empty
# Usage: add_option "flag" "value"
add_option() {
    flag="$1"
    value="$2"
    [ -n "$value" ] && cmd="$cmd $flag '$value'"
}

# Add flag to command if condition is "true"
# Usage: add_flag "flag" "condition"
add_flag() {
    flag="$1"
    condition="$2"
    [ "$condition" = "true" ] && cmd="$cmd $flag"
}

# Print error message and exit with given code
# Usage: error_exit "message" exit_code
error_exit() {
    echo "Error: $1"
    exit "$2"
}

# ==============================================================================
# Initialize Variables
# ==============================================================================

format="${3:-json}"
output_file="${4:-/tmp/noir_output.json}"

# ==============================================================================
# Build Command
# ==============================================================================

cmd="noir -b '$1' --no-log"
cmd="$cmd -f $format"
cmd="$cmd -o '$output_file'"

add_option "-u" "$2"
add_option "-t" "$5"
add_option "--exclude-techs" "$6"

add_flag "-P" "$7"
[ "$7" = "true" ] && add_option "--passive-scan-severity" "$8"

add_flag "-T" "$9"
add_option "--use-taggers" "${10}"

add_flag "--include-path" "${11}"
add_flag "--verbose" "${12}"
add_flag "-d" "${13}"

add_option "--concurrency" "${14}"
add_option "--exclude-codes" "${15}"

add_flag "--status-codes" "${16}"

# ==============================================================================
# Execute Command
# ==============================================================================

echo "Executing command: $cmd"
eval "$cmd"
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
    endpoints_output=$(tr -d '\n' < "$output_file")
    echo "endpoints=$endpoints_output" >> "$GITHUB_OUTPUT"
    echo "passive_results=[]" >> "$GITHUB_OUTPUT"
fi

# ==============================================================================
# Summary
# ==============================================================================

echo "Noir analysis completed successfully"
echo "Output format: $format"
echo "Results written to GitHub Actions output variables"