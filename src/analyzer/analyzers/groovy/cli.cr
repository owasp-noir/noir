require "../../../models/analyzer"

module Analyzer::Groovy
  # Surfaces the command-line attack surface of Groovy programs as `cli://`
  # endpoints: the built-in CliBuilder (and picocli @Option), JCommander
  # (@Parameter / addCommand subcommands) and Commons CLI (Option.builder /
  # addOption), plus System.getenv. Line-scan; attribution for JCommander
  # subcommands additionally uses a per-file pre-scan (variable -> class ->
  # command name) so it can resolve both the inline
  # `addCommand("name", new Class())` form and the more common
  # declare-then-register `addCommand("name", instance)` form. Root
  # attribution otherwise (CliBuilder/Commons CLI are flat), merged by URL.
  #
  # NOTE: like CliBuilder, this is a per-file analyzer. When a JCommander
  # subcommand class lives in its own file (registration call in one file,
  # `@Parameter` fields in another), the class-to-command mapping built here
  # won't span files, so that subcommand's fields fall back to that file's
  # own root endpoint instead of being attributed under the real
  # subcommand's URL. A cross-file pre-pass would be needed to close that
  # gap; not attempted here.
  class Cli < Analyzer
    CLI_OPT     = /\bcli\.([A-Za-z_]\w*)\s*\(([^)]*)/
    LONGOPT     = /longOpt:\s*['"]([^'"]+)['"]/
    OPTION_ATTR = /@Option\s*\(([^)]*)\)/
    GET_ENV     = /\bSystem\.getenv\s*\(\s*['"]([^'"]+)['"]/

    # CliBuilder methods that are not option definitions.
    NON_OPTION = Set{"parse", "usage", "with", "width", "header", "footer",
                     "stopAtNonOption", "expandArgumentFiles", "posix",
                     "errorWriter", "writer", "name"}

    MARKERS = /\bnew\s+CliBuilder\b|\bCliBuilder\s*\(|@picocli|@Command\b/
    WEB_RE  = /\bimport\s+(?:grails|org\.springframework)\b|@Controller\b|@RestController\b/

    # --- JCommander -----------------------------------------------------
    # Gated on library-specific constructs only (never a bare `@Parameter`,
    # which is too generic on its own) so unrelated annotations/classes
    # named similarly don't light this up.
    JC_MARKER      = /\bimport\s+com\.beust\.jcommander\b|\bnew\s+JCommander\s*\(|\bJCommander\.newBuilder\s*\(/
    JC_PARAMETER   = /@Parameter\s*\(([^)]*)\)/
    CLASS_DECL     = /\bclass\s+([A-Za-z_]\w*)/
    VAR_NEW_DECL   = /\b[A-Za-z_]\w*\s+([A-Za-z_]\w*)\s*=\s*new\s+([A-Za-z_]\w*)\s*\(/
    JC_ADD_CMD_STR   = /\.addCommand\s*\(\s*['"]([^'"]+)['"]\s*,\s*new\s+([A-Za-z_]\w*)\s*\(/
    JC_ADD_CMD_VAR   = /\.addCommand\s*\(\s*['"]([^'"]+)['"]\s*,\s*([A-Za-z_]\w*)\s*\)/
    JC_COMMAND_NAMES = /@Parameters\s*\([^)]*\bcommandNames\s*=\s*\{?\s*['"]([^'"]+)['"]/

    # --- Commons CLI ------------------------------------------------------
    CLI_MARKER          = /\bimport\s+org\.apache\.commons\.cli\b|\bOption\.builder\s*\(/
    COMMONS_CLI_BUILDER = /Option\.builder\s*\(\s*(?:['"]([^'"]*)['"])?\s*\)/
    COMMONS_CLI_LONGOPT = /\.longOpt\s*\(\s*['"]([^'"]+)['"]/
    COMMONS_CLI_ADD_OPT = /\.addOption\s*\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]\s*,/

    def analyze
      endpoints = {} of String => Endpoint
      get_files_by_extension(".groovy").each do |path|
        next if File.directory?(path)
        next if cli_test_path?(path)
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          has_clibuilder = content.matches?(MARKERS)
          has_jcommander = content.matches?(JC_MARKER)
          has_commonscli = content.matches?(CLI_MARKER)
          next unless has_clibuilder || has_jcommander || has_commonscli

          root_url = "cli://#{cli_binary_name(path)}"
          emit_env = !content.matches?(WEB_RE)
          subcommand_for_class = has_jcommander ? build_subcommand_map(content) : Hash(String, String).new

          class_stack = [] of NamedTuple(name: String, depth: Int32)
          depth = 0

          content.each_line.with_index do |line, index|
            line_no = index + 1

            if has_jcommander
              if m = line.match(CLASS_DECL)
                class_stack << {name: m[1], depth: depth}
              end
              depth += line.count('{') - line.count('}')
              while !class_stack.empty? && depth <= class_stack.last[:depth]
                class_stack.pop
              end
            end

            if has_clibuilder
              if m = line.match(CLI_OPT)
                unless NON_OPTION.includes?(m[1])
                  name = line.match(LONGOPT).try(&.[1]) || m[1]
                  fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", "flag"))
                end
              end
              if m = line.match(OPTION_ATTR)
                if name = picocli_name(m[1])
                  fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", "flag"))
                end
              end
            end

            if has_jcommander
              if m = line.match(JC_PARAMETER)
                if name = picocli_name(m[1])
                  klass = class_stack.last?.try(&.[:name])
                  cmd = klass ? subcommand_for_class[klass]? : nil
                  target_url = cmd ? "#{root_url}/#{cmd}" : root_url
                  fetch_endpoint(endpoints, target_url, path, line_no).push_param(Param.new(name, "", "flag"))
                end
              end
            end

            if has_commonscli
              commons_cli_option_names(line).each do |name|
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(name, "", "flag"))
              end
              line.scan(COMMONS_CLI_ADD_OPT) do |m|
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[2], "", "flag"))
              end
            end

            if emit_env
              line.scan(GET_ENV) { |em| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env")) }
            end
          end
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end
      endpoints.each_value { |ep| @result << ep }
      @result
    end

    # Builds a class-name -> command-name map for JCommander subcommands,
    # resolving both:
    #   .addCommand("name", new SomeClass())                (inline)
    #   .addCommand("name", someVar)                         (declare-then-register,
    #      where `someVar` was previously assigned via `... someVar = new SomeClass(...)`)
    #   .addCommand(new SomeClass())                         (single-arg, name comes
    #      from that class's own @Parameters(commandNames = "...") annotation)
    private def build_subcommand_map(content : String) : Hash(String, String)
      var_class = {} of String => String
      content.each_line do |line|
        if m = line.match(VAR_NEW_DECL)
          var_class[m[1]] = m[2]
        end
      end

      subcommand_for_class = {} of String => String
      content.each_line do |line|
        if m = line.match(JC_ADD_CMD_STR)
          subcommand_for_class[m[2]] = m[1]
        elsif m = line.match(JC_ADD_CMD_VAR)
          if klass = var_class[m[2]]?
            subcommand_for_class[klass] = m[1]
          end
        end
      end

      # Fallback for single-arg addCommand(new Class()) registrations: use
      # the class's own @Parameters(commandNames = "...") annotation, when
      # present, for classes not already resolved above.
      pending_name = nil
      content.each_line do |line|
        if m = line.match(JC_COMMAND_NAMES)
          pending_name = m[1]
        elsif m = line.match(CLASS_DECL)
          if pending_name
            subcommand_for_class[m[1]] ||= pending_name
            pending_name = nil
          end
        end
      end

      subcommand_for_class
    end

    # Extracts option names from every `Option.builder(...)` call on a line
    # (there may be several, chained with `;`), pairing each with its own
    # following `.longOpt("...")` call rather than the whole line's first
    # match. Prefers the long name; falls back to the short name.
    private def commons_cli_option_names(line : String) : Array(String)
      names = [] of String
      positions = [] of Int32
      cursor = 0
      while idx = line.index("Option.builder", cursor)
        positions << idx
        cursor = idx + 1
      end
      return names if positions.empty?

      positions.each_with_index do |pos, i|
        seg_end = i + 1 < positions.size ? positions[i + 1] : line.size
        segment = line[pos, seg_end - pos]
        if name = commons_cli_name(segment)
          names << name
        end
      end
      names
    end

    private def commons_cli_name(segment : String) : String?
      short = nil
      if m = segment.match(COMMONS_CLI_BUILDER)
        short = m[1]?
      end
      if lm = segment.match(COMMONS_CLI_LONGOPT)
        long = lm[1]
        return long unless long.empty?
      end
      return short if short && !short.empty?
      nil
    end

    private def picocli_name(body : String) : String?
      tokens = [] of String
      body.scan(/["'](--?[A-Za-z0-9][\w-]*)["']/) { |m| tokens << m[1] }
      return if tokens.empty?
      (tokens.find(&.starts_with?("--")) || tokens.first).lstrip('-')
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, ".groovy")
      if stem == "main" || stem == "cli" || stem == "app"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      lower = path.downcase
      lower.includes?("/test/") || lower.includes?("spec.groovy") || lower.includes?("test.groovy")
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
