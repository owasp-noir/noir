require "../../../models/analyzer"

module Analyzer::Perl
  # Surfaces the command-line attack surface of Perl programs as `cli://`
  # endpoints: Getopt::Long (GetOptions) / Getopt::Std (getopts) /
  # Getopt::Long::Descriptive (describe_options) / MooX::Options (option)
  # plus @ARGV indexing and %ENV. Line-scan; root attribution (these libs
  # are flat), merged by URL.
  class Cli < Analyzer
    # GetOptions("port=i" => \$port) — the spec string bound to a reference.
    GETOPT_KEY = /["']([a-zA-Z][\w-]*)[^"']*["']\s*=>\s*\\/
    GETOPTS    = /\bgetopts?\s*\(\s*['"]([^'"]*)['"]/
    ARGV_IDX   = /\$ARGV\s*\[\s*(\d+)\s*\]/
    ENV_READ   = /\$ENV\{\s*['"]?([A-Za-z_]\w*)['"]?\s*\}/
    # describe_options('%c %o', ['verbose|v' => 'be verbose'], ...) — each
    # array-ref's leading quoted spec string. Only the leading identifier is
    # captured so Getopt::Long::Descriptive suffix modifiers (|alias, =s,
    # !, +, :i, ...) don't leak into the reported flag name.
    DESCRIBE_OPT_SPEC = /\[\s*['"]([a-zA-Z][\w-]*)[^'"]*['"]/
    # option 'name' => (is => 'ro', ...); — MooX::Options attribute decl.
    # Only extracted when `use MooX::Options` was actually seen in the file,
    # so an unrelated bareword sub/call literally named `option` elsewhere
    # doesn't get misattributed as a MooX::Options flag.
    MOOX_OPTION = /\boption\s+['"]([a-zA-Z][\w-]*)['"]\s*=>/
    MOOX_MARKER = /\buse\s+MooX::Options\b/

    MARKERS = /\buse\s+Getopt::(?:Long|Std)\b|\bGetOptions\s*\(|\bgetopts?\s*\(|\buse\s+App::Cmd\b|\bMooseX::Getopt\b|\$ARGV\s*\[\s*\d+\s*\]|\buse\s+Getopt::Long::Descriptive\b|\bdescribe_options\s*\(|\buse\s+MooX::Options\b/
    WEB_RE  = /\buse\s+(?:Mojolicious|Mojo::|Dancer2?|Catalyst|Plack|Dancer)\b/

    def analyze
      endpoints = {} of String => Endpoint
      [".pl", ".pm"].each do |ext|
        get_files_by_extension(ext).each do |path|
          next if File.directory?(path)
          next if cli_test_path?(path)
          next unless File.exists?(path)
          begin
            content = read_file_content(path)
            next unless content.matches?(MARKERS)
            root_url = "cli://#{cli_binary_name(path)}"
            emit_env = !content.matches?(WEB_RE)
            uses_moox_options = content.matches?(MOOX_MARKER)
            in_getoptions = false
            go_depth = 0
            in_describe_options = false
            do_depth = 0
            content.each_line.with_index do |line, index|
              line_no = index + 1
              # Only treat `"key" => \ref` pairs as flags inside the
              # GetOptions(...) call, so unrelated reference hashes elsewhere
              # in the file don't leak as bogus flags.
              in_getoptions = true if line.includes?("GetOptions") && line.includes?("(")
              if in_getoptions
                line.scan(GETOPT_KEY) { |m| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag")) }
              end
              if in_getoptions
                go_depth += line.count('(') - line.count(')')
                in_getoptions = false if go_depth <= 0
              end
              if m = line.match(GETOPTS)
                parse_getopt_short(m[1], fetch_endpoint(endpoints, root_url, path, line_no))
              end
              if m = line.match(ARGV_IDX)
                fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new("arg#{m[1]}", "", "argument"))
              end
              if emit_env
                line.scan(ENV_READ) { |em| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(em[1], "", "env")) }
              end
              # Only treat `[ 'spec' => ... ]` array-refs as option specs
              # inside the describe_options(...) call, so unrelated array
              # literals elsewhere in the file don't leak as bogus flags.
              in_describe_options = true if line.includes?("describe_options") && line.includes?("(")
              if in_describe_options
                line.scan(DESCRIBE_OPT_SPEC) { |m| fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag")) }
              end
              if in_describe_options
                do_depth += line.count('(') - line.count(')')
                in_describe_options = false if do_depth <= 0
              end
              if uses_moox_options
                if m = line.match(MOOX_OPTION)
                  fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(m[1], "", "flag"))
                end
              end
            end
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
            next
          end
        end
      end
      endpoints.each_value { |ep| @result << ep }
      @result
    end

    private def parse_getopt_short(spec : String, endpoint : Endpoint)
      spec.each_char { |ch| endpoint.push_param(Param.new(ch.to_s, "", "flag")) unless ch == ':' }
    end

    private def cli_binary_name(path : String) : String
      stem = File.basename(path, File.extname(path))
      if stem == "main" || stem == "cli" || stem == "app"
        parent = File.basename(File.dirname(path))
        return parent unless parent.empty?
      end
      stem
    end

    private def cli_test_path?(path : String) : Bool
      lower = path.downcase
      lower.includes?("/t/") || lower.includes?("/test/") || lower.includes?("_test.")
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
