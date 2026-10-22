require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../utils/top_level_split"
require "../../../utils/url_path"

module Analyzer::Rust
  # Leptos `#[server]` functions. The `server_fn` macro mounts each one at
  # `{prefix}/{endpoint}`: `prefix` defaults to `/api` and `endpoint` to the
  # function name. With no explicit `endpoint` the macro also appends an
  # xxhash of `CARGO_MANIFEST_DIR` and the module path — that depends on the
  # directory the binary was built in, so it is left off and the URL carries
  # the stable part only.
  #
  # Arguments come in two spellings: the legacy positional
  # `#[server(StructName, "/prefix", "Encoding", "endpoint")]` and the keyed
  # `#[server(prefix = "/p", endpoint = "e", input = GetUrl)]`. The `input`
  # (or legacy encoding, or `protocol`) codec decides the method; every
  # function argument is a field of the request.
  class Leptos < RustEngine
    analyzer_for "rust_leptos"

    protected def crate_dependencies : Array(String)
      ["leptos"]
    end

    ARG_RULES = Noir::TopLevelSplit::Rules.new(
      nest: Noir::TopLevelSplit::Nest::Paren | Noir::TopLevelSplit::Nest::Bracket |
            Noir::TopLevelSplit::Nest::Brace | Noir::TopLevelSplit::Nest::Angle,
      quotes: "\"")

    SERVER_ATTR_RE = /#\s*\[\s*(?:\w+\s*::\s*)*server\b/
    # server_fn lowercases a legacy encoding before matching it (`"getjson"`).
    CODEC_VERB_RE = /\b(get|delete|patch|put|websocket)/i
    # Dioxus `name: Type` server-side extractors, not URL configuration.
    EXTRACTOR_ARG_RE = /\A\w+\s*:(?!:)/
    POSITIONAL_KEYS  = {"name", "prefix", "encoding", "endpoint"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      return endpoints unless file_has_routes?(source)

      include_callee = callees_needed?
      test_regions = RustEngine.collect_cfg_test_regions(source)
      Noir::TreeSitter.parse_rust(source) do |root|
        each_routing_pair(root) do |attr, function|
          next if RustEngine.inside_test_region?(attr, test_regions)
          name = attribute_name(attr, source) || next
          endpoint = route_endpoint(name, attr, function, source) || next
          endpoint.details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(attr) + 1))
          attach_handler_callees(function, source, path, endpoint) if include_callee
          endpoints << endpoint
        end
      end
      endpoints
    end

    protected def file_has_routes?(source : String) : Bool
      source.matches?(SERVER_ATTR_RE)
    end

    # Default `input` codec of a bare `#[server]`: Leptos posts a urlencoded
    # form (`PostUrl`).
    protected def default_body_location : String
      "form"
    end

    protected def route_endpoint(name : String, attr : LibTreeSitter::TSNode,
                                 function : LibTreeSitter::TSNode, source : String) : Endpoint?
      return unless name == "server"
      fn_name = Noir::TreeSitter.field(function, "name").try { |n| Noir::TreeSitter.node_text(n, source) } || return

      keyed = server_args(attribute_arguments(attr, source))
      prefix = keyed["prefix"]? || "/api"
      # An empty endpoint falls back to the generated one, as in server_fn.
      url = Noir::URLPath.join_rooted(prefix, keyed["endpoint"]?.presence || fn_name)

      codec = keyed["input"]? || keyed["encoding"]? || keyed["protocol"]?
      verb = codec.try(&.match(CODEC_VERB_RE)).try(&.[1])
      # A websocket server fn upgrades a GET; its arguments are a message
      # stream, not request fields.
      if verb.try(&.downcase) == "websocket"
        endpoint = Endpoint.new(url, "GET")
        endpoint.protocol = "ws"
        return endpoint
      end
      method = verb.try(&.upcase) || "POST"
      location =
        if method.in?("GET", "DELETE")
          "query"
        elsif codec.nil?
          default_body_location
        elsif codec.matches?(/Url|Multipart/i)
          "form"
        else
          "json"
        end

      params = function_args(function, source).map { |arg| Param.new(arg, "", location) }
      Endpoint.new(url, method, params)
    end

    # `#[server(...)]` arguments as `key => value`, string values unquoted.
    # Positional arguments are mapped onto `name`, `prefix`, `encoding` and
    # `endpoint` in that order, which is the legacy macro's signature.
    protected def server_args(arguments : Array(String)) : Hash(String, String)
      args = {} of String => String
      arguments.each_with_index do |arg, idx|
        next if arg.matches?(EXTRACTOR_ARG_RE)
        if m = arg.match(/\A(\w+)\s*=\s*(.+)\z/m)
          args[m[1]] = unquote(m[2])
        elsif key = POSITIONAL_KEYS[idx]?
          args[key] = unquote(arg)
        end
      end
      args
    end

    protected def unquote(value : String) : String
      value = value.strip
      value.size >= 2 && value.starts_with?('"') && value.ends_with?('"') ? value[1...-1] : value
    end

    # Last path segment of the attribute (`server` for `#[leptos::server]`).
    private def attribute_name(attr_item : LibTreeSitter::TSNode, source : String) : String?
      attr = find_named_child(attr_item, "attribute") || return
      Noir::TreeSitter.each_named_child(attr) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          return Noir::TreeSitter.node_text(child, source).split("::").last.strip
        end
      end
      nil
    end

    # The attribute's argument list split at top-level commas; empty for a
    # bare `#[server]`. Comments are cut out by their node ranges — a regex
    # would also cut the `//` in `"/a//b"`.
    protected def attribute_arguments(attr_item : LibTreeSitter::TSNode, source : String) : Array(String)
      attr = find_named_child(attr_item, "attribute")
      arguments = attr && Noir::TreeSitter.field(attr, "arguments")
      return [] of String unless arguments

      start = LibTreeSitter.ts_node_start_byte(arguments).to_i
      text = String.build do |io|
        pos = start + 1
        Noir::TreeSitter.each_named_child(arguments) do |child|
          next unless Noir::TreeSitter.node_type(child).ends_with?("comment")
          from = LibTreeSitter.ts_node_start_byte(child).to_i
          io << source.byte_slice(pos, from - pos)
          pos = LibTreeSitter.ts_node_end_byte(child).to_i
        end
        io << source.byte_slice(pos, LibTreeSitter.ts_node_end_byte(arguments).to_i - 1 - pos)
      end
      Noir::TopLevelSplit.split(text, ',', ARG_RULES).reject(&.empty?)
    end

    # Names of the function's plain `name: Type` parameters. Destructuring
    # patterns have no single field name and are skipped.
    protected def function_args(function : LibTreeSitter::TSNode, source : String) : Array(String)
      names = [] of String
      parameters = Noir::TreeSitter.field(function, "parameters") || return names
      Noir::TreeSitter.each_named_child(parameters) do |param|
        next unless Noir::TreeSitter.node_type(param) == "parameter"
        pattern = Noir::TreeSitter.field(param, "pattern") || next
        # `mut x` binds `x`; `r#type` is serialised as `type`; `_` is no field.
        name = Noir::TreeSitter.node_text(pattern, source).sub(/\Amut\s+/, "").lchop("r#")
        names << name if name != "_" && name.matches?(/\A[A-Za-z_]\w*\z/)
      end
      names
    end
  end
end
