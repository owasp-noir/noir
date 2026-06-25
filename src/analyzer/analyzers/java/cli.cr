require "../../../models/analyzer"
require "../../engines/java_engine"

module Analyzer::Java
  # Surfaces the command-line attack surface of Java programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers picocli, args4j, JCommander,
  # commons-cli and airline, plus gated System.getenv reads.
  #
  # Line-scan analyzer (Go/Ruby/Rust CLI house style) merging endpoints by
  # URL. Subclasses Analyzer directly (JavaEngine is a module) and uses
  # JavaEngine.test_path? to skip tests.
  class Cli < Analyzer
    COMMAND_ATTR    = /@Command\s*\([^)]*\bname\s*=\s*"([^"]+)"/
    COMMAND_OPEN    = /@Command\b/
    COMMAND_NAME_KV = /\bname\s*=\s*"([^"]+)"/
    SUBCOMMANDS_KEY = /\bsubcommands\s*=/
    OPTION_ATTR     = /@Option\s*\(([^)]*)\)/
    PARAMETER_ATTR  = /@Parameter\s*\(([^)]*)\)/  # jcommander
    PARAMETERS_ATTR = /@Parameters\b([^)\n]*\)?)/ # picocli positional / jcommander command
    ARGUMENT_ATTR   = /@Argument\b/               # args4j positional
    ARGUMENTS_ATTR  = /@Arguments\s*\(([^)]*)\)/  # airline positional
    JC_COMMAND      = /@Parameters\s*\([^)]*\bcommandNames\s*=\s*\{?\s*"([^"]+)"/
    FIELD_DECL      = /^\s*(?:public|private|protected)?\s*(?:final\s+|static\s+)*[\w<>\[\].]+\s+(\w+)\s*[;=]/

    # commons-cli (no subcommands; flags on root).
    ADD_OPTION_LL = /\.addOption\s*\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,/
    LONG_OPT      = /\.longOpt\s*\(\s*"([^"]+)"/

    GET_ENV = /\bSystem\.getenv\s*\(\s*"([^"]+)"\s*\)/

    LIB_MARKERS      = ["picocli.", "org.kohsuke.args4j", "com.beust.jcommander", "org.apache.commons.cli", "com.github.rvesse.airline", "io.airlift.airline"]
    WEB_FRAMEWORK_RE = /\bimport\s+(?:org\.springframework|jakarta\.ws\.rs|javax\.ws\.rs|io\.quarkus|io\.micronaut|io\.javalin|io\.vertx|com\.linecorp\.armeria|io\.dropwizard|spark\.|org\.apache\.struts)/

    def analyze
      endpoints = {} of String => Endpoint

      get_files_by_extension(".java").each do |path|
        next if File.directory?(path)
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)

        begin
          content = read_file_content(path)
          next unless LIB_MARKERS.any? { |m| content.includes?(m) } || content.matches?(/@Command\b|@Parameter\b|new\s+JCommander|new\s+CmdLineParser|new\s+Options\s*\(/)

          binary = java_binary_name(content, path)
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

    # The picocli/airline root command's @Command name is the binary; prefer
    # the one that declares `subcommands =`. Falls back to the first @Command
    # name, then the file stem.
    private def java_binary_name(content : String, path : String) : String
      content.each_line do |line|
        if line.matches?(SUBCOMMANDS_KEY) && (m = line.match(COMMAND_ATTR))
          return m[1]
        end
      end
      if m = content.match(COMMAND_ATTR)
        return m[1]
      end
      File.basename(path, ".java")
    end

    private def scan(lines : Array(String), path : String, binary : String,
                     root_url : String, endpoints : Hash(String, Endpoint), emit_env : Bool)
      current_url = root_url
      pending_argument = false

      lines.each_with_index do |line, index|
        line_no = index + 1

        # jcommander subcommand (commandNames) takes precedence over the
        # plain @Parameters positional form. A new command context also drops
        # any dangling positional (e.g. @Parameters on a method, which never
        # reaches a field declaration).
        if m = line.match(JC_COMMAND)
          pending_argument = false
          current_url = "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        elsif m = line.match(COMMAND_ATTR)
          pending_argument = false
          current_url = m[1] == binary ? root_url : "#{root_url}/#{m[1]}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        elsif line.matches?(COMMAND_OPEN)
          # Multi-line @Command(...): the name= sits on a following line.
          if name = command_name_lookahead(lines, index)
            pending_argument = false
            current_url = name == binary ? root_url : "#{root_url}/#{name}"
            fetch_endpoint(endpoints, current_url, path, line_no)
          end
        end

        if m = line.match(OPTION_ATTR)
          # A real field/option annotation ends any dangling positional so a
          # method-level @Parameters can't steal this @Option's field.
          pending_argument = false
          if name = annotation_flag_name(m[1])
            fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(name, "", "flag"))
          end
        end

        # commons-cli (root flags).
        if m = line.match(ADD_OPTION_LL)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[2], "", "flag"))
        end
        if m = line.match(LONG_OPT)
          fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
        end

        # positional args (picocli @Parameters / args4j @Argument / airline
        # @Arguments): bind the name from the next field declaration.
        if (line.matches?(PARAMETERS_ATTR) && !line.matches?(JC_COMMAND)) ||
           line.matches?(ARGUMENT_ATTR) || line.matches?(ARGUMENTS_ATTR)
          pending_argument = true
          next
        end
        if pending_argument && (m = line.match(FIELD_DECL))
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(m[1], "", "argument"))
          pending_argument = false
        end

        if emit_env
          line.scan(GET_ENV) do |env_match|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(env_match[1], "", "env"))
          end
        end
      end
    end

    # Finds the `name = "..."` of a multi-line @Command annotation that opens
    # on `start`, scanning until the annotation closes (`)`) or the class
    # declaration begins.
    private def command_name_lookahead(lines : Array(String), start : Int32) : String?
      (start...Math.min(start + 8, lines.size)).each do |j|
        line = lines[j]
        if m = line.match(COMMAND_NAME_KV)
          return m[1]
        end
        break if j > start && (line.includes?(")") || line.matches?(/\b(?:class|interface|enum)\s/))
      end
      nil
    end

    # Extracts the long flag name from an @Option/@Parameter body's
    # names={"-p","--port"} (or name="-p", aliases={"--port"}).
    private def annotation_flag_name(body : String) : String?
      tokens = [] of String
      body.scan(/"(--?[A-Za-z0-9][\w-]*)"/) { |m| tokens << m[1] }
      return if tokens.empty?
      long = tokens.find(&.starts_with?("--"))
      (long || tokens.first).lstrip('-')
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
