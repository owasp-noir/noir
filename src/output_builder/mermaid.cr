require "../models/output_builder"
require "../models/endpoint"
require "../models/passive_scan"

class OutputBuilderMermaid < OutputBuilder
  def print(endpoints : Array(Endpoint))
    build_mindmap(endpoints)
  end

  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    build_mindmap(endpoints, passive_results)
  end

  private def build_mindmap(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult) = [] of PassiveScanResult)
    ob_puts "mindmap"
    ob_puts "  root((API))"

    # Build hierarchical structure
    tree = build_path_tree(endpoints)

    # Output the tree with proper formatting
    output_tree(tree, 2)

    # Output passive scan findings as a separate branch
    output_passive_results(passive_results, 2)
  end

  private def output_passive_results(passive_results : Array(PassiveScanResult), indent : Int32)
    return if passive_results.empty?

    branch_indent = "  " * indent
    ob_puts "#{branch_indent}passive"
    passive_results.each do |result|
      finding_indent = "  " * (indent + 1)
      location = "#{result.file_path}:#{result.line_number}"
      label = "#{result.id} [#{result.info.severity}] #{location}"
      ob_puts "#{finding_indent}#{sanitize_label(label)}"
    end
  end

  # Simple tree node structure
  class TreeNode
    property children : Hash(String, TreeNode)
    property endpoints : Array(Endpoint)

    def initialize
      @children = {} of String => TreeNode
      @endpoints = [] of Endpoint
    end
  end

  private def build_path_tree(endpoints : Array(Endpoint))
    root = TreeNode.new
    endpoints.each do |endpoint|
      # Parse the URL path
      path = endpoint.url
      # A CLI command surface (`cli://tool/serve`) is not an HTTP path:
      # group it as cli -> tool -> serve instead of leaving the scheme as
      # a mangled `cli_` segment.
      path = path.sub("cli://", "cli/") if endpoint.cli?
      # A realtime event surface (`ws://chatHub/SendMessage`) is not an HTTP
      # path: group it as ws -> chatHub -> SendMessage instead of leaving the
      # scheme as a mangled `ws_` segment.
      path = path.sub("wss://", "wss/").sub("ws://", "ws/") if endpoint.realtime?
      # Remove query parameters if any
      if path.includes?("?")
        path = path.split("?")[0]
      end
      # Handle root path
      if path == "/" || path == ""
        root.endpoints << endpoint
        next
      end
      # Split path into segments
      segments = path.split("/").reject(&.empty?)
      # Navigate/create tree structure
      current_node = root
      segments.each do |segment|
        # Sanitize segment for Mermaid compatibility (path-param aware)
        sanitized_segment = sanitize_path_segment(segment)
        if !current_node.children.has_key?(sanitized_segment)
          current_node.children[sanitized_segment] = TreeNode.new
        end
        current_node = current_node.children[sanitized_segment]
      end
      # Add endpoint to the final node
      current_node.endpoints << endpoint
    end
    root
  end

  # General-purpose Mermaid mindmap label sanitizer for free-text node
  # labels (header / cookie / parameter names, passive findings). Mermaid
  # treats (), [], {} as node-shape syntax, so anything outside Unicode
  # letters/digits/underscore is collapsed to `_`. \p{L}\p{N} keeps CJK /
  # accented text intact — an ASCII-only class turned `사용자` into `___`,
  # destroying the label.
  private def sanitize_label(text : String) : String
    sanitized = text.gsub(/[^\p{L}\p{N}_]/, "_")
    # Mindmap node ids can't lead with a digit.
    sanitized = "path_#{sanitized}" if sanitized =~ /^\d/
    # Ensure non-empty.
    sanitized.empty? ? "unnamed" : sanitized
  end

  # Sanitize a single URL path segment. Path parameters are spelled many
  # ways across frameworks — `{id}` (OpenAPI), `:id` (Sinatra / Rails /
  # Express), `*path` (named splat) and a bare `*` (splat / wildcard).
  # Normalize every form to a `param_<name>` node so the mindmap marks the
  # segment as a path parameter consistently, instead of leaking `:id` as
  # `_id` and `*` as `_`, which erased that meaning entirely.
  private def sanitize_path_segment(segment : String) : String
    if md = segment.match(/^\{(.+)\}$/) || segment.match(/^:(.+)$/) || segment.match(/^\*(.+)$/)
      return "param_#{sanitize_label(md[1])}"
    end
    return "param_wildcard" if segment == "*"
    sanitize_label(segment)
  end

  # Render one parameter group (headers / cookies / query / body / path or
  # a CLI bucket) as a labeled sub-node followed by its sorted members.
  # A no-op for empty buckets so absent locations don't clutter the map.
  private def render_param_group(bucket : Hash(String, String), label : String, indent : Int32)
    return if bucket.empty?

    group_indent = "  " * (indent + 1)
    ob_puts "#{group_indent}#{label}"
    item_indent = "  " * (indent + 2)
    bucket.keys.sort!.each do |name|
      ob_puts "#{item_indent}#{sanitize_label(name)}"
    end
  end

  private def output_tree(node : TreeNode, indent : Int32)
    # Output endpoints for this node
    node.endpoints.each do |endpoint|
      indent_str = "  " * indent
      # Label the node with the HTTP method, tagging websockets. The
      # protocol field is "ws" everywhere else in the codebase (analyzers,
      # common output, websocket tagger). NB: the tag is a bare ` websocket`
      # word, NOT `[websocket]` — in a mindmap `[...]` is node-shape syntax,
      # so `GET [websocket]` renders as a square node showing only
      # "websocket" with the method silently dropped.
      endpoint_label = endpoint.method
      endpoint_label += " websocket" if endpoint.protocol == "ws"
      ob_puts "#{indent_str}#{endpoint_label}"

      # Group parameters by their real request location. Each location is
      # attack-surface-distinct, so it gets its own group instead of being
      # flattened into one "body" bucket — the old merge also silently
      # overwrote same-named params across locations (a `token` query param
      # and a `token` json field collapsed into a single node).
      params_hash = endpoint.params_to_hash

      render_param_group(params_hash["header"], "headers", indent)
      render_param_group(params_hash["cookie"], "cookies", indent)
      render_param_group(params_hash["query"], "query", indent)

      # `body` covers both JSON and form payloads: both are request-body
      # namespaces and (unlike query vs body) a request never carries both.
      body_params = {} of String => String
      params_hash["json"].each { |key, value| body_params[key] = value }
      params_hash["form"].each { |key, value| body_params[key] = value }
      render_param_group(body_params, "body", indent)

      # Path params get their own group. The tree already shows each path
      # parameter as a `param_*` segment (its position in the URL); this
      # group names the params the endpoint reads, which is complementary.
      render_param_group(params_hash["path"], "path", indent)

      # CLI inputs (protocol "cli") live outside the six canonical HTTP
      # buckets — render flags / positional arguments / env reads as their
      # own groups so they aren't silently dropped from the mindmap.
      {"flag" => "flags", "argument" => "arguments", "env" => "env"}.each do |param_type, label|
        bucket = params_hash[param_type]?
        render_param_group(bucket, label, indent) unless bucket.nil?
      end
    end

    # Output children nodes recursively
    sorted_keys = node.children.keys.sort!
    sorted_keys.each do |segment|
      indent_str = "  " * indent
      ob_puts "#{indent_str}#{segment}"
      output_tree(node.children[segment], indent + 1)
    end
  end
end
