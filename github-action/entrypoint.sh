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

# Set up base command with required parameters
cmd="noir -b '$1' --no-log"

# Add URL if provided
[ -n "$2" ] && cmd="$cmd -u '$2'"

# Set format (default to json if not provided)
format="$3"
[ -z "$format" ] && format="json"
cmd="$cmd -f $format"

# Add output file if specified
[ -n "$4" ] && cmd="$cmd -o '$4'"

# Add technologies if specified
[ -n "$5" ] && cmd="$cmd -t '$5'"

# Add excluded technologies if specified
[ -n "$6" ] && cmd="$cmd --exclude-techs '$6'"

# Add passive scan if enabled
[ "$7" = "true" ] && cmd="$cmd -P"

# Add passive scan severity if passive scan is enabled and severity is specified
[ "$7" = "true" ] && [ -n "$8" ] && cmd="$cmd --passive-scan-severity '$8'"

# Add all taggers if enabled
[ "$9" = "true" ] && cmd="$cmd -T"

# Add specific taggers if specified
[ -n "${10}" ] && cmd="$cmd --use-taggers '${10}'"

# Add include path if enabled
[ "${11}" = "true" ] && cmd="$cmd --include-path"

# Add verbose if enabled
[ "${12}" = "true" ] && cmd="$cmd --verbose"

# Add debug if enabled
[ "${13}" = "true" ] && cmd="$cmd -d"

# Add concurrency if specified
[ -n "${14}" ] && cmd="$cmd --concurrency '${14}'"

# Add exclude codes if specified
[ -n "${15}" ] && cmd="$cmd --exclude-codes '${15}'"

# Add status codes if enabled
[ "${16}" = "true" ] && cmd="$cmd --status-codes"

# Set output file for JSON results if not specified
output_file=""
if [ -n "$4" ]; then
    output_file="$4"
else
    output_file="/tmp/noir_output.json"
    cmd="$cmd -o '$output_file'"
fi

echo "Executing command: $cmd"

# Execute the command
eval "$cmd"
exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo "Error: Noir command failed with exit code $exit_code"
    exit $exit_code
fi

# Check if the output file exists
if [ ! -f "$output_file" ]; then
    echo "Error: Output file $output_file not found"
    exit 1
fi

# Read the output and set it as a GitHub Action output
if [ "$format" = "json" ] || [ "$format" = "jsonl" ]; then
    # For JSON output, validate and format for GitHub Actions
    if command -v jq >/dev/null 2>&1; then
        # Validate JSON and compress for GitHub Actions output
        if jq empty "$output_file" 2>/dev/null; then
            endpoints_output=$(cat "$output_file" | jq -c .)
            echo "endpoints=$endpoints_output" >> $GITHUB_OUTPUT
            
            # If there are passive results, extract them separately
            passive_results=$(echo "$endpoints_output" | jq -c '.passive_results // []')
            echo "passive_results=$passive_results" >> $GITHUB_OUTPUT
        else
            echo "Error: Invalid JSON output from Noir"
            exit 1
        fi
    else
        # Fallback if jq is not available
        endpoints_output=$(cat "$output_file" | tr -d '\n')
        echo "endpoints=$endpoints_output" >> $GITHUB_OUTPUT
        echo "passive_results=[]" >> $GITHUB_OUTPUT
    fi
else
    # For non-JSON formats, just output the raw content
    endpoints_output=$(cat "$output_file" | tr -d '\n')
    echo "endpoints=$endpoints_output" >> $GITHUB_OUTPUT
    echo "passive_results=[]" >> $GITHUB_OUTPUT
fi

echo "Noir analysis completed successfully"
echo "Output format: $format"
echo "Results written to GitHub Actions output variables"