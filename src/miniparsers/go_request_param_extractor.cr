require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./go_callee_extractor"

module Noir::GoRequestParamExtractor
  extend self

  MAX_HELPER_DEPTH = 3

  def package_function_bodies_for_dirs(file_contents : Hash(String, String),
                                       dirs : Set(String)) : Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody))
    bodies = Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody)).new
    return bodies if dirs.empty?

    file_contents.each do |path, content|
      dir = File.dirname(path)
      next unless dirs.includes?(dir)
      next unless content.includes?("func ")
      fns = Noir::GoCalleeExtractor.collect_function_bodies(content, path)
      next if fns.empty?
      bodies[dir] ||= Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      fns.each { |name, fb| bodies[dir][name] ||= fb }
    end

    bodies
  end

  def package_method_bodies_for_dirs(file_contents : Hash(String, String),
                                     dirs : Set(String)) : Hash(String, Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)))
    bodies = Hash(String, Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))).new
    return bodies if dirs.empty?

    file_contents.each do |path, content|
      dir = File.dirname(path)
      next unless dirs.includes?(dir)
      next unless content.includes?("func (")
      methods = Noir::GoCalleeExtractor.collect_method_bodies(content, path)
      next if methods.empty?
      dir_map = (bodies[dir] ||= Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)).new)
      methods.each do |name, list|
        (dir_map[name] ||= [] of Noir::GoCalleeExtractor::FunctionBody).concat(list)
      end
    end

    bodies
  end

  def function_bodies_for_directory(package_bodies : Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody)),
                                    dir : String) : Hash(String, Noir::GoCalleeExtractor::FunctionBody)
    package_bodies[dir]? || Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
  end

  def method_bodies_for_directory(package_bodies : Hash(String, Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))),
                                  dir : String) : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))
    package_bodies[dir]? || Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)).new
  end

  def params_for_routes(source : String,
                        route_rows : Set(Int32),
                        route_methods : Hash(Int32, String),
                        external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                        external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))) : Hash(Int32, Array(Param))
    by_route = Hash(Int32, Array(Param)).new
    return by_route if route_rows.empty?

    cache = Hash(String, Array(Param)).new
    Noir::TreeSitter.parse_go(source) do |root|
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        row = Noir::TreeSitter.node_start_row(node)
        next unless route_rows.includes?(row)

        http_method = route_methods[row]? || ""
        params = [] of Param
        find_handler_args(node).each do |handler_arg|
          collect_params_for_handler_arg(
            unwrap_handler_arg(handler_arg, source),
            source,
            http_method,
            external_functions,
            external_methods,
            cache,
            Set(String).new,
            params
          )
        end
        by_route[row] = dedupe_params(params) unless params.empty?
      end
    end

    by_route
  end

  private def collect_params_for_handler_arg(handler_arg : LibTreeSitter::TSNode,
                                             source : String,
                                             http_method : String,
                                             external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                             external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                             cache : Hash(String, Array(Param)),
                                             visiting : Set(String),
                                             sink : Array(Param))
    case Noir::TreeSitter.node_type(handler_arg)
    when "func_literal"
      if body = Noir::TreeSitter.field(handler_arg, "body")
        collect_params_in_body(body, source, http_method, external_functions, external_methods, cache, visiting, sink, 0)
      end
    when "identifier"
      name = Noir::TreeSitter.node_text(handler_arg, source)
      if fn = external_functions[name]?
        append_function_params(fn, http_method, external_functions, external_methods, cache, visiting, sink, 0)
      end
    when "selector_expression"
      append_selector_handler_params(handler_arg, source, http_method, external_functions, external_methods, cache, visiting, sink)
    when "call_expression"
      if candidate = fallback_handler_arg_from_call(handler_arg, source, external_functions, external_methods)
        collect_params_for_handler_arg(
          unwrap_handler_arg(candidate, source),
          source,
          http_method,
          external_functions,
          external_methods,
          cache,
          visiting,
          sink
        )
      end
    end
  end

  private def append_selector_handler_params(handler_arg : LibTreeSitter::TSNode,
                                             source : String,
                                             http_method : String,
                                             external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                             external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                             cache : Hash(String, Array(Param)),
                                             visiting : Set(String),
                                             sink : Array(Param))
    field = Noir::TreeSitter.field(handler_arg, "field")
    return unless field

    method_name = Noir::TreeSitter.node_text(field, source)
    if (methods = external_methods[method_name]?) && methods.size == 1
      append_function_params(methods.first, http_method, external_functions, external_methods, cache, visiting, sink, 0)
    end
  end

  private def append_function_params(fn : Noir::GoCalleeExtractor::FunctionBody,
                                     http_method : String,
                                     external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                     external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                     cache : Hash(String, Array(Param)),
                                     visiting : Set(String),
                                     sink : Array(Param),
                                     depth : Int32)
    key = "#{fn.file_path}:#{fn.start_row}:#{http_method}"
    if cached = cache[key]?
      cached.each { |param| push_param(sink, param) }
      return
    end

    visit_key = "#{fn.file_path}:#{fn.start_row}"
    return if visiting.includes?(visit_key)
    visiting << visit_key

    params = [] of Param
    wrapped = "package _noir_params_wrap\n#{fn.source}\n"
    Noir::TreeSitter.parse_go(wrapped) do |root|
      Noir::TreeSitter.each_named_child(root) do |child|
        ty = Noir::TreeSitter.node_type(child)
        next unless ty == "function_declaration" || ty == "method_declaration"
        if body = Noir::TreeSitter.field(child, "body")
          collect_params_in_body(body, wrapped, http_method, external_functions, external_methods, cache, visiting, params, depth)
          break
        end
      end
    end

    visiting.delete(visit_key)
    cache[key] = dedupe_params(params)
    cache[key].each { |param| push_param(sink, param) }
  end

  private def collect_params_in_body(body : LibTreeSitter::TSNode,
                                     source : String,
                                     http_method : String,
                                     external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                     external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                     cache : Hash(String, Array(Param)),
                                     visiting : Set(String),
                                     sink : Array(Param),
                                     depth : Int32)
    walk(body) do |node|
      next unless Noir::TreeSitter.node_type(node) == "call_expression"

      extract_params_from_call(node, source, http_method).each do |param|
        push_param(sink, param)
      end

      next if depth >= MAX_HELPER_DEPTH
      if fn = helper_function_body_for_call(node, source, external_functions, external_methods)
        append_function_params(fn, http_method, external_functions, external_methods, cache, visiting, sink, depth + 1)
      end
    end
  end

  private def extract_params_from_call(call : LibTreeSitter::TSNode,
                                       source : String,
                                       http_method : String) : Array(Param)
    params = [] of Param
    call_text = Noir::TreeSitter.node_text(call, source)

    if call_text.matches?(/json\.NewDecoder\([^)]*\.Body\)\s*\.\s*Decode/) ||
       call_text.matches?(/(?:io|ioutil)\.ReadAll\([^)]*\.Body\)/)
      params << Param.new("body", "", "json")
    end

    append_regex_param(params, call_text, /\.URL\s*\.\s*Query\s*\(\s*\)\s*\.\s*Get\s*\(\s*["`]([^"`]+)["`]/, "query")
    append_regex_param(params, call_text, /\.PostForm\s*\.\s*Get\s*\(\s*["`]([^"`]+)["`]/, "form")
    append_regex_param(params, call_text, /\.Form\s*\.\s*Get\s*\(\s*["`]([^"`]+)["`]/, form_value_param_type(http_method))
    append_regex_param(params, call_text, /\.PostFormValue\s*\(\s*["`]([^"`]+)["`]/, "form")
    append_regex_param(params, call_text, /\.FormValue\s*\(\s*["`]([^"`]+)["`]/, form_value_param_type(http_method))
    append_regex_param(params, call_text, /\.Header\s*\.\s*Get\s*\(\s*["`]([^"`]+)["`]/, "header")
    append_regex_param(params, call_text, /\.Cookie\s*\(\s*["`]([^"`]+)["`]/, "cookie")
    append_regex_param(params, call_text, /\.PathValue\s*\(\s*["`]([^"`]+)["`]/, "path")

    leaf = call_function_leaf(call, source)
    if param_type = helper_param_type(leaf, http_method)
      if name = first_string_arg(call, source)
        params << Param.new(name, "", param_type)
      end
    end

    dedupe_params(params)
  end

  private def append_regex_param(params : Array(Param), call_text : String, regex : Regex, param_type : String)
    if match = call_text.match(regex)
      params << Param.new(match[1], "", param_type)
    end
  end

  private def helper_function_body_for_call(call : LibTreeSitter::TSNode,
                                            source : String,
                                            external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                            external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))) : Noir::GoCalleeExtractor::FunctionBody?
    function = Noir::TreeSitter.field(call, "function")
    return unless function

    case Noir::TreeSitter.node_type(function)
    when "identifier"
      name = Noir::TreeSitter.node_text(function, source)
      external_functions[name]?
    when "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      return unless field
      method_name = Noir::TreeSitter.node_text(field, source)
      return if helper_param_type(method_name, "") || method_name == "Get" || method_name == "Decode"
      if (methods = external_methods[method_name]?) && methods.size == 1
        methods.first
      end
    end
  end

  private def helper_param_type(name : String, http_method : String) : String?
    case name
    when "HasQueryParam"
      "query"
    when "PathValue", "PathParam", "URLParam"
      "path"
    else
      if name.matches?(/^Query[A-Za-z0-9_]*Param(?:List)?$/)
        "query"
      elsif name.matches?(/^Route[A-Za-z0-9_]*Param$/)
        "path"
      elsif name.matches?(/^Path[A-Za-z0-9_]*Param$/)
        "path"
      elsif name.matches?(/^Form[A-Za-z0-9_]*Param$/)
        form_value_param_type(http_method)
      elsif name.matches?(/^Header[A-Za-z0-9_]*Param$/)
        "header"
      elsif name.matches?(/^Cookie[A-Za-z0-9_]*Param$/)
        "cookie"
      end
    end
  end

  private def form_value_param_type(http_method : String) : String
    case http_method
    when "GET", "HEAD", ""
      "query"
    else
      "form"
    end
  end

  private def first_string_arg(call : LibTreeSitter::TSNode, source : String) : String?
    args = Noir::TreeSitter.field(call, "arguments")
    return unless args

    Noir::TreeSitter.each_named_child(args) do |arg|
      if string_literal_node?(arg)
        return decode_string_literal(arg, source)
      end
    end

    nil
  end

  private def find_handler_args(call : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
    found = [] of LibTreeSitter::TSNode
    args = Noir::TreeSitter.field(call, "arguments")
    return found unless args

    first = true
    Noir::TreeSitter.each_named_child(args) do |arg|
      if first
        first = false
        next
      end
      next if string_literal_node?(arg)
      found << arg
    end

    found
  end

  private def fallback_handler_arg_from_call(call : LibTreeSitter::TSNode,
                                             source : String,
                                             external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                             external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))) : LibTreeSitter::TSNode?
    args = Noir::TreeSitter.field(call, "arguments")
    return unless args

    Noir::TreeSitter.each_named_child(args) do |arg|
      next if string_literal_node?(arg)
      candidate = unwrap_handler_arg(arg, source)
      return candidate if handler_candidate?(candidate, source, external_functions, external_methods)
    end

    nil
  end

  private def handler_candidate?(node : LibTreeSitter::TSNode,
                                 source : String,
                                 external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                 external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))) : Bool
    case Noir::TreeSitter.node_type(node)
    when "func_literal", "call_expression"
      true
    when "identifier"
      external_functions.has_key?(Noir::TreeSitter.node_text(node, source))
    when "selector_expression"
      field = Noir::TreeSitter.field(node, "field")
      return false unless field
      methods = external_methods[Noir::TreeSitter.node_text(field, source)]?
      !methods.nil? && methods.size == 1
    else
      false
    end
  end

  private def unwrap_handler_arg(arg : LibTreeSitter::TSNode, source : String, depth : Int32 = 0) : LibTreeSitter::TSNode
    return arg if depth > 4
    return arg unless Noir::TreeSitter.node_type(arg) == "call_expression"

    function = Noir::TreeSitter.field(arg, "function")
    wrapper_name = function ? call_text(function, source) : ""
    return arg unless handler_wrapper_call?(wrapper_name)

    args = Noir::TreeSitter.field(arg, "arguments")
    return arg unless args

    inner : LibTreeSitter::TSNode? = nil
    Noir::TreeSitter.each_named_child(args) do |child|
      next if string_literal_node?(child)
      inner = child
      break unless wrapper_name == "append"
    end

    if found = inner
      unwrap_handler_arg(found, source, depth + 1)
    else
      arg
    end
  end

  private def handler_wrapper_call?(name : String) : Bool
    return true if name == "append"
    return true if name == "HandlerFunc" || name.ends_with?(".HandlerFunc")
    return true if name == "StripPrefix" || name.ends_with?(".StripPrefix")
    return true if name == "Use" || name.ends_with?(".Use")
    false
  end

  private def call_function_leaf(call : LibTreeSitter::TSNode, source : String) : String
    function = Noir::TreeSitter.field(call, "function")
    return "" unless function
    case Noir::TreeSitter.node_type(function)
    when "identifier"
      Noir::TreeSitter.node_text(function, source)
    when "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      field ? Noir::TreeSitter.node_text(field, source) : ""
    else
      ""
    end
  end

  private def call_text(node : LibTreeSitter::TSNode, source : String) : String
    case Noir::TreeSitter.node_type(node)
    when "identifier"
      Noir::TreeSitter.node_text(node, source)
    when "selector_expression"
      operand = Noir::TreeSitter.field(node, "operand")
      field = Noir::TreeSitter.field(node, "field")
      return "" unless operand && field
      left = call_text(operand, source)
      left.empty? ? Noir::TreeSitter.node_text(field, source) : "#{left}.#{Noir::TreeSitter.node_text(field, source)}"
    else
      ""
    end
  end

  private def string_literal_node?(node : LibTreeSitter::TSNode) : Bool
    ty = Noir::TreeSitter.node_type(node)
    ty == "interpreted_string_literal" || ty == "raw_string_literal"
  end

  private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
    text = Noir::TreeSitter.node_text(node, source)
    return text[1...-1] if text.size >= 2 && ((text.starts_with?("\"") && text.ends_with?("\"")) || (text.starts_with?("`") && text.ends_with?("`")))
    text
  end

  private def dedupe_params(params : Array(Param)) : Array(Param)
    deduped = [] of Param
    params.each { |param| push_param(deduped, param) }
    deduped
  end

  private def push_param(params : Array(Param), param : Param)
    return if param.name.empty? || param.param_type.empty?
    return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
    params << param
  end

  private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
    block.call(node)
    Noir::TreeSitter.each_named_child(node) do |child|
      walk(child, &block)
    end
  end
end
