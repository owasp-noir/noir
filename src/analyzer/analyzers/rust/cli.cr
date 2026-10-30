require "../../../models/analyzer"
require "../../engines/rust_engine"
require "../../engines/cli_endpoint_support"

module Analyzer::Rust
  # Surfaces the command-line attack surface of Rust programs as `cli://`
  # endpoints: one endpoint per (sub)command with named options
  # (param_type "flag"), positional arguments ("argument") and consumed
  # environment variables ("env"). Covers `std::env::args`/`var` plus the
  # clap / structopt / argh derive macros and the getopts builder API
  # (`Options::new()` + `opts.optopt`/`optflag`/`optflagopt`/`optmulti`/`reqopt`).
  #
  # Scope notes (follow-ups): the clap *builder* API (`Command::new(...)
  # .arg(Arg::new(...))`) is only recognized as a CLI signal, not parsed into
  # args — a line-scan can't reliably track its method-chain/paren scoping.
  # A `#[command(flatten)]` struct's flags surface on the root rather than
  # on the command that flattens it.
  #
  # Line-scan analyzer (Go/Python CLI house style) with a cross-file
  # URL-merge, instead of the tree-sitter analyze_file path the HTTP Rust
  # analyzers use. Subclasses Analyzer directly (RustEngine#analyze_file is
  # abstract) and reuses RustEngine.test_path? as a class method.
  class Cli < Analyzer
    analyzer_for "rust_cli"

    include CliEndpointSupport

    DERIVE_RE = /#\[\s*derive\s*\(([^)]*)\)/
    ITEM_RE   = /\b(?:struct|enum)\s+([A-Za-z_]\w*)/
    # clap/structopt field attribute, e.g. #[arg(short, long, env = "X")].
    CLAP_ATTR_RE = /#\[\s*(?:arg|structopt|clap)(?:\s*\((.*)\))?\s*\]\s*$/m
    ARGH_ATTR_RE = /#\[\s*argh(?:\s*\((.*)\))?\s*\]\s*$/m
    FIELD_RE     = /^\s*(?:pub\s+)?(\w+)\s*:/
    # `#[command(subcommand)]` (clap 4) / `#[clap(subcommand)]` / `#[structopt(subcommand)]`.
    SUBCOMMAND_ATTR_RE = /#\[\s*(?:command|clap|structopt)\s*\([^\]]*\bsubcommand\b/
    QUOTED_RE          = /"(?:\\.|[^"\\])*"/
    # `method: UsersMethod` / `method: Option<UsersMethod>` / `pub cmd: sub::Cmd`.
    SUBCOMMAND_FIELD_RE = /^(?:pub(?:\([^)]*\))?\s+)?\w+\s*:\s*(?:Option\s*<\s*)?([A-Za-z0-9_:]+)/
    VARIANT_RE          = /^\s*(?:#\[\s*command\s*\([^\]]*\bname\s*=\s*"([^"]+)"[^\]]*\)\s*\]\s*)?([A-Z]\w*)(?:\s*\(\s*([A-Za-z0-9_:]+)\s*\))?/

    # Shared helper that buffers multi-line attributes with bracket depth tracking
    # outside strings, strips comments quote-aware, and parses derives, command names, and arg attributes.
    private class AttributeScanner
      getter pending_derive : String?
      getter pending_command_name : String?
      getter? pending_subcommand = false
      getter pending_attrs : Array(Tuple(Symbol, String))

      @in_block_comment = false
      @in_attr = false
      @attr_depth = 0
      @attr_buf = IO::Memory.new
      @pending_derive : String? = nil
      @pending_command_name : String? = nil
      @pending_attrs = [] of Tuple(Symbol, String)

      def initialize
      end

      def process_line(line : String) : String
        line_code, @in_block_comment = Noir::RustCalleeExtractor.strip_comment_with_state(line, @in_block_comment, preserve_strings: true)
        return "" if line_code.strip.empty? && !@in_attr

        code_out = String::Builder.new
        in_string = false
        escaped = false
        quote_char = '\0'
        reader = Char::Reader.new(line_code)

        while reader.has_next?
          char = reader.current_char

          if in_string
            if escaped
              escaped = false
            elsif char == '\\'
              escaped = true
            elsif char == quote_char
              in_string = false
            end

            if @in_attr
              @attr_buf << char
            else
              code_out << char
            end
          else
            if char == '"'
              in_string = true
              quote_char = char
              if @in_attr
                @attr_buf << char
              else
                code_out << char
              end
            elsif !@in_attr
              if char == '#'
                saved_pos = reader.pos
                reader.next_char
                while reader.has_next? && reader.current_char.ascii_whitespace?
                  reader.next_char
                end
                if reader.has_next? && reader.current_char == '['
                  @in_attr = true
                  @attr_depth = 1
                  @attr_buf.clear
                  @attr_buf << "#["
                  reader.next_char
                  next
                else
                  reader.pos = saved_pos
                  code_out << char
                end
              else
                code_out << char
              end
            else
              @attr_buf << char
              if char == '['
                @attr_depth += 1
              elsif char == ']'
                @attr_depth -= 1
                if @attr_depth <= 0
                  @in_attr = false
                  @attr_depth = 0
                  parse_attribute(@attr_buf.to_s)
                  @attr_buf.clear
                end
              end
            end
          end

          reader.next_char
        end

        if @in_attr
          @attr_buf << " "
        end

        code_out.to_s.strip
      end

      private def parse_attribute(attr : String)
        if dm = attr.match(DERIVE_RE)
          @pending_derive = dm[1]
        end
        if am = attr.match(CLAP_ATTR_RE)
          body = am[1]? || ""
          @pending_attrs << {:clap, body}
        elsif am = attr.match(ARGH_ATTR_RE)
          body = am[1]? || ""
          @pending_attrs << {:argh, body}
        end
        if cm = attr.match(/#\[\s*command\s*\(.*?\bname\s*=\s*"([^"]+)"/m)
          @pending_command_name = cm[1]
        end
        if attr.matches?(SUBCOMMAND_ATTR_RE) && attr.gsub(QUOTED_RE, "").matches?(SUBCOMMAND_ATTR_RE)
          @pending_subcommand = true
        end
      end

      def consume_subcommand : Bool
        val = @pending_subcommand
        @pending_subcommand = false
        val
      end

      def consume_derive : String?
        val = @pending_derive
        @pending_derive = nil
        val
      end

      def consume_command_name : String?
        val = @pending_command_name
        @pending_command_name = nil
        val
      end

      def clear_attrs
        @pending_attrs.clear
      end

      def reset_for_new_item
        @pending_attrs.clear
        @pending_command_name = nil
        @pending_subcommand = false
      end
    end

    # clap builder marker (used only to recognise a builder-style CLI; the
    # builder arg/subcommand tree is a follow-up — see the note in `analyze`).
    BUILDER_NEW = /Command::new\s*\(\s*"([^"]+)"/

    # builtin.
    ENV_VAR_RE  = /\b(?:std::)?env::var(?:_os)?\s*\(\s*"([^"]+)"/
    ENV_ARGS_RE = /\b(?:std::)?env::args(?:_os)?\s*\(/

    # getopts: a flat (no-subcommand) builder API. `let mut opts =
    # Options::new();` binds a receiver variable, then `opts.optopt(short,
    # long, desc, hint)` / `optflag(short, long, desc)` /
    # `optflagopt(short, long, desc, hint)` / `optmulti(short, long, desc,
    # hint)` / `reqopt(short, long, desc, hint)` register each option on it.
    # The optional type-annotation group tolerates a `getopts::` prefix
    # (`let mut opts: getopts::Options = ...`), matching the same prefix
    # already tolerated before `Options::new`.
    GETOPTS_NEW_RE  = /\blet\s+(?:mut\s+)?(\w+)(?:\s*:\s*(?:getopts::)?Options)?\s*=\s*(?:getopts::)?Options::new\s*\(\s*\)/
    GETOPTS_CALL_RE = /\b(\w+)\.(?:optopt|reqopt|optflagopt|optflag|optmulti)\s*\(\s*"([^"]*)"\s*,\s*"([^"]*)"/

    # Web crates: their env::var reads are config, not a CLI surface.
    WEB_CRATE_RE = /\buse\s+(?:axum|actix_web|ntex|rocket|warp|tide|poem|salvo|gotham|loco_rs|hyper|tonic|tower_http)\b|::serve\s*\(|HttpServer::new|TcpListener::bind/

    def analyze
      cargo = collect_cargo_binaries
      endpoints = {} of String => Endpoint

      rs_sources = [] of Tuple(String, String, Array(String))
      get_files_by_extension(".rs").each do |path|
        next if RustEngine.test_path?(base_relative_path(path))

        begin
          content = read_file_content(path)
          next unless cli_evidence?(content)
          rs_sources << {path, content, content.lines}
        rescue e
          logger.debug "Error analyzing #{path}: #{e}"
          next
        end
      end

      tree = collect_clap_tree(rs_sources, cargo)

      rs_sources.each do |path, content, lines|
        binary = rust_binary_name(cargo, path)
        root_url = "cli://#{binary}"
        emit_env = !content.matches?(WEB_CRATE_RE)
        scan(lines, path, binary, root_url, endpoints, emit_env, tree)
      rescue e
        logger.debug "Error analyzing #{path}: #{e}"
        next
      end

      @result.concat(cli_endpoints(endpoints))
      @result
    end

    private def cli_evidence?(content : String) : Bool
      content.matches?(DERIVE_RE) && content.matches?(/\b(?:Parser|Subcommand|Args|StructOpt|FromArgs)\b/) ||
        content.matches?(/\buse\s+(?:clap|structopt|argh|bpaf|pico_args|getopts)\b|\b(?:clap|structopt|argh|bpaf|pico_args|getopts)::/) ||
        content.matches?(ENV_ARGS_RE) ||
        (content.includes?("clap") && content.matches?(BUILDER_NEW))
    end

    private def rust_binary_name(cargo : Array(Tuple(String, String)), path : String) : String
      expanded = Noir::PathScope.expand(File.dirname(path))
      cargo.each do |name, dir|
        return name if expanded == dir || expanded.starts_with?("#{dir}/")
      end
      File.basename(path, ".rs")
    end

    # The clap command tree of a scan. Items are keyed by file and name
    # (`src/run.rs::Args`): a crate commonly has a Parser named `Args` and
    # per-command `run::Args` / `build::Args`, so a bare name is ambiguous.
    private class ClapTree
      getter enums = {} of String => String             # Subcommand enum key => binary
      getter enum_index = {} of String => Array(String) # enum name => paths
      getter args_index = {} of String => Array(String) # Args struct name => paths
      getter args_subcommand = {} of String => String   # Args struct key => its `#[command(subcommand)]` field type
      getter binaries = {} of String => String          # path => binary
      # Every command path an enum's variants sit under: an enum shared by
      # `users` and `orders` has both.
      getter enum_bases = {} of String => Array(String)
      # The commands an Args struct holds the flags of (`Users(UsersArgs)`).
      getter args_urls = {} of String => Array(String)
    end

    # A diamond of shared enums multiplies paths; real CLIs stay far below this.
    MAX_COMMAND_BASES = 32

    private def collect_clap_tree(rs_sources : Array(Tuple(String, String, Array(String))),
                                  cargo : Array(Tuple(String, String))) : ClapTree
      tree = ClapTree.new

      # Pass 1: Subcommand enums, Args structs and the Args and Parser
      # structs' `#[command(subcommand)]` field types.
      parser_fields = [] of Tuple(String, String) # {field type, path}
      rs_sources.each do |path, _content, lines|
        tree.binaries[path] = rust_binary_name(cargo, path)
        scanner = AttributeScanner.new
        current_args : String? = nil
        in_parser = false

        lines.each do |line|
          code = scanner.process_line(line)
          next if code.empty?
          subcommand_field = scanner.consume_subcommand

          if m = code.match(ITEM_RE)
            derive = scanner.consume_derive
            kind = derive && classify_derive(derive)
            key = "#{path}::#{m[1]}"
            current_args = nil
            in_parser = kind == :parser && code.matches?(/\bstruct\s/)
            if kind == :subcommand && code.matches?(/\benum\s/)
              tree.enums[key] = tree.binaries[path]
              (tree.enum_index[m[1]] ||= [] of String) << path
            elsif kind == :args && code.matches?(/\bstruct\s/)
              (tree.args_index[m[1]] ||= [] of String) << path
              current_args = key
            end
          elsif subcommand_field && (fm = code.match(SUBCOMMAND_FIELD_RE))
            if args = current_args
              tree.args_subcommand[args] = fm[1]
            elsif in_parser
              parser_fields << {fm[1], path}
            end
          end
        end
      end

      # Pass 2: parent enum => {child enum, command name} links, and the
      # variants that wrap an Args struct.
      children = {} of String => Array(Tuple(String, String))
      adopted = Set(String).new
      args_links = [] of Tuple(String, String, String) # {struct key, parent enum key, command name}
      link = ->(child : String?, parent : String, name : String) {
        if child && child != parent
          (children[parent] ||= [] of Tuple(String, String)) << {child, name}
          adopted << child
        end
      }

      rs_sources.each do |path, _content, lines|
        current_enum : String? = nil
        variant : String? = nil
        depth = 0
        enum_depth = -1
        scanner = AttributeScanner.new

        lines.each do |line|
          entry_depth = depth
          code = scanner.process_line(line)

          if !code.empty?
            subcommand_field = scanner.consume_subcommand
            if current_enum.nil?
              # An item's own `#[command(name = ...)]` (the Parser struct's
              # binary name) must not carry over to the next enum's first variant.
              scanner.consume_command_name if code.matches?(ITEM_RE)
              if (m = code.match(/\benum\s+([A-Za-z_]\w*)/)) && tree.enums.has_key?("#{path}::#{m[1]}")
                current_enum = "#{path}::#{m[1]}"
                variant = nil
                opened = code.count('{')
                enum_depth = opened > 0 ? entry_depth + opened : entry_depth + 1
              end
            elsif entry_depth == enum_depth
              if m = code.match(VARIANT_RE)
                variant = name = m[1]? || scanner.consume_command_name || camel_to_kebab(m[2])
                if payload = m[3]?
                  if child = resolve_clap_item(tree, tree.enum_index, payload, path)
                    link.call(child, current_enum, name)
                  elsif args = resolve_clap_item(tree, tree.args_index, payload, path)
                    args_links << {args, current_enum, name}
                    if field_type = tree.args_subcommand[args]?
                      link.call(resolve_clap_item(tree, tree.enum_index, field_type, args[0, args.rindex!("::")]), current_enum, name)
                    end
                  end
                end
              elsif code.matches?(/^[A-Z]\w*/)
                scanner.consume_command_name
              end
            elsif entry_depth == enum_depth + 1 && subcommand_field && (name = variant) &&
                  (fm = code.match(SUBCOMMAND_FIELD_RE))
              # Inline variant: `Jwks { #[command(subcommand)] action: JwksAction }`.
              link.call(resolve_clap_item(tree, tree.enum_index, fm[1], path), current_enum, name)
            end
          end

          depth += code.count('{') - code.count('}')
          if current_enum && depth < enum_depth
            current_enum = nil
            scanner.consume_command_name
          end
        end
      end

      # Pass 3: walk down from the root enums, one base per distinct path.
      # The roots are the enums a Parser's subcommand field names and those
      # no variant nests. A cycle back to the root (`As(AsArgs)` holding the
      # top-level enum again) adopts every enum, so the Parser's field is
      # what anchors it. An enum only reachable through a cycle nothing else
      # enters seeds a walk of its own.
      roots = parser_fields.compact_map { |type, path| resolve_clap_item(tree, tree.enum_index, type, path) }
      roots.concat(tree.enums.keys.reject { |key| adopted.includes?(key) })
      roots.each { |key| walk_clap_tree(tree, children, key, "cli://#{tree.enums[key]}", [key]) }
      tree.enums.each do |key, binary|
        walk_clap_tree(tree, children, key, "cli://#{binary}", [key]) unless tree.enum_bases.has_key?(key)
      end
      args_links.each do |args, parent, name|
        urls = tree.args_urls[args] ||= [] of String
        tree.enum_bases[parent].each { |base| urls << "#{base}/#{name}" }
        urls.uniq!
      end

      tree
    end

    private def walk_clap_tree(tree : ClapTree, children : Hash(String, Array(Tuple(String, String))),
                               key : String, base : String, stack : Array(String))
      bases = tree.enum_bases[key] ||= [] of String
      return if bases.size >= MAX_COMMAND_BASES || bases.includes?(base)
      bases << base
      (children[key]? || [] of Tuple(String, String)).each do |(child, name)|
        walk_clap_tree(tree, children, child, "#{base}/#{name}", stack + [child]) unless stack.includes?(child)
      end
    end

    # The key of the item a type path names, seen from `from_path`. A
    # module-qualified path (`run::Args`, `crate::cmd::Run`) must match the
    # item's file (`src/run.rs`, `src/cmd/mod.rs`); a bare name prefers the
    # same file, then the same crate. Ambiguity resolves to nothing.
    private def resolve_clap_item(tree : ClapTree, index : Hash(String, Array(String)),
                                  type_path : String, from_path : String) : String?
      segments = type_path.split("::").reject { |segment| segment.empty? || segment.in?("crate", "self", "super") }
      return unless (name = segments.pop?) && (paths = index[name]?)

      candidates = if segments.empty?
                     paths.includes?(from_path) ? [from_path] : paths
                   else
                     suffix = "/#{segments.join('/')}"
                     paths.select { |path| path.rchop(".rs").rchop("/mod").ends_with?(suffix) }
                   end
      if candidates.size > 1
        candidates = candidates.select { |path| tree.binaries[path]? == tree.binaries[from_path]? }
      end
      "#{candidates.first}::#{name}" if candidates.size == 1
    end

    private def scan(lines : Array(String), path : String, binary : String,
                     root_url : String, endpoints : Hash(String, Endpoint), emit_env : Bool,
                     tree : ClapTree)
      depth = 0
      item_kind : Symbol? = nil # :parser | :subcommand | :args
      current_enum : String? = nil
      current_enum_bases = [root_url]
      item_body_depth = -1
      item_entered = false
      current_cmds = [root_url]
      scanner = AttributeScanner.new

      # getopts has no subcommand concept: a receiver-variable map (not a
      # sticky cursor) links each `Options::new()` binding to the command
      # URL its `opt*` calls should attach to (always root_url today, but
      # keeps the same variable-scoping shape as the other CLI analyzers).
      getopts_vars = {} of String => String

      lines.each_with_index do |line, index|
        entry_depth = depth
        line_no = index + 1
        code = scanner.process_line(line)

        # derive + item entry (only while not already inside a derive item).
        if item_kind.nil?
          if (derive = scanner.pending_derive) && (im = code.match(ITEM_RE))
            if kind = classify_derive(derive)
              item_kind = kind
              key = "#{path}::#{im[1]}"
              if kind == :subcommand
                current_enum = key
                current_enum_bases = tree.enum_bases[key]? || [root_url]
                current_cmds = current_enum_bases
              elsif kind == :args
                current_cmds = tree.args_urls[key]? || [root_url]
              else
                current_cmds = [root_url]
              end
              opened = code.count('{')
              # The body may open on this line (`struct X {`) or the next
              # (`struct X\n{`). Only mark the item "entered" once its brace
              # is actually seen, so the teardown guard below can't fire on
              # the declaration line and drop the whole item.
              item_body_depth = opened > 0 ? entry_depth + opened : entry_depth + 1
              item_entered = opened > 0
            end
            scanner.consume_derive
          elsif code.match(ITEM_RE)
            scanner.consume_derive
          end
        end

        if item_kind
          # subcommand enum: a variant at the enum-body level opens a command.
          if item_kind == :subcommand && entry_depth == item_body_depth
            if vm = code.match(VARIANT_RE)
              # clap renames CamelCase variants to kebab-case by default
              # (`BuildProject` -> `build-project`); an explicit
              # `#[command(name = "...")]` wins.
              name = vm[1]? || scanner.consume_command_name || camel_to_kebab(vm[2])
              payload = vm[3]?
              nested = payload && resolve_clap_item(tree, tree.enum_index, payload, path)
              # A variant whose payload is itself the nested enum is only a
              # path segment; one wrapping an Args struct or inline fields is
              # a command of its own (its flags, and with `Option<_>` it runs).
              unless nested && nested != current_enum
                current_cmds = current_enum_bases.map { |base| "#{base}/#{name}" }
                current_cmds.each { |url| fetch_endpoint(endpoints, url, path, line_no) }
              end
            elsif code.matches?(/^[A-Z]\w*/)
              scanner.consume_command_name
            end
          end

          if (fm = code.match(FIELD_RE)) && !scanner.pending_attrs.empty?
            scanner.pending_attrs.each do |attr|
              current_cmds.each { |url| apply_field(attr, fm[1], url, path, line_no, endpoints) }
            end
            scanner.clear_attrs
          end
        end

        # getopts: bind `let mut opts = Options::new();` to the current
        # binary's root command, then attribute each `opts.optopt(...)` /
        # `optflag(...)` / `optflagopt(...)` / `optmulti(...)` / `reqopt(...)`
        # call to that same receiver via the variable map.
        if nm = line.match(GETOPTS_NEW_RE)
          getopts_vars[nm[1]] = root_url
        end
        if cm = line.match(GETOPTS_CALL_RE)
          if url = getopts_vars[cm[1]]?
            short = cm[2]
            long = cm[3]
            name = long.empty? ? short : long
            fetch_endpoint(endpoints, url, path, line_no).push_param(Param.new(name, "", "flag")) unless name.empty?
          end
        end

        # builtin env reads (gated).
        if emit_env
          line.scan(ENV_VAR_RE) do |env_match|
            fetch_endpoint(endpoints, root_url, path, line_no).push_param(Param.new(env_match[1], "", "env"))
          end
        end

        depth += code.count('{') - code.count('}')
        item_entered = true if item_kind && !item_entered && depth >= item_body_depth
        if item_kind && item_entered && depth < item_body_depth
          item_kind = nil
          item_entered = false
          current_cmds = [root_url]
          scanner.reset_for_new_item
        elsif item_kind == :subcommand && depth == item_body_depth
          current_cmds = current_enum_bases
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
      unquoted_body = body.gsub(/"(?:\\.|[^"\\])*"/, "")
      return if unquoted_body.matches?(/\bsubcommand\b/)
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
        out << {name, Noir::PathScope.expand(File.dirname(path))}
      end
      out.sort_by! { |(_n, dir)| -dir.size }
      out
    end
  end
end
