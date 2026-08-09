require "../cli/catalog"
require "../cli/scan_flags"

module Noir::Completions::Bash
  extend self

  def script : String
    <<-SCRIPT
      _noir_completions() {
        local cur prev cmd opts
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        cmd="${COMP_WORDS[1]}"

        local commands="#{Noir::CLI::Catalog::NAMES.join(" ")}"

        if [[ ${COMP_CWORD} -eq 1 ]]; then
          COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
          if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
            COMPREPLY=( $(compgen -f -- "${cur}") )
          fi
          return 0
        fi

        case "${cmd}" in
      #{subcommand_branches}
        esac

        # scan flags (also covers bare `noir -b ...` v0 invocation since the
        # router default-routes to scan)
        local opts="
          #{Noir::CLI::ScanFlags::NAMES.join(" ")}
        "

        # `--flag=value` form: bash treats '=' as a word break (default
        # COMP_WORDBREAKS), so the value is $cur and '=' is $prev. Look one
        # token further back for the flag to complete its enum values.
        if [[ ${prev} == "=" ]]; then
          case "${COMP_WORDS[COMP_CWORD-2]}" in
      #{choice_branches("      ")}
          esac
        fi

        case "${prev}" in
      #{choice_branches("    ")}
          #{Noir::CLI::ScanFlags.path_like.flat_map(&.names).join("|")})
            COMPREPLY=( $(compgen -f -- "${cur}") )
            return 0
            ;;
          #{Noir::CLI::ScanFlags.opaque_value.flat_map(&.names).join("|")})
            # value flags — no useful completion, just let the user type
            return 0
            ;;
          *)
            ;;
        esac

        # A leading '-' means the user is typing a flag; otherwise fall back
        # to filesystem completion so `noir scan <path>` completes base paths.
        if [[ ${cur} == -* ]]; then
          COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
        else
          COMPREPLY=( $(compgen -f -- "${cur}") )
        fi
        return 0
      }

      complete -F _noir_completions noir
      SCRIPT
  end

  # Each subcommand branch returns unconditionally, so `noir cache clear
  # <TAB>` can never fall through to the scan-flag block below.
  private def subcommand_branches : String
    Noir::CLI::Catalog.completable.map do |(name, values)|
      # `noir help <cmd>` completes the verb list, which the function
      # already holds in `$commands`.
      words = name == "help" ? "${commands}" : values.join(" ")

      body = if values.empty?
               ""
             else
               "      if [[ ${COMP_CWORD} -eq 2 ]]; then\n" \
               "        COMPREPLY=( $(compgen -W \"#{words}\" -- \"${cur}\") )\n" \
               "      fi\n"
             end

      "    #{name})\n#{body}      return 0\n      ;;"
    end.join("\n")
  end

  # The enum-valued flags, rendered once for the `--flag value` form and
  # again for `--flag=value` (which bash splits at the `=`).
  private def choice_branches(indent : String) : String
    Noir::CLI::ScanFlags.with_choices.map do |flag|
      "#{indent}#{flag.names.join("|")})\n" \
      "#{indent}  COMPREPLY=( $(compgen -W \"#{flag.choice_list}\" -- \"${cur}\") )\n" \
      "#{indent}  return 0\n" \
      "#{indent}  ;;"
    end.join("\n")
  end
end

def generate_bash_completion_script
  Noir::Completions::Bash.script
end
