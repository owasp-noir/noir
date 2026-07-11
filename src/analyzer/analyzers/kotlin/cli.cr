require "../../../models/analyzer"
require "../../engines/kotlin_engine"

module Analyzer::Kotlin
  # Surfaces the command-line attack surface of Kotlin programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers clikt, kotlinx-cli and picocli
  # plus gated System.getenv reads.
  #
  # Line-scan analyzer (Go/Ruby/Rust CLI house style) merging endpoints by
  # URL. Subclasses Analyzer directly (KotlinEngine is a module) and uses
  # KotlinEngine.test_path? to skip tests.
  class Cli < Analyzer
    # clikt: `class Serve : CliktCommand(name = "serve")` (name optional →
    # class name lower-cased).
    CLIKT_CLASS  = /\bclass\s+(\w+)\s*(?:\([^)]*\))?\s*:\s*[^{]*\bCliktCommand\b/
    CLIKT_NAME   = /CliktCommand\s*\([^)]*\bname\s*=\s*"([^"]+)"/
    CLIKT_OPTION = /\bval\s+(\w+)\s+by\s+option\s*\(([^)]*)\)/
    CLIKT_ARG    = /\bval\s+(\w+)\s+by\s+argument\s*\(/
    CLIKT_ENVVAR = /\benvvar\s*=\s*"([^"]+)"/

    # kotlinx-cli.
    ARGPARSER   = /\bArgParser\s*\(\s*"([^"]+)"/
    KX_OPTION   = /\bby\s+\w*\.?option\s*\(\s*ArgType\.\w+\s*,\s*"([^"]+)"/
    KX_ARGUMENT = /\bby\s+\w*\.?argument\s*\(\s*ArgType\.\w+\s*,\s*"([^"]+)"/

    # picocli: annotations sit on the line above the class/property they
    # decorate (`@Command(name = "serve")` \n `class Serve : Callable<Int>`),
    # so a one-line lookahead resolves each pending annotation.
    # A `@Command(` may wrap across lines once `description`/`subcommands` are
    # added, so the annotation start is matched with a bounded body-join
    # instead of requiring the close paren on the same line.
    PICOCLI_COMMAND_START = /@Command\s*\(/
    PICOCLI_NAME          = /\bname\s*=\s*"([^"]+)"/
    PICOCLI_CLASS         = /\bclass\s+(\w+)\b/
    PICOCLI_OPTION        = /@Option\s*\(([^)]*)\)/
    PICOCLI_PARAMS        = /@Parameters\b/
    PICOCLI_PROPERTY      = /\b(?:var|val)\s+(\w+)\s*:/

    GET_ENV = /\bSystem\.getenv\s*\(\s*"([^"]+)"\s*\)/

    LIB_MARKERS      = ["com.github.ajalt.clikt", "kotlinx.cli", "picocli.CommandLine"]
    WEB_FRAMEWORK_RE = /\bimport\s+(?:org\.springframework|io\.ktor|org\.http4k)/

    def analyze
      endpoints = {} of String => Endpoint

      get_files_by_extension(".kt").each do |path|
        next if File.directory?(path)
        next if KotlinEngine.test_path?(path)
        next unless File.exists?(path)

        begin
          content = read_file_content(path)
          next unless LIB_MARKERS.any? { |m| content.includes?(m) } || content.matches?(/:\s*CliktCommand\b|\bArgParser\s*\(/)

          binary = kotlin_binary_name(content, path)
          root_url = "cli://#{binary}"
          emit_env = !content.matches?(WEB_FRAMEWORK_RE)
          scan(content.lines, path, binary, root_url, endpoints, emit_env)
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end

      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def kotlin_binary_name(content : String, path : String) : String
      if m = content.match(ARGPARSER)
        return m[1]
      end
      File.basename(path, ".kt")
    end

    private def scan(lines : Array(String), path : String, binary : String,
                     root_url : String, endpoints : Hash(String, Endpoint), emit_env : Bool)
      current_url = root_url

      # picocli pending-annotation state: annotations decorate the class or
      # property declared on the *next* line, so each is resolved with a
      # single-line lookahead (never a sticky cursor across commands).
      awaiting_picocli_command = false
      pending_picocli_command_name = nil.as(String?)
      picocli_command_wait = 0
      awaiting_picocli_flag = false
      pending_picocli_flag_name = nil.as(String?)
      awaiting_picocli_positional = false

      lines.each_with_index do |line, index|
        line_no = index + 1

        # Resolve any picocli annotation pending from the previous line(s). A
        # wrapped `@Command(...)` puts its class several lines below its
        # annotation, so wait (bounded) for the next class rather than
        # clearing after a single line — while staying bounded so flags never
        # leak onto a stale command if no class ever follows.
        if awaiting_picocli_command
          if m = line.match(PICOCLI_CLASS)
            name = pending_picocli_command_name || m[1].downcase
            current_url = name == binary ? root_url : "#{root_url}/#{name}"
            fetch_endpoint(endpoints, current_url, path, line_no)
            awaiting_picocli_command = false
            pending_picocli_command_name = nil
          else
            picocli_command_wait += 1
            awaiting_picocli_command = false if picocli_command_wait > 8
          end
        end

        if awaiting_picocli_flag
          if m = line.match(PICOCLI_PROPERTY)
            name = pending_picocli_flag_name || camel_to_kebab(m[1])
            fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(name, "", "flag"))
          end
          awaiting_picocli_flag = false
        end

        if awaiting_picocli_positional
          if m = line.match(PICOCLI_PROPERTY)
            fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(camel_to_kebab(m[1]), "", "argument"))
          end
          awaiting_picocli_positional = false
        end

        # clikt command class: name= or the class name lower-cased; the class
        # whose name matches the binary is the root.
        if m = line.match(CLIKT_CLASS)
          name = line.match(CLIKT_NAME).try(&.[1]) || m[1].downcase
          current_url = name == binary ? root_url : "#{root_url}/#{name}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end

        if m = line.match(CLIKT_OPTION)
          ep = fetch_endpoint(endpoints, current_url, path, line_no)
          name = option_long(m[2]) || camel_to_kebab(m[1])
          ep.push_param(Param.new(name, "", "flag"))
          # `option(..., envvar = "X")` also reads the environment; the env
          # binding belongs to the option's command, not the file's root.
          # Scan the whole line, not the `([^)]*)` option body: a `)` inside
          # an earlier help string (`help = "path (see docs)"`) truncates
          # that capture before the trailing `envvar =` is reached.
          if env = line.match(CLIKT_ENVVAR)
            ep.push_param(Param.new(env[1], "", "env"))
          end
        end
        if m = line.match(CLIKT_ARG)
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(camel_to_kebab(m[1]), "", "argument"))
        end

        # kotlinx-cli (flags/args on root).
        if m = line.match(KX_OPTION)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
        end
        if m = line.match(KX_ARGUMENT)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "argument"))
        end

        # picocli: queue the annotation so it resolves against the class/
        # property it decorates. The name= is read from the (possibly
        # multi-line) annotation body; the property may sit inline on the same
        # line or on the next one.
        if line.matches?(PICOCLI_COMMAND_START)
          body = picocli_join_body(lines, index)
          pending_picocli_command_name = body.match(PICOCLI_NAME).try(&.[1])
          awaiting_picocli_command = true
          picocli_command_wait = 0
        end
        if m = line.match(PICOCLI_OPTION)
          long = option_long(m[1])
          if pm = line[m.end..].match(PICOCLI_PROPERTY)
            fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(long || camel_to_kebab(pm[1]), "", "flag"))
          else
            pending_picocli_flag_name = long
            awaiting_picocli_flag = true
          end
        end
        if m = line.match(PICOCLI_PARAMS)
          if pm = line[m.end..].match(PICOCLI_PROPERTY)
            fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(camel_to_kebab(pm[1]), "", "argument"))
          else
            awaiting_picocli_positional = true
          end
        end

        if emit_env
          line.scan(GET_ENV) do |env_match|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(env_match[1], "", "env"))
          end
        end
      end
    end

    # Joins a picocli annotation body starting at the `(` on `lines[start]`
    # through the matching `)`, so a `@Command(` whose `name = "..."` wraps
    # onto a later line is still captured. Bounded to a few lines.
    private def picocli_join_body(lines : Array(String), start : Int32) : String
      text = String::Builder.new
      depth = 0
      started = false
      li = start
      while li < lines.size && li - start <= 10
        lines[li].each_char do |ch|
          if ch == '('
            depth += 1
            started = true
          elsif ch == ')'
            depth -= 1
            return text.to_s if started && depth == 0
          else
            text << ch if started && depth >= 1
          end
        end
        text << ' '
        li += 1
      end
      text.to_s
    end

    # clikt `option("-v", "--verbose")` → prefer the long name; nil when the
    # option declares no explicit names (caller falls back to the property).
    private def option_long(body : String) : String?
      tokens = [] of String
      body.scan(/"(--?[A-Za-z0-9][\w-]*)"/) { |m| tokens << m[1] }
      return if tokens.empty?
      (tokens.find(&.starts_with?("--")) || tokens.first).lstrip('-')
    end

    private def camel_to_kebab(name : String) : String
      result = String::Builder.new
      name.each_char_with_index do |ch, i|
        result << '-' if ch.uppercase? && i > 0
        result << ch.downcase
      end
      result.to_s
    end

    private def fetch_endpoint(endpoints : Hash(String, Endpoint), url : String,
                               path : String, line_no : Int32) : Endpoint
      endpoints[url] ||= begin
        ep = Endpoint.new(url, "CLI", Details.new(PathInfo.new(path, line_no)))
        ep.protocol = "cli"
        ep
      end
    end
  end
end
