# Crystal bindings for tree-sitter.
#
# Linked against the system-provided libtree-sitter runtime plus per-grammar
# object files that we vendor under `grammars/<lang>/`. Each grammar ships a
# large auto-generated `parser.c` and a small hand-written `scanner.c`.
#
# The ldflags backtick command auto-compiles each grammar when its source
# files are newer than the corresponding `.o`, mirroring the pattern used in
# sibling project `hwaro/src/ext/stb_bindings.cr`.
#
# Upstream versions currently vendored:
#   tree-sitter-python  v0.23.6

@[Link(ldflags: "`sh #{__DIR__}/build.sh`")]
lib LibTreeSitter
  # ----- Opaque types -----
  type TSParser = Void*
  type TSTree = Void*
  type TSLanguage = Void*
  type TSQuery = Void*
  type TSQueryCursor = Void*

  # ----- Query API error codes (TSQueryError in api.h) -----
  TS_QUERY_ERROR_NONE      = 0
  TS_QUERY_ERROR_SYNTAX    = 1
  TS_QUERY_ERROR_NODE_TYPE = 2
  TS_QUERY_ERROR_FIELD     = 3
  TS_QUERY_ERROR_CAPTURE   = 4
  TS_QUERY_ERROR_STRUCTURE = 5
  TS_QUERY_ERROR_LANGUAGE  = 6

  # ----- Structs exposed by api.h -----
  struct TSPoint
    row : LibC::UInt
    column : LibC::UInt
  end

  struct TSNode
    context : LibC::UInt[4]
    id : Void*
    tree : Void*
  end

  # ----- Parser lifecycle -----
  fun ts_parser_new : TSParser
  fun ts_parser_delete(parser : TSParser)
  fun ts_parser_set_language(parser : TSParser, language : TSLanguage) : Bool
  fun ts_parser_parse_string(parser : TSParser, old_tree : TSTree, string : LibC::Char*, length : LibC::UInt) : TSTree

  # ----- Tree / node -----
  fun ts_tree_delete(tree : TSTree)
  fun ts_tree_root_node(tree : TSTree) : TSNode
  fun ts_node_string(node : TSNode) : LibC::Char*
  fun ts_node_type(node : TSNode) : LibC::Char*
  fun ts_node_child_count(node : TSNode) : LibC::UInt
  fun ts_node_named_child_count(node : TSNode) : LibC::UInt
  fun ts_node_named_child(node : TSNode, index : LibC::UInt) : TSNode
  fun ts_node_child(node : TSNode, index : LibC::UInt) : TSNode
  fun ts_node_child_by_field_name(node : TSNode, name : LibC::Char*, name_length : LibC::UInt) : TSNode
  fun ts_node_start_byte(node : TSNode) : LibC::UInt
  fun ts_node_end_byte(node : TSNode) : LibC::UInt
  fun ts_node_start_point(node : TSNode) : TSPoint
  fun ts_node_end_point(node : TSNode) : TSPoint
  fun ts_node_is_null(node : TSNode) : Bool

  # ----- Query API -----
  struct TSQueryCapture
    node : TSNode
    index : LibC::UInt
  end

  struct TSQueryMatch
    id : LibC::UInt
    pattern_index : UInt16
    capture_count : UInt16
    captures : TSQueryCapture*
  end

  # ----- Query predicates (tree-sitter stores them as metadata; the
  # caller is responsible for enforcing them when iterating matches.) -----
  TS_PREDICATE_STEP_DONE    = 0
  TS_PREDICATE_STEP_CAPTURE = 1
  TS_PREDICATE_STEP_STRING  = 2

  struct TSQueryPredicateStep
    type : LibC::Int
    value_id : LibC::UInt
  end

  fun ts_query_new(language : TSLanguage, source : LibC::Char*, source_len : LibC::UInt,
                   error_offset : LibC::UInt*, error_type : LibC::Int*) : TSQuery
  fun ts_query_delete(query : TSQuery)
  fun ts_query_pattern_count(query : TSQuery) : LibC::UInt
  fun ts_query_capture_count(query : TSQuery) : LibC::UInt
  fun ts_query_capture_name_for_id(query : TSQuery, index : LibC::UInt, length : LibC::UInt*) : LibC::Char*
  fun ts_query_string_value_for_id(query : TSQuery, index : LibC::UInt, length : LibC::UInt*) : LibC::Char*
  fun ts_query_predicates_for_pattern(query : TSQuery, pattern_index : LibC::UInt,
                                      step_count : LibC::UInt*) : TSQueryPredicateStep*
  fun ts_query_cursor_new : TSQueryCursor
  fun ts_query_cursor_delete(cursor : TSQueryCursor)
  fun ts_query_cursor_exec(cursor : TSQueryCursor, query : TSQuery, node : TSNode)
  fun ts_query_cursor_next_match(cursor : TSQueryCursor, match : TSQueryMatch*) : Bool

  # ----- Grammars (linked from vendored parser.o) -----
  fun tree_sitter_python : TSLanguage
  fun tree_sitter_go : TSLanguage
  fun tree_sitter_java : TSLanguage
end

# Thin high-level facade. Keeps tree lifetime tied to an object so callers
# don't have to think about `ts_tree_delete`.
module Noir::TreeSitter
  # Parses `source` with the given `language` and yields the root
  # `LibTreeSitter::TSNode`. The parser and tree are freed when the
  # block returns.
  def self.parse(source : String, language : LibTreeSitter::TSLanguage, &)
    parser = LibTreeSitter.ts_parser_new
    raise "ts_parser_new returned null" if parser.null?
    begin
      unless LibTreeSitter.ts_parser_set_language(parser, language)
        raise "ts_parser_set_language failed (ABI mismatch?)"
      end
      tree = LibTreeSitter.ts_parser_parse_string(parser, Pointer(Void).null.as(LibTreeSitter::TSTree), source.to_unsafe, source.bytesize.to_u32)
      raise "ts_parser_parse_string returned null" if tree.null?
      begin
        yield LibTreeSitter.ts_tree_root_node(tree)
      ensure
        LibTreeSitter.ts_tree_delete(tree)
      end
    ensure
      LibTreeSitter.ts_parser_delete(parser)
    end
  end

  # Parses `source` with the Python grammar and yields the root node.
  def self.parse_python(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_python) { |root| yield root }
  end

  # Parses `source` with the Go grammar and yields the root node.
  def self.parse_go(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_go) { |root| yield root }
  end

  # Parses `source` with the Java grammar and yields the root node.
  def self.parse_java(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_java) { |root| yield root }
  end

  # Convenience: returns the root-node s-expression for `source`.
  def self.python_sexp(source : String) : String
    parse_python(source) do |root|
      ptr = LibTreeSitter.ts_node_string(root)
      begin
        String.new(ptr)
      ensure
        # ts_node_string allocates with malloc; free it.
        LibC.free(ptr.as(Void*))
      end
    end
  end

  # --- Small helpers used by extractors. Kept here so callers don't
  # have to touch LibTreeSitter directly. ---

  def self.node_type(node : LibTreeSitter::TSNode) : String
    String.new(LibTreeSitter.ts_node_type(node))
  end

  def self.node_text(node : LibTreeSitter::TSNode, source : String) : String
    sb = LibTreeSitter.ts_node_start_byte(node).to_i
    eb = LibTreeSitter.ts_node_end_byte(node).to_i
    source.byte_slice(sb, eb - sb)
  end

  def self.node_start_row(node : LibTreeSitter::TSNode) : Int32
    LibTreeSitter.ts_node_start_point(node).row.to_i
  end

  def self.field(node : LibTreeSitter::TSNode, name : String) : LibTreeSitter::TSNode?
    child = LibTreeSitter.ts_node_child_by_field_name(node, name.to_unsafe, name.bytesize.to_u32)
    LibTreeSitter.ts_node_is_null(child) ? nil : child
  end

  # Iterates named children without allocating an array.
  def self.each_named_child(node : LibTreeSitter::TSNode, &)
    count = LibTreeSitter.ts_node_named_child_count(node)
    count.times do |i|
      yield LibTreeSitter.ts_node_named_child(node, i.to_u32)
    end
  end

  # Compiled tree-sitter query.
  #
  # Queries are S-expression patterns that describe node shapes and
  # capture nodes by `@name`. They let detectors declare the shape of
  # a route registration call once instead of hand-walking the AST.
  #
  # Example: match every `@<router>.route(...)` decorator in Python
  # source and capture the router identifier and the path string.
  #
  # ```
  # query = Noir::TreeSitter::Query.new(
  #   LibTreeSitter.tree_sitter_python,
  #   <<-SCM
  #     (decorator
  #       (call
  #         function: (attribute
  #           object: (identifier) @router
  #           attribute: (identifier) @verb
  #           (#eq? @verb "route"))
  #         arguments: (argument_list
  #           (string (string_content) @path))))
  #   SCM
  # )
  # Noir::TreeSitter.parse_python(source) do |root|
  #   query.each_match(root) do |match|
  #     puts "#{Noir::TreeSitter.node_text(match["router"], source)} -> " \
  #          "#{Noir::TreeSitter.node_text(match["path"], source)}"
  #   end
  # end
  # query.close
  # ```
  class Query
    # Raised when a query pattern fails to compile. The message contains
    # the byte offset and the tree-sitter error category.
    class CompileError < Exception
    end

    # Opaque handle; exposed as a struct getter only for internal callers
    # that need to pass the raw pointer to LibTreeSitter functions.
    @handle : LibTreeSitter::TSQuery

    # Cached capture-id → name map. Queries expose capture names by id
    # returned through `TSQueryCapture.index`; we resolve them once at
    # construction time.
    @capture_names : Array(String)

    # Parsed predicate constraint (`#eq?`, `#match?`, …). Each predicate
    # scopes a pattern: a match is only surfaced when every predicate
    # for its pattern evaluates true.
    private record Predicate, name : String, pattern_index : Int32, args : Array(PredicateArg)
    # `regex` is a pre-compiled `Regex` when the argument is a literal
    # pattern on a `#match?` / `#not-match?` predicate. Evaluating many
    # matches against the same query would otherwise reparse the regex
    # on every hit.
    private record PredicateArg, is_capture : Bool, value : String, regex : Regex? = nil

    @predicates_by_pattern : Hash(Int32, Array(Predicate))

    def initialize(language : LibTreeSitter::TSLanguage, source : String)
      error_offset = 0_u32
      error_type = 0
      handle = LibTreeSitter.ts_query_new(
        language,
        source.to_unsafe,
        source.bytesize.to_u32,
        pointerof(error_offset),
        pointerof(error_type),
      )
      if handle.null?
        raise CompileError.new(
          "tree-sitter query failed to compile (code=#{error_type}, byte_offset=#{error_offset})"
        )
      end
      @handle = handle

      # Resolve capture names by id. `ts_query_capture_count` returns how
      # many distinct `@name` captures appear in the query.
      cap_count = LibTreeSitter.ts_query_capture_count(@handle)
      @capture_names = Array(String).new(cap_count.to_i)
      cap_count.times do |i|
        length = 0_u32
        ptr = LibTreeSitter.ts_query_capture_name_for_id(@handle, i.to_u32, pointerof(length))
        @capture_names << (ptr.null? ? "" : String.new(ptr.to_slice(length.to_i)))
      end

      @predicates_by_pattern = parse_predicates
    end

    # Parse predicate steps for every pattern in the query into the
    # structured `Predicate` form that `match_passes_predicates?` can
    # walk cheaply per match.
    private def parse_predicates : Hash(Int32, Array(Predicate))
      result = Hash(Int32, Array(Predicate)).new
      pattern_count = LibTreeSitter.ts_query_pattern_count(@handle)
      pattern_count.times do |pattern_index|
        step_count = 0_u32
        steps_ptr = LibTreeSitter.ts_query_predicates_for_pattern(
          @handle, pattern_index.to_u32, pointerof(step_count)
        )
        next if step_count == 0
        predicates = [] of Predicate
        current_name = ""
        current_args = [] of PredicateArg
        step_count.times do |i|
          step = steps_ptr[i]
          case step.type
          when LibTreeSitter::TS_PREDICATE_STEP_STRING
            length = 0_u32
            ptr = LibTreeSitter.ts_query_string_value_for_id(@handle, step.value_id, pointerof(length))
            text = ptr.null? ? "" : String.new(ptr.to_slice(length.to_i))
            if current_name.empty?
              current_name = text
            else
              # Eagerly compile the regex when this is the pattern arg
              # of a `#match?` / `#not-match?` predicate. Capture-valued
              # patterns (dynamic) can't be pre-compiled and fall back
              # at evaluation time.
              regex =
                if (current_name == "match?" || current_name == "not-match?") && current_args.size == 1
                  begin
                    Regex.new(text)
                  rescue ArgumentError
                    nil
                  end
                end
              current_args << PredicateArg.new(false, text, regex)
            end
          when LibTreeSitter::TS_PREDICATE_STEP_CAPTURE
            current_args << PredicateArg.new(true, @capture_names[step.value_id.to_i]? || "")
          when LibTreeSitter::TS_PREDICATE_STEP_DONE
            unless current_name.empty?
              predicates << Predicate.new(current_name, pattern_index.to_i, current_args)
            end
            current_name = ""
            current_args = [] of PredicateArg
          end
        end
        result[pattern_index.to_i] = predicates unless predicates.empty?
      end
      result
    end

    # Resolve the node text a predicate arg refers to. For capture args
    # we look up the capture on the current match; for string args the
    # stored literal is used as-is.
    private def resolve_arg(arg : PredicateArg, match_captures : Hash(String, LibTreeSitter::TSNode), source_text : String) : String?
      if arg.is_capture
        if node = match_captures[arg.value]?
          return Noir::TreeSitter.node_text(node, source_text)
        end
        nil
      else
        arg.value
      end
    end

    # Evaluate every predicate on the given pattern against `match_captures`.
    # Returns false if any predicate fails; unsupported predicate names
    # are treated as passing (consistent with tree-sitter grep behaviour
    # for unknown directives).
    private def match_passes_predicates?(pattern_index : Int32,
                                         match_captures : Hash(String, LibTreeSitter::TSNode),
                                         source_text : String) : Bool
      preds = @predicates_by_pattern[pattern_index]?
      return true unless preds
      preds.all? do |pred|
        case pred.name
        when "eq?", "not-eq?"
          next true if pred.args.size < 2
          lhs = resolve_arg(pred.args[0], match_captures, source_text)
          rhs = resolve_arg(pred.args[1], match_captures, source_text)
          equal = lhs == rhs
          pred.name == "eq?" ? equal : !equal
        when "match?", "not-match?"
          next true if pred.args.size < 2
          text = resolve_arg(pred.args[0], match_captures, source_text)
          next true if text.nil?
          pattern_arg = pred.args[1]
          # Prefer the eagerly-compiled regex cached on the predicate
          # arg. Falls back to runtime compilation only when the pattern
          # itself is a capture reference.
          re = pattern_arg.regex
          if re.nil?
            pattern = resolve_arg(pattern_arg, match_captures, source_text)
            next true if pattern.nil?
            re =
              begin
                Regex.new(pattern)
              rescue ArgumentError
                nil
              end
            next true if re.nil?
          end
          matched = !!(text =~ re)
          pred.name == "match?" ? matched : !matched
        when "any-of?", "not-any-of?"
          text = resolve_arg(pred.args[0], match_captures, source_text)
          next true if text.nil?
          # Index-range iteration avoids allocating a slice on every
          # match the way `pred.args[1..].any?` would.
          found = (1...pred.args.size).any? do |i|
            resolve_arg(pred.args[i], match_captures, source_text) == text
          end
          pred.name == "any-of?" ? found : !found
        else
          true # unknown predicate — let the match through
        end
      end
    end

    # Free the underlying TSQuery. Safe to call multiple times; subsequent
    # calls are no-ops.
    def close
      return if @handle.null?
      LibTreeSitter.ts_query_delete(@handle)
      @handle = Pointer(Void).null.as(LibTreeSitter::TSQuery)
    end

    def finalize
      close
    end

    # Runs the query against `node` and yields one `Hash(String, TSNode)`
    # per match. `source_text` is the string that was parsed to produce
    # the tree, needed to resolve captured node text when evaluating
    # predicates like `#eq?` / `#match?`. When a pattern captures the
    # same name multiple times, the last match wins; use `each_match_raw`
    # for the full capture list.
    def each_match(node : LibTreeSitter::TSNode,
                   source_text : String,
                   & : Hash(String, LibTreeSitter::TSNode) ->)
      cursor = LibTreeSitter.ts_query_cursor_new
      begin
        LibTreeSitter.ts_query_cursor_exec(cursor, @handle, node)
        match = uninitialized LibTreeSitter::TSQueryMatch
        while LibTreeSitter.ts_query_cursor_next_match(cursor, pointerof(match))
          count = match.capture_count.to_i
          captures = Hash(String, LibTreeSitter::TSNode).new(initial_capacity: count)
          count.times do |i|
            cap = match.captures[i]
            name = @capture_names[cap.index.to_i]? || ""
            captures[name] = cap.node
          end
          next unless match_passes_predicates?(match.pattern_index.to_i, captures, source_text)
          yield captures
        end
      ensure
        LibTreeSitter.ts_query_cursor_delete(cursor)
      end
    end

    # Lower-level variant: yields `(pattern_index, Array({capture_name, TSNode}))`
    # so callers can disambiguate multiple captures sharing a name, and
    # know which pattern in a multi-pattern query matched.
    def each_match_raw(node : LibTreeSitter::TSNode,
                       source_text : String,
                       & : Int32, Array(Tuple(String, LibTreeSitter::TSNode)) ->)
      cursor = LibTreeSitter.ts_query_cursor_new
      begin
        LibTreeSitter.ts_query_cursor_exec(cursor, @handle, node)
        match = uninitialized LibTreeSitter::TSQueryMatch
        while LibTreeSitter.ts_query_cursor_next_match(cursor, pointerof(match))
          count = match.capture_count.to_i
          caps = Array(Tuple(String, LibTreeSitter::TSNode)).new(count)
          captures = Hash(String, LibTreeSitter::TSNode).new(initial_capacity: count)
          count.times do |i|
            cap = match.captures[i]
            name = @capture_names[cap.index.to_i]? || ""
            caps << {name, cap.node}
            captures[name] = cap.node
          end
          next unless match_passes_predicates?(match.pattern_index.to_i, captures, source_text)
          yield match.pattern_index.to_i, caps
        end
      ensure
        LibTreeSitter.ts_query_cursor_delete(cursor)
      end
    end
  end
end

lib LibC
  fun free(ptr : Void*)
end
