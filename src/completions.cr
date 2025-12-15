def generate_zsh_completion_script
  <<-SCRIPT
#compdef noir

_arguments \\
  '-b[Set base path]:path:_files' \\
  '-u[Set base URL for endpoints]:URL:_urls' \\
  '-f[Set output format]:format:(plain yaml json jsonl markdown-table sarif html curl httpie oas2 oas3 postman only-url only-param only-header only-cookie only-tag mermaid)' \\
  '-o[Write result to file]:path:_files' \\
  '--set-pvalue[Specifies the value of the identified parameter]:value:' \\
  '--set-pvalue-header[Specifies the value of the identified parameter for headers]:value:' \\
  '--set-pvalue-cookie[Specifies the value of the identified parameter for cookies]:value:' \\
  '--set-pvalue-query[Specifies the value of the identified parameter for query parameters]:value:' \\
  '--set-pvalue-form[Specifies the value of the identified parameter for form data]:value:' \\
  '--set-pvalue-json[Specifies the value of the identified parameter for JSON data]:value:' \\
  '--set-pvalue-path[Specifies the value of the identified parameter for path parameters]:value:' \\
  '--status-codes[Display HTTP status codes for discovered endpoints]' \\
  '--exclude-codes[Exclude specific HTTP response codes (comma-separated)]:status:' \\
  '--include-path[Include file path in the plain result]' \\
  '--no-color[Disable color output]' \\
  '--no-log[Displaying only the results]' \\
  '-P[Perform a passive scan for security issues using rules from the specified path]' \\
  '--passive-scan[Enable passive security scan]' \\
  '--passive-scan-path[Specify the path for the rules used in the passive security scan]:path:_files' \\
  '--passive-scan-severity[Min severity (critical|high|medium|low, default: high)]:severity:(critical high medium low)' \\
  '--passive-scan-auto-update[Auto-update rules at startup]' \\
  '--passive-scan-no-update-check[Skip rule update check]' \\
  '-T[Activates all taggers for full analysis coverage]' \\
  '--use-taggers[Activates specific taggers]:values:' \\
  '--list-taggers[Lists all available taggers]' \\
  '--send-req[Send results to a web request]' \\
  '--send-proxy[Send results to a web request via an HTTP proxy]:proxy:' \\
  '--send-es[Send results to Elasticsearch]:es:' \\
  '--with-headers[Add custom headers to be included in the delivery]:headers:' \\
  '--use-matchers[Send URLs that match specific conditions to the Deliver]:string:' \\
  '--use-filters[Exclude URLs that match specified conditions and send the rest to Deliver]:string:' \\
  '--diff-path[Specify the path to the old version of the source code for comparison]:path:_files' \\
  '-t[Specify the technologies to use]:techs:' \\
  '--exclude-techs[Specify the technologies to be excluded]:techs:' \\
  '--list-techs[Show all technologies]' \\
  '--config-file[Specify the path to a configuration file in YAML format]:path:_files' \\
  '--concurrency[Set concurrency]:concurrency:' \\
  '--generate-completion[Generate Zsh/Bash/Fish completion script]:completion:(zsh bash fish)' \\
  '--cache-disable[Disable LLM cache]' \\
  '--cache-clear[Clear LLM cache before run]' \\
  '--ai-provider[Specify the AI (LLM) provider or custom API URL]:provider:' \\
  '--ai-model[Set the model name to use for AI analysis]:model:' \\
  '--ai-key[Provide the API key for the AI provider]:key:' \\
  '--ai-max-token[Set the maximum number of tokens for AI requests]:value:' \\
  '--ollama[Specify the Ollama server URL (Deprecated)]:URL:_urls' \\
  '--ollama-model[Specify the Ollama model name (Deprecated)]:model:' \\
  '-d[Show debug messages]' \\
  '-v[Show version]' \\
  '--build-info[Show version and Build info]' \\
  '--verbose[Show verbose output]' \\
  '--help-all[Show all help]' \\
  '-h[Show help]'
SCRIPT
end

def generate_bash_completion_script
  <<-SCRIPT
_noir_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="
        -b --base-path
        -u --url
        -f --format
        -o --output
        --set-pvalue
        --set-pvalue-header
        --set-pvalue-cookie
        --set-pvalue-query
        --set-pvalue-form
        --set-pvalue-json
        --set-pvalue-path
        --status-codes
        --exclude-codes
        --include-path
        --no-color
        --no-log
        -P --passive-scan
        --passive-scan-path
        --passive-scan-severity
        --passive-scan-auto-update
        --passive-scan-no-update-check
        -T --use-all-taggers
        --use-taggers
        --list-taggers
        --send-req
        --send-proxy
        --send-es
        --with-headers
        --use-matchers
        --use-filters
        --diff-path
        -t --techs
        --exclude-techs
        --list-techs
        --config-file
        --concurrency
        --generate-completion
        --cache-disable
        --cache-clear
        --ai-provider
        --ai-model
        --ai-key
        --ai-max-token
        --ollama
        --ollama-model
        -d --debug
        -v --version
        --build-info
        --verbose
        --help-all
        -h --help
    "

    case "${prev}" in
        -f|--format)
            COMPREPLY=( $(compgen -W "plain yaml json jsonl markdown-table sarif html curl httpie oas2 oas3 postman only-url only-param only-header only-cookie only-tag mermaid" -- "${cur}") )
            return 0
            ;;
        --send-proxy|--send-es|--with-headers|--use-matchers|--use-filters|--diff-path|--config-file|--set-pvalue|--techs|--exclude-techs|--ollama|--ollama-model|-o|-b|-u)
            COMPREPLY=( $(compgen -f -- "${cur}") )
            return 0
            ;;
        --generate-completion)
            COMPREPLY=( $(compgen -W "zsh bash fish" -- "${cur}") )
            return 0
            ;;
        --passive-scan-severity)
            COMPREPLY=( $(compgen -W "critical high medium low" -- "${cur}") )
            return 0
            ;;
        --ai-provider|--ai-model|--ai-key|--ai-max-token|--ollama|--ollama-model)
            COMPREPLY=( $(compgen -f -- "${cur}") )
            return 0
            ;;
        *)
            ;;
    esac

    COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
    return 0
}

complete -F _noir_completions noir
SCRIPT
end

def generate_fish_completion_script
  <<-SCRIPT
function __fish_noir_needs_command
    set -l cmd (commandline -opc)
    if test (count $cmd) -eq 1
        return 0
    end
    return 1
end

complete -c noir -n '__fish_noir_needs_command' -a '-b' -d 'Set base path'
complete -c noir -n '__fish_noir_needs_command' -a '-u' -d 'Set base URL for endpoints'
complete -c noir -n '__fish_noir_needs_command' -a '-f' -d 'Set output format'
complete -c noir -n '__fish_noir_needs_command' -a '-o' -d 'Write result to file'
complete -c noir -n '__fish_noir_needs_command' -a '--set-pvalue' -d 'Specifies the value of the identified parameter'
complete -c noir -n '__fish_noir_needs_command' -a '--set-pvalue-header' -d 'Specifies the value of the identified parameter for headers'
complete -c noir -n '__fish_noir_needs_command' -a '--set-pvalue-cookie' -d 'Specifies the value of the identified parameter for cookies'
complete -c noir -n '__fish_noir_needs_command' -a '--set-pvalue-query' -d 'Specifies the value of the identified parameter for query parameters'
complete -c noir -n '__fish_noir_needs_command' -a '--set-pvalue-form' -d 'Specifies the value of the identified parameter for form data'
complete -c noir -n '__fish_noir_needs_command' -a '--set-pvalue-json' -d 'Specifies the value of the identified parameter for JSON data'
complete -c noir -n '__fish_noir_needs_command' -a '--set-pvalue-path' -d 'Specifies the value of the identified parameter for path parameters'
complete -c noir -n '__fish_noir_needs_command' -a '--status-codes' -d 'Display HTTP status codes for discovered endpoints'
complete -c noir -n '__fish_noir_needs_command' -a '--exclude-codes' -d 'Exclude specific HTTP response codes (comma-separated)'
complete -c noir -n '__fish_noir_needs_command' -a '--include-path' -d 'Include file path in the plain result'
complete -c noir -n '__fish_noir_needs_command' -a '--no-color' -d 'Disable color output'
complete -c noir -n '__fish_noir_needs_command' -a '--no-log' -d 'Displaying only the results'
complete -c noir -n '__fish_noir_needs_command' -a '-P' -d 'Perform a passive scan for security issues using rules from the specified path'
complete -c noir -n '__fish_noir_needs_command' -a '--passive-scan' -d 'Enable passive security scan'
complete -c noir -n '__fish_noir_needs_command' -a '--passive-scan-path' -d 'Specify the path for the rules used in the passive security scan'
complete -c noir -n '__fish_noir_needs_command' -a '--passive-scan-severity' -d 'Min severity (critical|high|medium|low, default: high)'
complete -c noir -n '__fish_noir_needs_command' -a '--passive-scan-auto-update' -d 'Auto-update rules at startup'
complete -c noir -n '__fish_noir_needs_command' -a '--passive-scan-no-update-check' -d 'Skip rule update check'
complete -c noir -n '__fish_noir_needs_command' -a '-T' -d 'Activates all taggers for full analysis coverage'
complete -c noir -n '__fish_noir_needs_command' -a '--use-taggers' -d 'Activates specific taggers'
complete -c noir -n '__fish_noir_needs_command' -a '--list-taggers' -d 'Lists all available taggers'
complete -c noir -n '__fish_noir_needs_command' -a '--send-req' -d 'Send results to a web request'
complete -c noir -n '__fish_noir_needs_command' -a '--send-proxy' -d 'Send results to a web request via an HTTP proxy'
complete -c noir -n '__fish_noir_needs_command' -a '--send-es' -d 'Send results to Elasticsearch'
complete -c noir -n '__fish_noir_needs_command' -a '--with-headers' -d 'Add custom headers to be included in the delivery'
complete -c noir -n '__fish_noir_needs_command' -a '--use-matchers' -d 'Send URLs that match specific conditions to the Deliver'
complete -c noir -n '__fish_noir_needs_command' -a '--use-filters' -d 'Exclude URLs that match specified conditions and send the rest to Deliver'
complete -c noir -n '__fish_noir_needs_command' -a '--diff-path' -d 'Specify the path to the old version of the source code for comparison'
complete -c noir -n '__fish_noir_needs_command' -a '-t' -d 'Specify the technologies to use'
complete -c noir -n '__fish_noir_needs_command' -a '--exclude-techs' -d 'Specify the technologies to be excluded'
complete -c noir -n '__fish_noir_needs_command' -a '--list-techs' -d 'Show all technologies'
complete -c noir -n '__fish_noir_needs_command' -a '--config-file' -d 'Specify the path to a configuration file in YAML format'
complete -c noir -n '__fish_noir_needs_command' -a '--concurrency' -d 'Set concurrency'
complete -c noir -n '__fish_noir_needs_command' -a '--generate-completion' -d 'Generate Zsh/Bash/Fish completion script'
complete -c noir -n '__fish_noir_needs_command' -a '--cache-disable' -d 'Disable LLM cache'
complete -c noir -n '__fish_noir_needs_command' -a '--cache-clear' -d 'Clear LLM cache before run'
complete -c noir -n '__fish_noir_needs_command' -a '--ai-provider' -d 'Specify the AI (LLM) provider or custom API URL'
complete -c noir -n '__fish_noir_needs_command' -a '--ai-model' -d 'Set the model name to use for AI analysis'
complete -c noir -n '__fish_noir_needs_command' -a '--ai-key' -d 'Provide the API key for the AI provider'
complete -c noir -n '__fish_noir_needs_command' -a '--ai-max-token' -d 'Set the maximum number of tokens for AI requests'
complete -c noir -n '__fish_noir_needs_command' -a '--ollama' -d 'Specify the Ollama server URL (Deprecated)'
complete -c noir -n '__fish_noir_needs_command' -a '--ollama-model' -d 'Specify the Ollama model name (Deprecated)'
complete -c noir -n '__fish_noir_needs_command' -a '-d' -d 'Show debug messages'
complete -c noir -n '__fish_noir_needs_command' -a '-v' -d 'Show version'
complete -c noir -n '__fish_noir_needs_command' -a '--build-info' -d 'Show version and Build info'
complete -c noir -n '__fish_noir_needs_command' -a '--verbose' -d 'Show verbose messages'
complete -c noir -n '__fish_noir_needs_command' -a '--help-all' -d 'Show all help'
complete -c noir -n '__fish_noir_needs_command' -a '-h' -d 'Show help'
SCRIPT
end
