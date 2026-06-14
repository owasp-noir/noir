# Shell completion scripts for the v1 `noir` CLI.
#
# v1 introduces subcommands (scan, list, cache, config, rules, completion,
# version, help) on top of the v0 flag-only surface. Completions are
# subcommand-aware: typing `noir <TAB>` lists the verbs; typing
# `noir scan <TAB>` falls back to scan-specific paths/flags.
#
# The v0 flag set is still completed under `noir scan` (and under bare
# `noir` for backward compatibility with users who haven't switched to
# the verb form).

private FORMATS = "plain yaml json jsonl toml markdown-table sarif html curl httpie powershell adb simctl oas2 oas3 postman only-url only-param only-header only-cookie only-tag mermaid"

private SCAN_FLAGS = %w[
  -b --base-path
  -u --url
  -f --format
  -o --output
  --pvalue
  --set-pvalue
  --set-pvalue-header
  --set-pvalue-cookie
  --set-pvalue-query
  --set-pvalue-form
  --set-pvalue-json
  --set-pvalue-path
  --status-codes
  --exclude-codes
  --exclude-path
  --include
  --include-path
  --include-techs
  --include-callee
  --ai-context
  --no-color
  --no-spinner
  --no-log
  -P --passive-scan
  --passive-scan-path
  --passive-scan-severity
  --passive-scan-auto-update
  --passive-scan-no-update-check
  -T --use-all-taggers
  --use-taggers
  --probe
  --probe-via
  --probe-header
  --probe-match
  --probe-skip
  --export-es
  --export-opensearch
  --export-webhook
  --ai-provider
  --ai-model
  --ai-key
  --ai-agent
  --ai-agent-max-steps
  --ai-native-tools-allowlist
  --ai-max-token
  --diff-path
  -t --techs
  --exclude-techs
  --only-techs
  --config-file
  --concurrency
  --cache-disable
  --cache-clear
  -d --debug
  --verbose
  -v --version
  -h --help
]

def generate_zsh_completion_script
  <<-SCRIPT
    #compdef noir

    _noir() {
      local -a commands subjects shells cache_actions config_actions rules_actions

      commands=(
        'scan:Discover endpoints in one or more codebases'
        'list:List built-in catalogs (techs, taggers, formats)'
        'cache:Manage the LLM response cache (info, clear, purge)'
        'config:Manage the user-level config (show, init, path)'
        'rules:Manage passive-scan rules (list, update, path)'
        'completion:Generate shell completion script (zsh, bash, fish, elvish)'
        'version:Print the noir version (--verbose for build info)'
        'help:Show help for a command'
      )
      subjects=(techs taggers formats)
      shells=(zsh bash fish elvish)
      cache_actions=(info clear purge)
      config_actions=(show edit init path)
      rules_actions=(list update path)

      if (( CURRENT == 2 )); then
        _describe -t commands 'noir command' commands
        _files
        return
      fi

      case "${words[2]}" in
        list)
          if (( CURRENT == 3 )); then
            _describe -t subjects 'subject' subjects
          fi
          return
          ;;
        cache)
          if (( CURRENT == 3 )); then
            _describe -t cache_actions 'action' cache_actions
          fi
          return
          ;;
        config)
          if (( CURRENT == 3 )); then
            _describe -t config_actions 'action' config_actions
          fi
          return
          ;;
        rules)
          if (( CURRENT == 3 )); then
            _describe -t rules_actions 'action' rules_actions
          fi
          return
          ;;
        completion)
          if (( CURRENT == 3 )); then
            _describe -t shells 'shell' shells
          fi
          return
          ;;
        version)
          return
          ;;
        help)
          if (( CURRENT == 3 )); then
            _describe -t commands 'noir command' commands
          fi
          return
          ;;
        scan|*)
          _arguments \\
            '(-b --base-path)'{-b,--base-path}'[Set base path]:path:_files' \\
            '(-u --url)'{-u,--url}'[Set base URL for endpoints]:URL:_urls' \\
            '(-f --format)'{-f,--format}'[Output format]:format:(#{FORMATS})' \\
            '(-o --output)'{-o,--output}'[Write result to file]:path:_files' \\
            '--pvalue[Set parameter value TYPE=VAL]:value:' \\
            '--set-pvalue[Set pvalue (any)]:value:' \\
            '--set-pvalue-header[Set pvalue (header)]:value:' \\
            '--set-pvalue-cookie[Set pvalue (cookie)]:value:' \\
            '--set-pvalue-query[Set pvalue (query)]:value:' \\
            '--set-pvalue-form[Set pvalue (form)]:value:' \\
            '--set-pvalue-json[Set pvalue (json)]:value:' \\
            '--set-pvalue-path[Set pvalue (path)]:value:' \\
            '--status-codes[Display HTTP status codes]' \\
            '--exclude-codes[Exclude HTTP codes (comma-separated)]:codes:' \\
            '--include[Enrich plain output (path,techs,callee)]:list:(path techs callee path,techs path,techs,callee)' \\
            '--include-path[Include source path column (legacy)]' \\
            '--include-techs[Include techs column (legacy)]' \\
            '--include-callee[Include callee column (legacy)]' \\
            '--ai-context[Include AI review context (guards,sinks,...)]::list:(guards sinks validators signals callee)' \\
            '--exclude-path[Exclude files by glob]:pattern:' \\
            '--no-color[Disable color output]' \\
            '--no-spinner[Disable loading spinner animations]' \\
            '--no-log[Show only results]' \\
            '(-P --passive-scan)'{-P,--passive-scan}'[Enable passive security scan]' \\
            '--passive-scan-path[Custom passive rules path]:path:_files' \\
            '--passive-scan-severity[Min severity]:severity:(critical high medium low)' \\
            '--passive-scan-auto-update[Auto-update rules at startup]' \\
            '--passive-scan-no-update-check[Skip rule update check]' \\
            '(-T --use-all-taggers)'{-T,--use-all-taggers}'[Activate all taggers]' \\
            '--use-taggers[Activate specific taggers]:list:' \\
            '--probe[Fire HTTP requests at endpoints]' \\
            '--probe-via[Route probes through proxy]:url:' \\
            '--probe-header[Header per probe]:value:' \\
            '--probe-match[Only probe matching endpoints]:value:' \\
            '--probe-skip[Skip matching endpoints]:value:' \\
            '--export-es[Index endpoints in Elasticsearch]:url:' \\
            '--export-opensearch[Index endpoints in OpenSearch]:url:' \\
            '--export-webhook[POST endpoint catalog as JSON]:url:' \\
            '--ai-provider[AI provider prefix or URL]:provider:' \\
            '--ai-model[AI model name]:model:' \\
            '--ai-key[AI API key]:key:' \\
            '--ai-agent[Enable agentic AI workflow]' \\
            '--ai-agent-max-steps[Max steps for AI agent loop]:n:' \\
            '--ai-native-tools-allowlist[Provider allowlist for native tool-calling]:list:' \\
            '--ai-max-token[Max tokens per request]:n:' \\
            '--diff-path[Old code version for diff]:path:_files' \\
            '(-t --techs)'{-t,--techs}'[Specify technologies]:techs:' \\
            '--exclude-techs[Exclude technologies]:techs:' \\
            '--only-techs[Only run these tech detectors]:techs:' \\
            '--config-file[YAML config file]:path:_files' \\
            '--concurrency[Concurrency level]:level:' \\
            '--cache-disable[Disable LLM cache for this run]' \\
            '--cache-clear[Clear LLM cache before scan]' \\
            '(-d --debug)'{-d,--debug}'[Enable debug messages]' \\
            '--verbose[Verbose mode]' \\
            '(-v --version)'{-v,--version}'[Show version]' \\
            '(-h --help)'{-h,--help}'[Show help]'
          return
          ;;
      esac
    }

    compdef _noir noir
    SCRIPT
end

def generate_bash_completion_script
  scan_flags = SCAN_FLAGS.join(" ")
  <<-SCRIPT
    _noir_completions() {
      local cur prev cmd opts
      COMPREPLY=()
      cur="${COMP_WORDS[COMP_CWORD]}"
      prev="${COMP_WORDS[COMP_CWORD-1]}"
      cmd="${COMP_WORDS[1]}"

      local commands="scan list cache config rules completion version help"

      if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
        if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
          COMPREPLY=( $(compgen -f -- "${cur}") )
        fi
        return 0
      fi

      case "${cmd}" in
        list)
          if [[ ${COMP_CWORD} -eq 2 ]]; then
            COMPREPLY=( $(compgen -W "techs taggers formats" -- "${cur}") )
            return 0
          fi
          ;;
        cache)
          if [[ ${COMP_CWORD} -eq 2 ]]; then
            COMPREPLY=( $(compgen -W "info clear purge" -- "${cur}") )
            return 0
          fi
          ;;
        config)
          if [[ ${COMP_CWORD} -eq 2 ]]; then
            COMPREPLY=( $(compgen -W "show edit init path" -- "${cur}") )
            return 0
          fi
          ;;
        rules)
          if [[ ${COMP_CWORD} -eq 2 ]]; then
            COMPREPLY=( $(compgen -W "list update path" -- "${cur}") )
            return 0
          fi
          ;;
        completion)
          if [[ ${COMP_CWORD} -eq 2 ]]; then
            COMPREPLY=( $(compgen -W "zsh bash fish elvish" -- "${cur}") )
            return 0
          fi
          ;;
        version)
          return 0
          ;;
        help)
          if [[ ${COMP_CWORD} -eq 2 ]]; then
            COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
          fi
          return 0
          ;;
      esac

      # scan flags (also covers bare `noir -b ...` v0 invocation since the
      # router default-routes to scan)
      local opts="
        #{scan_flags}
      "

      case "${prev}" in
        -f|--format)
          COMPREPLY=( $(compgen -W "#{FORMATS}" -- "${cur}") )
          return 0
          ;;
        --include)
          COMPREPLY=( $(compgen -W "path techs callee path,techs path,techs,callee" -- "${cur}") )
          return 0
          ;;
        --ai-context)
          COMPREPLY=( $(compgen -W "guards sinks validators signals callee" -- "${cur}") )
          return 0
          ;;
        --passive-scan-severity)
          COMPREPLY=( $(compgen -W "critical high medium low" -- "${cur}") )
          return 0
          ;;
        -b|--base-path|-u|--url|-o|--output|--diff-path|--config-file|--passive-scan-path|--probe-via|--export-es|--export-opensearch|--export-webhook)
          COMPREPLY=( $(compgen -f -- "${cur}") )
          return 0
          ;;
        --probe-header|--probe-match|--probe-skip|--use-taggers|--pvalue|--set-pvalue|--set-pvalue-header|--set-pvalue-cookie|--set-pvalue-query|--set-pvalue-form|--set-pvalue-json|--set-pvalue-path|-t|--techs|--exclude-techs|--only-techs|--exclude-codes|--exclude-path|--ai-provider|--ai-model|--ai-key|--ai-agent-max-steps|--ai-native-tools-allowlist|--ai-max-token|--concurrency)
          # value flags — no useful completion, just let the user type
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
    function __fish_noir_using_command
        set -l cmd (commandline -opc)
        if test (count $cmd) -ge 2
            if test "$cmd[2]" = $argv[1]
                return 0
            end
        end
        return 1
    end

    function __fish_noir_needs_command
        set -l cmd (commandline -opc)
        if test (count $cmd) -eq 1
            return 0
        end
        return 1
    end

    # Top-level subcommands
    complete -c noir -f -n '__fish_noir_needs_command' -a scan       -d 'Discover endpoints'
    complete -c noir -f -n '__fish_noir_needs_command' -a list       -d 'List built-in catalogs'
    complete -c noir -f -n '__fish_noir_needs_command' -a cache      -d 'Manage LLM cache'
    complete -c noir -f -n '__fish_noir_needs_command' -a config     -d 'Manage user config'
    complete -c noir -f -n '__fish_noir_needs_command' -a rules      -d 'Manage passive rules'
    complete -c noir -f -n '__fish_noir_needs_command' -a completion -d 'Generate shell completion'
    complete -c noir -f -n '__fish_noir_needs_command' -a version    -d 'Print noir version'
    complete -c noir -f -n '__fish_noir_needs_command' -a help       -d 'Show help'

    # Sub-actions per command
    complete -c noir -f -n '__fish_noir_using_command list' -a 'techs taggers formats'
    complete -c noir -f -n '__fish_noir_using_command cache' -a 'info clear purge'
    complete -c noir -f -n '__fish_noir_using_command config' -a 'show edit init path'
    complete -c noir -f -n '__fish_noir_using_command rules' -a 'list update path'
    complete -c noir -f -n '__fish_noir_using_command completion' -a 'zsh bash fish elvish'

    # Scan-time flags (also valid under bare `noir` for v0 compat)
    complete -c noir -s b -l base-path             -d 'Set base path' -r -F
    complete -c noir -s u -l url                   -d 'Set base URL' -r
    complete -c noir -s f -l format                -d 'Output format' -r -a 'plain yaml json jsonl toml markdown-table sarif html curl httpie powershell adb simctl oas2 oas3 postman only-url only-param only-header only-cookie only-tag mermaid'
    complete -c noir -s o -l output                -d 'Write result to file' -r -F
    complete -c noir      -l pvalue                -d 'Set param value TYPE=VAL' -r
    complete -c noir      -l set-pvalue            -d 'Set pvalue (any)'    -r
    complete -c noir      -l set-pvalue-header     -d 'Set pvalue (header)' -r
    complete -c noir      -l set-pvalue-cookie     -d 'Set pvalue (cookie)' -r
    complete -c noir      -l set-pvalue-query      -d 'Set pvalue (query)'  -r
    complete -c noir      -l set-pvalue-form       -d 'Set pvalue (form)'   -r
    complete -c noir      -l set-pvalue-json       -d 'Set pvalue (json)'   -r
    complete -c noir      -l set-pvalue-path       -d 'Set pvalue (path)'   -r
    complete -c noir      -l status-codes          -d 'Display HTTP status codes'
    complete -c noir      -l exclude-codes         -d 'Exclude HTTP codes' -r
    complete -c noir      -l exclude-path          -d 'Exclude files by glob' -r
    complete -c noir      -l include               -d 'Enrich plain output (path,techs,callee)' -r -a 'path techs callee path,techs path,techs,callee'
    complete -c noir      -l include-path          -d 'Include source path in plain output (legacy)'
    complete -c noir      -l include-techs         -d 'Include techs column in plain output (legacy)'
    complete -c noir      -l include-callee        -d 'Include callee column in plain output (legacy)'
    complete -c noir      -l ai-context            -d 'Include AI review context' -a 'guards sinks validators signals callee'
    complete -c noir      -l ai-agent              -d 'Enable agentic AI workflow'
    complete -c noir      -l ai-agent-max-steps    -d 'Max steps for AI agent loop' -r
    complete -c noir      -l ai-native-tools-allowlist -d 'Provider allowlist for native tool-calling' -r
    complete -c noir      -l ai-max-token          -d 'Max tokens per request' -r
    complete -c noir      -l no-color              -d 'Disable color output'
    complete -c noir      -l no-spinner            -d 'Disable loading spinner animations'
    complete -c noir      -l no-log                -d 'Show only results'
    complete -c noir -s P -l passive-scan          -d 'Enable passive scan'
    complete -c noir      -l passive-scan-path           -d 'Custom passive rules path' -r -F
    complete -c noir      -l passive-scan-severity       -d 'Min severity' -r -a 'critical high medium low'
    complete -c noir      -l passive-scan-auto-update    -d 'Auto-update rules at startup'
    complete -c noir      -l passive-scan-no-update-check -d 'Skip rule update check'
    complete -c noir -s T -l use-all-taggers       -d 'Activate all taggers'
    complete -c noir      -l use-taggers           -d 'Activate specific taggers' -r
    complete -c noir      -l probe                 -d 'Fire HTTP requests at endpoints'
    complete -c noir      -l probe-via             -d 'Route probes through proxy' -r
    complete -c noir      -l probe-header          -d 'Header per probe' -r
    complete -c noir      -l probe-match           -d 'Only probe matching endpoints' -r
    complete -c noir      -l probe-skip            -d 'Skip matching endpoints' -r
    complete -c noir      -l export-es             -d 'Index endpoints in Elasticsearch' -r
    complete -c noir      -l export-opensearch     -d 'Index endpoints in OpenSearch' -r
    complete -c noir      -l export-webhook        -d 'POST endpoint catalog as JSON' -r
    complete -c noir      -l ai-provider           -d 'AI provider prefix or URL' -r
    complete -c noir      -l ai-model              -d 'AI model name' -r
    complete -c noir      -l ai-key                -d 'AI API key' -r
    complete -c noir      -l diff-path             -d 'Old code version for diff' -r -F
    complete -c noir -s t -l techs                 -d 'Specify technologies' -r
    complete -c noir      -l exclude-techs         -d 'Exclude technologies' -r
    complete -c noir      -l only-techs            -d 'Only these tech detectors' -r
    complete -c noir      -l config-file           -d 'YAML config file' -r -F
    complete -c noir      -l concurrency           -d 'Concurrency level' -r
    complete -c noir      -l cache-disable         -d 'Disable LLM cache for this run'
    complete -c noir      -l cache-clear           -d 'Clear LLM cache before scan'
    complete -c noir -s d -l debug                 -d 'Enable debug messages'
    complete -c noir      -l verbose               -d 'Verbose mode'
    complete -c noir -s v -l version               -d 'Show version'
    complete -c noir -s h -l help                  -d 'Show help'
    SCRIPT
end

# Native Elvish (https://elv.sh) completion. Wires the noir verb
# surface into `$edit:completion:arg-completer` so `noir <Tab>` lists
# the subcommands, `noir <verb> <Tab>` lists that verb's sub-actions,
# and `noir scan <Tab>` falls back to filesystem path completion.
#
# Install:
#   noir completion elvish > ~/.config/elvish/lib/noir.elv
# then add `use noir` to ~/.config/elvish/rc.elv.
def generate_elvish_completion_script
  <<-SCRIPT
    # Noir v1 — Elvish tab-completion
    #
    # Save this file to ~/.config/elvish/lib/noir.elv and add
    #   use noir
    # to your ~/.config/elvish/rc.elv.

    use str

    var commands       = [scan list cache config rules completion version help]
    var list-subjects  = [techs taggers formats]
    var cache-actions  = [info clear purge]
    var config-actions = [show edit init path]
    var rules-actions  = [list update path]
    var shells         = [zsh bash fish elvish]
    var scan-flags = [
      -b --base-path -u --url -f --format -o --output
      --pvalue --set-pvalue
      --set-pvalue-header --set-pvalue-cookie --set-pvalue-query
      --set-pvalue-form --set-pvalue-json --set-pvalue-path
      --status-codes --exclude-codes --exclude-path
      --include --include-path --include-techs --include-callee
      --ai-context --no-color --no-spinner --no-log
      -P --passive-scan --passive-scan-path --passive-scan-severity
      --passive-scan-auto-update --passive-scan-no-update-check
      -T --use-all-taggers --use-taggers
      --probe --probe-via --probe-header --probe-match --probe-skip
      --export-es --export-opensearch --export-webhook
      --ai-provider --ai-model --ai-key --ai-agent --ai-agent-max-steps
      --ai-native-tools-allowlist --ai-max-token
      --diff-path -t --techs --exclude-techs --only-techs
      --config-file --concurrency
      --cache-disable --cache-clear
      -d --debug --verbose
      -v --version -h --help
    ]

    set edit:completion:arg-completer[noir] = {|@cmd|
      var n = (count $cmd)
      var last = $cmd[-1]
      if (== $n 2) {
        put $@commands
      } else {
        var verb = $cmd[1]
        # v0 compat: a leading flag (e.g. `noir -b ./path`) means the
        # whole invocation is an implicit `scan`, so treat it that way.
        if (or (eq $verb scan) (str:has-prefix $verb -)) {
          if (str:has-prefix $last -) {
            put $@scan-flags
          } else {
            edit:complete-filename $last
          }
        } elif (== $n 3) {
          if (eq $verb list) {
            put $@list-subjects
          } elif (eq $verb cache) {
            put $@cache-actions
          } elif (eq $verb config) {
            put $@config-actions
          } elif (eq $verb rules) {
            put $@rules-actions
          } elif (eq $verb completion) {
            put $@shells
          } elif (eq $verb help) {
            put $@commands
          }
        }
      }
    }
    SCRIPT
end
