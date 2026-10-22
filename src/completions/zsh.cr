require "../cli/catalog"
require "../cli/scan_flags"
require "./shell"

module Noir::Completions::Zsh
  extend self

  alias Arg = Noir::CLI::ScanFlags::Arg

  def script : String
    <<-SCRIPT
      #compdef noir

      _noir() {
        local -a commands #{word_arrays.join(" ")}

        commands=(
      #{command_descriptions}
        )
      #{word_assignments}

        if (( CURRENT == 2 )); then
          _describe -t commands 'noir command' commands
          _files
          return
        fi

        case "${words[2]}" in
      #{subcommand_branches}
          scan|*)
            _arguments \\
      #{argument_specs} \\
              '*:path:_files'
            return
            ;;
        esac
      }

      compdef _noir noir
      SCRIPT
  end

  # `list_words`, `cache_words`, … — one array per verb with a fixed
  # vocabulary. `help` reuses `commands`, so it gets no array of its own.
  private def word_arrays : Array(String)
    Noir::CLI::Catalog.completable
      .select { |(name, values)| !values.empty? && name != "help" }
      .map { |(name, _)| "#{name}_words" }
  end

  private def command_descriptions : String
    Noir::CLI::Catalog::COMMANDS.map do |command|
      "    #{Noir::Completions.quote("#{command.name}:#{command.summary}")}"
    end.join("\n")
  end

  private def word_assignments : String
    Noir::CLI::Catalog.completable
      .select { |(name, values)| !values.empty? && name != "help" }
      .map { |(name, values)| "  #{name}_words=(#{values.join(" ")})" }
      .join("\n")
  end

  private def subcommand_branches : String
    Noir::CLI::Catalog.completable.map do |(name, values)|
      body = if values.empty?
               ""
             elsif name == "help"
               # `noir help <cmd>` completes the verb list, descriptions and
               # all, so it reuses the `commands` array built above.
               "      if (( CURRENT == 3 )); then\n" \
               "        _describe -t commands 'noir command' commands\n" \
               "      fi\n"
             else
               "      if (( CURRENT == 3 )); then\n" \
               "        _describe -t values '#{name}' #{name}_words\n" \
               "      fi\n"
             end

      "    #{name})\n#{body}      return\n      ;;"
    end.join("\n")
  end

  private def argument_specs : String
    Noir::CLI::ScanFlags::FLAGS.map { |flag| "        #{argument_spec(flag)} \\" }
      .join("\n")
      .rchop(" \\")
  end

  # zsh spec form. A flag with short forms declares them as mutually
  # exclusive with the long one — `'(-b --base-path)'{-b,--base-path}'[…]'`
  # — so zsh stops offering the alias once either is on the line.
  private def argument_spec(flag : Noir::CLI::ScanFlags::Flag) : String
    body = "[#{flag.description}]#{value_spec(flag)}"

    if flag.shorts.empty?
      Noir::Completions.quote("#{flag.long}#{body}")
    else
      names = flag.names
      "#{Noir::Completions.quote("(#{names.join(" ")})")}{#{names.join(",")}}#{Noir::Completions.quote(body)}"
    end
  end

  # A doubled colon marks an optional value — what `--ai-context` with no
  # argument relies on.
  private def value_spec(flag : Noir::CLI::ScanFlags::Flag) : String
    case flag.arg
    in Arg::None           then ""
    in Arg::Value          then ":#{flag.hint}:"
    in Arg::File           then ":#{flag.hint}:_files"
    in Arg::Url            then ":#{flag.hint}:_urls"
    in Arg::Choice         then ":#{flag.hint}:(#{flag.choice_list})"
    in Arg::OptionalChoice then "::#{flag.hint}:(#{flag.choice_list})"
    end
  end
end
