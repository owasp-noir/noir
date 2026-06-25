require "../../../models/analyzer"
require "../../engines/kotlin_engine"

module Analyzer::Kotlin
  # Surfaces the command-line attack surface of Kotlin programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers clikt and kotlinx-cli plus gated
  # System.getenv reads.
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

    # kotlinx-cli.
    ARGPARSER   = /\bArgParser\s*\(\s*"([^"]+)"/
    KX_OPTION   = /\bby\s+\w*\.?option\s*\(\s*ArgType\.\w+\s*,\s*"([^"]+)"/
    KX_ARGUMENT = /\bby\s+\w*\.?argument\s*\(\s*ArgType\.\w+\s*,\s*"([^"]+)"/

    GET_ENV = /\bSystem\.getenv\s*\(\s*"([^"]+)"\s*\)/

    LIB_MARKERS      = ["com.github.ajalt.clikt", "kotlinx.cli"]
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

      lines.each_with_index do |line, index|
        line_no = index + 1

        # clikt command class: name= or the class name lower-cased; the class
        # whose name matches the binary is the root.
        if m = line.match(CLIKT_CLASS)
          name = line.match(CLIKT_NAME).try(&.[1]) || m[1].downcase
          current_url = name == binary ? root_url : "#{root_url}/#{name}"
          fetch_endpoint(endpoints, current_url, path, line_no)
        end

        if m = line.match(CLIKT_OPTION)
          name = option_long(m[2]) || camel_to_kebab(m[1])
          fetch_endpoint(endpoints, current_url, path, line_no).push_param(Param.new(name, "", "flag"))
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

        if emit_env
          line.scan(GET_ENV) do |env_match|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(env_match[1], "", "env"))
          end
        end
      end
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
