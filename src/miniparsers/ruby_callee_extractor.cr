require "../models/endpoint"
require "../ext/tree_sitter/tree_sitter"
require "./callee_extractor_base"

module Noir::RubyCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  RESERVED = Set{
    "alias", "and", "begin", "break", "case", "class", "def",
    "defined?", "do", "else", "elsif", "end", "ensure", "false",
    "for", "if", "in", "module", "next", "nil", "not", "or",
    "redo", "rescue", "retry", "return", "self", "super", "then",
    "true", "undef", "unless", "until", "when", "while", "yield",
  }

  RAILS_FORMAT_CALLS = Set{"html", "json", "js", "xml", "rss", "atom", "turbo_stream", "api"}
  RAILS_RESPONSE_DSL = Set{"respond_to"}
  REQUEST_ACCESSORS  = Set{"get", "post", "put", "patch", "delete", "xhr", "xhr?", "remote_ip", "raw_post"}
  ATTRIBUTE_READERS  = Set{
    "id", "ids", "uuid", "guid", "token", "key",
    "name", "username", "title", "description", "text", "body", "message",
    "url", "uri", "path", "email", "status", "state", "type", "role",
    "score", "size", "length", "first", "last", "active",
    "attributes", "safe_attributes", "password", "password_confirmation", "scheme_name",
  }

  # Nodes a receiver chain can start with: `user`, `User`, `@user`, `@@x`,
  # `self`, `Admin::Health`.
  CHAIN_HEADS = Set{"identifier", "constant", "instance_variable", "class_variable", "self", "scope_resolution"}

  # What a name with no receiver and no arguments must be followed by on
  # its line to read as a call: `authenticate! if x`, `foo bar`.
  COMMAND_TAIL = /\A[ \t]+(?:[:'"]|@{1,2}[A-Za-z_]|[A-Za-z_])/

  # The callees of a method or block body given as text, `start_line` being
  # the 1-based file line its first line sits on.
  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    hits = [] of {Int32, Int32, Int32, String}
    body = close_masked_heredocs(body)
    Noir::TreeSitter.parse_ruby(body) { |root| collect(root, body, hits, locals_in(root, body)) }
    finish(hits, file_path, start_line - 1)
  rescue
    [] of Entry
  end

  HEREDOC_OPENER = /<<[~-]?(["'`]?)([A-Za-z_]\w*)\1/

  # Bodies cut from `RubyEngine#ruby_source` text have their heredocs
  # blanked out, terminator included, which leaves `<<~SQL` opening a
  # heredoc that swallows the rest of the body. Such an opener reads as an
  # empty string of the same width.
  # ponytail: a `x<<y` shift with no `y` line below reads as a string too.
  private def close_masked_heredocs(body : String) : String
    return body unless body.includes?("<<")
    body.gsub(HEREDOC_OPENER) do |opener, match|
      terminator = match[2]
      body.each_line.any?(&.strip.==(terminator)) ? opener : %("#{" " * (opener.size - 2)}")
    end
  end

  # The callees of every `def` in `source` (a whole file), by method name;
  # a later `def` of one name replaces an earlier one, as Ruby does.
  def callees_by_method(source : String, file_path : String) : Hash(String, Array(Entry))
    result = Hash(String, Array(Entry)).new
    Noir::TreeSitter.parse_ruby(source) { |root| each_method(root, source, file_path, result) }
    result
  rescue
    Hash(String, Array(Entry)).new
  end

  private def each_method(node : LibTreeSitter::TSNode, source : String, file_path : String, result : Hash(String, Array(Entry)))
    Noir::TreeSitter.each_named_child(node) do |child|
      case Noir::TreeSitter.node_type(child)
      when "method", "singleton_method"
        next unless name = Noir::TreeSitter.field(child, "name")
        hits = [] of {Int32, Int32, Int32, String}
        locals = locals_in(child, source)
        Noir::TreeSitter.each_named_child(child) do |part|
          next if part.id == name.id || Noir::TreeSitter.node_type(part) == "method_parameters" ||
                  Noir::TreeSitter.field(child, "object").try(&.id) == part.id
          collect(part, source, hits, locals)
        end
        callees = finish(hits, file_path, 0)
        result[Noir::TreeSitter.node_text(name, source)] = callees unless callees.empty?
      else
        each_method(child, source, file_path, result)
      end
    end
  end

  # Sorted the way a reader of the line sees them: by line, receiver
  # chains before bare calls, then left to right.
  private def finish(hits : Array({Int32, Int32, Int32, String}), file_path : String, row_offset : Int32) : Array(Entry)
    hits.sort_by! { |row, kind, col, _| {row, kind, col} }
    hits.map { |row, _, _, name| {name, file_path, row + row_offset + 1} }.uniq!
  end

  private def collect(node : LibTreeSitter::TSNode, source : String, hits : Array({Int32, Int32, Int32, String}), locals : Set(String))
    case Noir::TreeSitter.node_type(node)
    when "call"
      receiver = Noir::TreeSitter.field(node, "receiver")
      if receiver.nil?
        bare_call(node, source, hits)
      elsif !chain_link?(node)
        chain_runs(node, source, hits)
      end
    when "identifier"
      unless method_name?(node) || locals.includes?(Noir::TreeSitter.node_text(node, source))
        command_name(node, node, source, hits)
      end
    end
    Noir::TreeSitter.each_named_child(node) { |child| collect(child, source, hits, locals) }
  end

  PARAMETER_LISTS = Set{"method_parameters", "block_parameters", "lambda_parameters"}

  # The local variables `node` declares: assigned names, parameters and
  # `rescue => e`. A bare name among them is a variable read, not a call.
  private def locals_in(node : LibTreeSitter::TSNode, source : String) : Set(String)
    locals = Set(String).new
    Noir::TreeSitter.walk(node) do |child|
      case Noir::TreeSitter.node_type(child)
      when "assignment", "operator_assignment"
        Noir::TreeSitter.field(child, "left").try { |left| add_names(left, source, locals) }
      when "exception_variable", "left_assignment_list", "destructured_left_assignment", "destructured_parameter"
        add_names(child, source, locals)
      else
        next unless PARAMETER_LISTS.includes?(Noir::TreeSitter.node_type(child))
        Noir::TreeSitter.each_named_child(child) do |param|
          if Noir::TreeSitter.node_type(param) == "identifier"
            locals << Noir::TreeSitter.node_text(param, source)
          elsif name = Noir::TreeSitter.field(param, "name")
            locals << Noir::TreeSitter.node_text(name, source)
          end
        end
      end
    end
    locals
  end

  private def add_names(node : LibTreeSitter::TSNode, source : String, locals : Set(String))
    if Noir::TreeSitter.node_type(node) == "identifier"
      locals << Noir::TreeSitter.node_text(node, source)
    else
      Noir::TreeSitter.each_named_child(node) { |child| add_names(child, source, locals) if Noir::TreeSitter.node_type(child).in?("identifier", "rest_assignment", "destructured_left_assignment") }
    end
  end

  # `foo(x)`, `foo x`, `foo do ... end`: a call with no receiver. With
  # neither arguments nor a block it is a call only by what follows it.
  private def bare_call(node : LibTreeSitter::TSNode, source : String, hits : Array({Int32, Int32, Int32, String}))
    return unless method = Noir::TreeSitter.field(node, "method")
    return unless Noir::TreeSitter.node_type(method) == "identifier"
    if Noir::TreeSitter.field(node, "arguments") || Noir::TreeSitter.field(node, "block")
      push_bare(method, source, hits)
    else
      command_name(method, node, source, hits)
    end
  end

  private def command_name(name : LibTreeSitter::TSNode, node : LibTreeSitter::TSNode, source : String, hits : Array({Int32, Int32, Int32, String}))
    tail_start = LibTreeSitter.ts_node_end_byte(node).to_i
    tail = source.byte_slice?(tail_start, 64) || ""
    push_bare(name, source, hits) if tail.matches?(COMMAND_TAIL)
  end

  private def push_bare(name : LibTreeSitter::TSNode, source : String, hits : Array({Int32, Int32, Int32, String}))
    text = Noir::TreeSitter.node_text(name, source)
    return unless text.matches?(/\A[a-z_]/)
    return if skip_callee?(text)
    point = LibTreeSitter.ts_node_start_point(name)
    hits << {point.row.to_i, 1, point.column.to_i, text}
  end

  # The `method` field of a call, or a name a declaration introduces.
  private def method_name?(node : LibTreeSitter::TSNode) : Bool
    return true unless parent = Noir::TreeSitter.parent(node)
    case Noir::TreeSitter.node_type(parent)
    when "call"
      Noir::TreeSitter.field(parent, "method").try(&.id) == node.id
    when "method", "singleton_method", "alias", "undef"
      true
    else
      false
    end
  end

  # A call that is the receiver of another call: its chain is read from
  # the outermost call.
  private def chain_link?(node : LibTreeSitter::TSNode) : Bool
    return false unless parent = Noir::TreeSitter.parent(node)
    Noir::TreeSitter.node_type(parent) == "call" && Noir::TreeSitter.field(parent, "receiver").try(&.id) == node.id
  end

  # The runs of plain names in a receiver chain, each one a callee:
  # `User.find(id).posts.create(x)` holds `User.find` and `posts.create`.
  # A link with arguments or a block ends a run; `a&.b` reads as `a.b`.
  private def chain_runs(top : LibTreeSitter::TSNode, source : String, hits : Array({Int32, Int32, Int32, String}))
    links = [] of LibTreeSitter::TSNode
    node = top
    while Noir::TreeSitter.node_type(node) == "call" && (receiver = Noir::TreeSitter.field(node, "receiver")) && links.size < 256
      links << node
      node = receiver
    end
    links.reverse!
    run = [] of String
    run_col = 0
    if head = chain_head(node, source)
      run << head
      run_col = LibTreeSitter.ts_node_start_point(node).column.to_i
    end
    links.each do |link|
      method = Noir::TreeSitter.field(link, "method")
      unless method && Noir::TreeSitter.node_type(method).in?("identifier", "constant")
        run.clear
        next
      end
      run_col = LibTreeSitter.ts_node_start_point(method).column.to_i if run.empty?
      run << Noir::TreeSitter.node_text(method, source)
      args = Noir::TreeSitter.field(link, "arguments")
      next unless args || Noir::TreeSitter.field(link, "block")
      push_run(run, run_col, method, !!args.try { |list| Noir::TreeSitter.node_text(list, source).starts_with?('(') }, hits)
      run.clear
    end
    if last = links.last?.try { |link| Noir::TreeSitter.field(link, "method") }
      push_run(run, run_col, last, false, hits)
    end
  end

  private def push_run(run : Array(String), col : Int32, method : LibTreeSitter::TSNode, has_parens : Bool, hits : Array({Int32, Int32, Int32, String}))
    return if run.size < 2
    name = run.join('.')
    return if skip_callee?(name, has_parens)
    hits << {Noir::TreeSitter.node_start_row(method), 0, col, name}
  end

  private def chain_head(node : LibTreeSitter::TSNode, source : String) : String?
    type = Noir::TreeSitter.node_type(node)
    return unless CHAIN_HEADS.includes?(type)
    text = Noir::TreeSitter.node_text(node, source).lchop("::")
    return if type == "scope_resolution" && !text.matches?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)
    text
  end

  private def skip_callee?(name : String, has_parens : Bool = false) : Bool
    return true if name.empty?

    last = name.split('.').last
    return true if RESERVED.includes?(last)
    return true if RAILS_RESPONSE_DSL.includes?(last)
    return true if request_accessor_callee?(name, last)
    return true if rails_format_callee?(name, last, has_parens)
    return true if attribute_reader_callee?(name, last, has_parens)

    false
  end

  private def rails_format_callee?(name : String, last : String, has_parens : Bool) : Bool
    return false if has_parens
    name.starts_with?("format.") && RAILS_FORMAT_CALLS.includes?(last)
  end

  private def request_accessor_callee?(name : String, last : String) : Bool
    name.starts_with?("request.") && REQUEST_ACCESSORS.includes?(last)
  end

  private def attribute_reader_callee?(name : String, last : String, has_parens : Bool) : Bool
    return false if has_parens
    return false if name.starts_with?("response.")
    return false if last.ends_with?("?") || last.ends_with?("!") || last.ends_with?("=")
    ATTRIBUTE_READERS.includes?(last) ||
      last.starts_with?("is_") ||
      last.ends_with?("_id") ||
      last.ends_with?("_ids") ||
      last.ends_with?("_ip") ||
      last.ends_with?("_name") ||
      last.ends_with?("_at") ||
      last.ends_with?("_attributes")
  end

  def strip_comment(line : String, preserve_strings : Bool = false) : String
    # Fast path: the per-char rebuild below only ever diverges from the input
    # when the line carries a `#` comment (either mode) or, with
    # `preserve_strings: false`, a string literal whose interior is blanked.
    # With `preserve_strings: true` a `#`-free line maps to itself; with
    # `preserve_strings: false` it must also be quote-free. When none of the
    # relevant trigger bytes are present, skip the String::Builder allocation
    # entirely. `#`/`'`/`"` are single-byte ASCII that can never appear inside
    # a UTF-8 multibyte sequence, so raw byte_index scans (memchr) are both
    # correct and allocation-free. This is the hot path — every Ruby analyzer
    # runs strip_comment on every line, most of which need no rewrite.
    if preserve_strings
      return line unless line.byte_index(0x23_u8) # '#'
    else
      # '#', '\'' or '"' anywhere forces the rewrite; otherwise it's identity.
      return line unless line.byte_index(0x23_u8) || line.byte_index(0x27_u8) || line.byte_index(0x22_u8)
    end

    stripped = String::Builder.new
    in_string = false
    escaped = false
    quote = '\0'

    line.each_char do |char|
      if in_string
        if escaped
          stripped << (preserve_strings ? char : ' ')
          escaped = false
        elsif char == '\\'
          stripped << (preserve_strings ? char : ' ')
          escaped = true
        elsif char == quote
          stripped << char
          in_string = false
        else
          stripped << (preserve_strings ? char : ' ')
        end
      elsif char == '"' || char == '\''
        in_string = true
        quote = char
        stripped << char
      elsif char == '#'
        return stripped.to_s
      else
        stripped << char
      end
    end

    stripped.to_s
  end
end
