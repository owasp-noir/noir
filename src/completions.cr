def generate_zsh_completion_script
  <<-SCRIPT
      #compdef noir

      _arguments \\
        '-b[Set base path]:path:_files' \\
        '-u[Set base URL for endpoints]:URL:_urls' \\
        '-f[Set output format]:format:(plain yaml json jsonl markdown-table curl httpie oas2 oas3 only-url only-param only-header only-cookie)' \\
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
        '-d[Show debug messages]' \\
        '-v[Show version]' \\
        '--build-info[Show version and Build info]' \\
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
                -d --debug
                -v --version
                --build-info
                -h --help
            "

            case "${prev}" in
                -f|--format)
                    COMPREPLY=( $(compgen -W "plain yaml json jsonl markdown-table curl httpie oas2 oas3 only-url only-param only-header only-cookie" -- "${cur}") )
                    return 0
                    ;;
                --send-proxy|--send-es|--with-headers|--use-matchers|--use-filters|--diff-path|--config-file|--set-pvalue|--techs|--exclude-techs|-o|-b|-u)
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
