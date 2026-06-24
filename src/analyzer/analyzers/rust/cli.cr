require "../../../models/analyzer"
require "../../engines/rust_engine"

module Analyzer::Rust
  # Surfaces the command-line attack surface of Rust programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers `std::env::args`/`var` plus the
  # clap / structopt / argh derive macros.
  #
  # Scope notes (follow-ups): the clap *builder* API (`Command::new(...)
  # .arg(Arg::new(...))`) is only recognized as a CLI signal, not parsed into
  # args — a line-scan can't reliably track its method-chain/paren scoping.
  # Tuple subcommand variants that reference a separate `#[derive(Args)]`
  # struct (`Serve(ServeArgs)`) surface that struct's flags on the root
  # rather than the subcommand, since the variant→struct link isn't resolved
  # here; inline-field variants (`Serve { ... }`) attribute correctly.
  #
  # Line-scan analyzer (Go/Python CLI house style) with a cross-file
  # URL-merge, instead of the tree-sitter analyze_file path the HTTP Rust
  # analyzers use. Subclasses Analyzer directly (RustEngine#analyze_file is
  # abstract) and reuses RustEngine.test_path? as a class method.
  class Cli < Analyzer
    DERIVE_RE = /#\[\s*derive\s*\(([^)]*)\)/
    ITEM_RE   = /\b(?:struct|enum)\s+\w+/
    # clap/structopt field attribute, e.g. #[arg(short, long, env = "X")].
    CLAP_ATTR_RE = /#\[\s*(?:arg|structopt|clap)\s*\(([^\]]*)\)/
    ARGH_ATTR_RE = /#\[\s*argh\s*\(([^\]]*)\)/
    FIELD_RE     = /^\s*(?:pub\s+)?(\w+)\s*:/
    VARIANT_RE   = /^\s*(?:#\[\s*command\s*\(\s*name\s*=\s*"([^"]+)"[^\]]*\)\s*\]\s*)?([A-Z]\w*)/

    # clap builder marker (used only to recognise a builder-style CLI; the
    # builder arg/subcommand tree is a follow-up — see the note in `analyze`).
    BUILDER_NEW = /Command::new\s*\(\s*"([^"]+)"/

    # builtin.
    ENV_VAR_RE  = /\b(?:std::)?env::var(?:_os)?\s*\(\s*"([^"]+)"/
    ENV_ARGS_RE = /\b(?:std::)?env::args(?:_os)?\s*\(/

    # Web crates: their env::var reads are config, not a CLI surface.
    WEB_CRATE_RE = /\buse\s+(?:axum|actix_web|rocket|warp|tide|poem|salvo|gotham|loco_rs|hyper|tonic|tower_http)\b|::serve\s*\(|HttpServer::new|TcpListener::bind/

    def analyze
      cargo = collect_cargo_binaries
      endpoints = {} of String => Endpoint

      get_files_by_extension(".rs").each do |path|
        next if File.directory?(path)
        next if RustEngine.test_path?(path)

        begin
          content = read_file_content(path)
          next unless cli_evidence?(content)

          binary = rust_binary_name(cargo, path)
          root_url = "cli://#{binary}"
          emit_env = !content.matches?(WEB_CRATE_RE)
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
      content.matches?(DERIVE_RE) && content.matches?(/\b(?:Parser|Subcommand|Args|StructOpt|FromArgs)\b/) ||
        content.matches?(/\buse\s+(?:clap|structopt|argh|bpaf|pico_args)\b|\b(?:clap|structopt|argh|bpaf|pico_args)::/) ||
        content.matches?(ENV_ARGS_RE) ||
        (content.includes?("clap") && content.matches?(BUILDER_NEW))
    end

    private def rust_binary_name(cargo : Array(Tuple(String, String)), path : String) : String
      expanded = File.expand_path(File.dirname(path))
      cargo.each do |name, dir|
        return name if expanded == dir || expanded.starts_with?("#{dir}/")
      end
      File.basename(path, ".rs")
    end

    private def scan(lines : Array(String), path : String, binary : String,
                     root_url : String, endpoints : Hash(String, Endpoint), emit_env : Bool)
      depth = 0
      item_kind : Symbol? = nil # :parser | :subcommand | :args
      item_body_depth = -1
      item_entered = false
      current_cmd = root_url
      pending_derive : String? = nil
      pending_attr : Tuple(Symbol, String)? = nil # {:clap|:argh, body}

      lines.each_with_index do |line, index|
        entry_depth = depth
        line_no = index + 1
        stripped = line.strip

        # derive + item entry (only while not already inside a derive item).
        if item_kind.nil?
          if dm = line.match(DERIVE_RE)
            pending_derive = dm[1]
          end
          if (derive = pending_derive) && line.matches?(ITEM_RE)
            if kind = classify_derive(derive)
              item_kind = kind
              current_cmd = root_url
              opened = line.count('{')
              # The body may open on this line (`struct X {`) or the next
              # (`struct X\n{`). Only mark the item "entered" once its brace
              # is actually seen, so the teardown guard below can't fire on
              # the declaration line and drop the whole item.
              item_body_depth = opened > 0 ? entry_depth + opened : entry_depth + 1
              item_entered = opened > 0
            end
            pending_derive = nil
          end
        end

        if item_kind
          # subcommand enum: a variant at the enum-body level opens a command.
          if item_kind == :subcommand && entry_depth == item_body_depth
            if vm = stripped.match(VARIANT_RE)
              # clap renames CamelCase variants to kebab-case by default
              # (`BuildProject` -> `build-project`); an explicit
              # `#[command(name = "...")]` wins.
              name = vm[1]? || camel_to_kebab(vm[2])
              current_cmd = "#{root_url}/#{name}"
              fetch_endpoint(endpoints, current_cmd, path, line_no)
            end
          end

          if am = line.match(CLAP_ATTR_RE)
            pending_attr = {:clap, am[1]}
          elsif am = line.match(ARGH_ATTR_RE)
            pending_attr = {:argh, am[1]}
          elsif (attr = pending_attr) && (fm = stripped.match(FIELD_RE))
            apply_field(attr, fm[1], current_cmd, path, line_no, endpoints)
            pending_attr = nil
          end
        end

        # builtin env reads (gated).
        if emit_env
          line.scan(ENV_VAR_RE) do |env_match|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(env_match[1], "", "env"))
          end
        end

        depth += line.count('{') - line.count('}')
        item_entered = true if item_kind && !item_entered && depth >= item_body_depth
        if item_kind && item_entered && depth < item_body_depth
          item_kind = nil
          item_entered = false
          current_cmd = root_url
          pending_attr = nil
        end
      end
    end

    private def classify_derive(derive : String) : Symbol?
      return :parser if derive.includes?("Parser") || derive.includes?("StructOpt")
      return :subcommand if derive.includes?("Subcommand")
      return :args if derive.includes?("Args") || derive.includes?("FromArgs")
      nil
    end

    # Resolves one struct field's clap/argh attribute into a flag/argument
    # (plus any env binding) on the given command.
    private def apply_field(attr : Tuple(Symbol, String), field : String, url : String,
                            path : String, line_no : Int32, endpoints : Hash(String, Endpoint))
      kind, body = attr
      ep = fetch_endpoint(endpoints, url, path, line_no)

      if kind == :argh
        if body.includes?("positional")
          ep.push_param(Param.new(kebab(field), "", "argument"))
        elsif body.includes?("option") || body.includes?("switch")
          ep.push_param(Param.new(kebab(field), "", "flag"))
        end
        return
      end

      # clap / structopt
      if env = body.match(/\benv\s*=\s*"([^"]+)"/)
        ep.push_param(Param.new(env[1], "", "env"))
      end
      if long = body.match(/\blong\s*=\s*"([^"]+)"/)
        ep.push_param(Param.new(long[1], "", "flag"))
      elsif body.matches?(/\blong\b/) || body.matches?(/\bshort\b/)
        ep.push_param(Param.new(kebab(field), "", "flag"))
      elsif !body.matches?(/\benv\s*=/)
        # No long/short and not a pure env binding: a positional argument.
        ep.push_param(Param.new(kebab(field), "", "argument"))
      end
    end

    private def kebab(name : String) : String
      name.gsub('_', '-')
    end

    # CamelCase -> kebab-case, matching clap's default subcommand renaming
    # (`BuildProject` -> `build-project`, `Serve` -> `serve`).
    private def camel_to_kebab(name : String) : String
      result = String::Builder.new
      name.each_char_with_index do |ch, i|
        result << '-' if ch.uppercase? && i > 0
        result << ch.downcase
      end
      result.to_s
    end

    # Maps each Cargo manifest directory to its binary name ([[bin]] name when
    # present, else the [package] name).
    private def collect_cargo_binaries : Array(Tuple(String, String))
      out = [] of Tuple(String, String)
      get_files_by_extension(".toml").each do |path|
        next unless File.basename(path) == "Cargo.toml"
        begin
          content = read_file_content(path)
        rescue
          next
        end
        name = content.match(/\[\[bin\]\][^\[]*?name\s*=\s*"([^"]+)"/m).try(&.[1]) ||
               content.match(/\[package\][^\[]*?name\s*=\s*"([^"]+)"/m).try(&.[1])
        next unless name
        out << {name, File.expand_path(File.dirname(path))}
      end
      out.sort_by! { |(_n, dir)| -dir.size }
      out
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
