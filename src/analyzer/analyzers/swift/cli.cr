require "../../../models/analyzer"
require "../../engines/swift_engine"

module Analyzer::Swift
  # Surfaces the command-line attack surface of Swift programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers swift-argument-parser plus builtin
  # CommandLine.arguments / ProcessInfo.environment / getenv.
  #
  # Line-scan analyzer (Go/Ruby/Rust CLI house style) merging endpoints by
  # URL. Subclasses Analyzer directly (SwiftEngine#analyze_file is abstract)
  # and reuses SwiftEngine.swift_test_path? to skip tests.
  class Cli < Analyzer
    PARSABLE_STRUCT = /\b(?:struct|enum|class)\s+(\w+)\s*:\s*[^\{]*\b(?:Async)?ParsableCommand\b/
    COMMAND_NAME    = /\bcommandName:\s*"([^"]+)"/
    SUBCOMMANDS_KEY = /\bsubcommands:/
    OPTION_FLAG     = /@(?:Option|Flag)\b/
    ARGUMENT_WRAP   = /@Argument\b/
    CUSTOM_LONG     = /name:\s*\.(?:customLong|long)\s*\(\s*"([^"]+)"/
    VAR_DECL        = /\bvar\s+(\w+)/

    GETENV   = /\bgetenv\s*\(\s*"([^"]+)"/
    PROC_ENV = /ProcessInfo(?:\.processInfo|\(\))?\.environment\s*\[\s*"([^"]+)"\s*\]/
    ARGS_IDX = /\bCommandLine\.arguments\s*\[\s*(\d+)\s*\]/

    WEB_FRAMEWORK_RE = /\bimport\s+(?:Vapor|Hummingbird\w*|Kitura\w*)\b|\bapp\.environment\b/

    def analyze
      endpoints = {} of String => Endpoint

      get_files_by_extension(".swift").each do |path|
        next if File.directory?(path)
        next if SwiftEngine.swift_test_path?(path)
        next unless File.exists?(path)

        begin
          content = read_file_content(path)
          next unless cli_evidence?(content)

          binary = swift_binary_name(content, path)
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

    private def cli_evidence?(content : String) : Bool
      content.includes?("import ArgumentParser") || content.matches?(PARSABLE_STRUCT) ||
        content.matches?(OPTION_FLAG) || content.matches?(ARGUMENT_WRAP) ||
        content.matches?(/\bCommandLine\.arguments\b/)
    end

    # The root command is the ParsableCommand whose configuration declares
    # `subcommands:`; its commandName (or struct name) is the binary.
    private def swift_binary_name(content : String, path : String) : String
      lines = content.lines
      fallback : String? = nil
      lines.each_with_index do |line, i|
        next unless sm = line.match(PARSABLE_STRUCT)
        name = command_name_after(lines, i) || sm[1].downcase
        # The first ParsableCommand is the binary unless a later one is the
        # explicit root (declares `subcommands:`).
        fallback ||= name
        (i...Math.min(i + 20, lines.size)).each do |j|
          return name if lines[j].matches?(SUBCOMMANDS_KEY)
        end
      end
      fallback || File.basename(path, ".swift")
    end

    # commandName from a CommandConfiguration that may open a few lines below
    # the struct declaration.
    private def command_name_after(lines : Array(String), start : Int32) : String?
      (start...Math.min(start + 15, lines.size)).each do |j|
        if m = lines[j].match(COMMAND_NAME)
          return m[1]
        end
      end
      nil
    end

    private def scan(lines : Array(String), path : String, binary : String,
                     root_url : String, endpoints : Hash(String, Endpoint), emit_env : Bool)
      current_url = root_url
      pending : Symbol? = nil # :flag | :argument awaiting the var name
      pending_custom : String? = nil

      lines.each_with_index do |line, index|
        line_no = index + 1

        if sm = line.match(PARSABLE_STRUCT)
          name = command_name_after(lines, index) || sm[1].downcase
          current_url = name == binary ? root_url : "#{root_url}/#{name}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end

        if line.matches?(OPTION_FLAG)
          pending = :flag
          pending_custom = line.match(CUSTOM_LONG).try(&.[1])
        elsif line.matches?(ARGUMENT_WRAP)
          pending = :argument
          pending_custom = nil
        end

        if pending && (vm = line.match(VAR_DECL))
          name = pending_custom || camel_to_kebab(vm[1])
          type = pending == :flag ? "flag" : "argument"
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(name, "", type))
          pending = nil
          pending_custom = nil
        end

        if emit_env
          line.scan(PROC_ENV) do |em|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env"))
          end
          line.scan(GETENV) do |em|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env"))
          end
        end

        if m = line.match(ARGS_IDX)
          unless m[1] == "0"
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
          end
        end
      end
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
