require "../models/endpoint"
require "./cpp_callee_extractor"
require "../utils/top_level_split"

# Shared parsing for the C embedded HTTP servers (Mongoose, CivetWeb,
# libmicrohttpd). C has no route DSL: a URI is a string literal handed to a
# registration call, or compared against the request URI inside one big
# handler, and a handler is a plain function. These helpers resolve those
# literals (including `#define NAME "/path"`), find a handler's body, and
# read the method and parameter evidence out of it. Offsets are bytes, as in
# `CppCalleeExtractor`.
module Noir::CHttpSupport
  extend self

  # C apps embed these libraries from C++ too (CivetWeb ships a C++ wrapper).
  EXTENSIONS = %w[.c .h .cc .cpp .cxx .hpp]
  # The libraries' own sources, vendored next to the app as the amalgamated
  # file or as a whole checkout (`lib/mongoose/src/http.c`, its examples).
  VENDORED     = Set{"mongoose.c", "mongoose.h", "civetweb.c", "civetweb.h", "CivetServer.cpp", "CivetServer.h", "microhttpd.h"}
  VENDORED_DIR = %r{(?:\A|/)(?:mongoose|civetweb|libmicrohttpd)/(?:src|examples|tutorials|test)/}

  # `#define NAME "/p"`, `static const char NAME[] = "/p";`, `const char *NAME = "/p";`
  DEFINE_RE   = /#[ \t]*define[ \t]+([A-Za-z_]\w*)[ \t]+"([^"\n]*)"|\bconst\s+char\s*(?:\*\s*(?:const\s+)?)?([A-Za-z_]\w*)\s*(?:\[\s*\])?\s*=\s*"([^"\n]*)"\s*;/
  STRING_EXPR = /\A(?:\s*(?:"(?:[^"\\]|\\.)*"|[A-Za-z_]\w*))+\s*\z/
  STRING_PART = /"((?:[^"\\]|\\.)*)"|([A-Za-z_]\w*)/
  # `strcmp(ri->request_method, "POST")`, `mg_match(hm->method, mg_str("POST"), NULL)`,
  # `strcmp("GET", method)`, `strcmp(method, MHD_HTTP_METHOD_POST)`. Negated
  # compares count too: `if (0 != strcmp(method, "GET")) return MHD_NO;` is
  # how a handler says it only serves GET.
  METHOD_RE = /method\s*,\s*(?:mg_str\s*\(\s*)?"(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)"|"(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)"\s*,\s*[&\w>.\-]*method\b|MHD_HTTP_METHOD_(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\b/
  # Mongoose `mg_http_get_var(&hm->query, "q", ...)` and CivetWeb
  # `mg_get_var(qs, len, "q", ...)`: the source buffer says query vs form.
  VAR_RE   = /\bmg_(?:http_get_var|get_http_var|http_var|get_var2?)\s*\(\s*([^,]*),(?:[^,"]*,)?\s*(?:mg_str\s*\(\s*)?"([^"]+)"/
  NAMED_RE = [
    {/\bgetParam\s*\(\s*[^,"]*,\s*"([^"]+)"/, "query"},
    {/\b(?:mg_http_get_header|mg_get_http_header|mg_get_header|getHeader)\s*\(\s*[^,]*,\s*"([^"]+)"/, "header"},
    {/\b(?:mg_get_cookie|getCookie)\s*\(\s*[^,]*,\s*"([^"]+)"/, "cookie"},
    {/\bmg_json_get\w*\s*\(\s*[^,]*,\s*"\$\.(\w+)/, "json"},
  ]
  MHD_VALUE_RE = /\bMHD_lookup_connection_value(?:_n)?\s*\(\s*[^,]*,\s*MHD_(GET_ARGUMENT|HEADER|COOKIE|POSTDATA)_KIND\s*,\s*"([^"]+)"/
  MHD_KINDS    = {"GET_ARGUMENT" => "query", "HEADER" => "header", "COOKIE" => "cookie", "POSTDATA" => "form"}
  CALL_RE      = /(?<![\w.>])([A-Za-z_]\w*)\s*\(/

  # Comment-stripped source plus its string constants.
  record Unit, source : String, defines : Hash(String, String)

  def unit(content : String) : Unit
    source = CppCalleeExtractor.strip_comments(content)
    defines = {} of String => String
    source.scan(DEFINE_RE) { |m| m[1]? ? (defines[m[1]] = m[2]) : (defines[m[3]] = m[4]) }
    Unit.new(source, defines)
  end

  def vendored?(path : String) : Bool
    VENDORED.includes?(File.basename(path)) || path.matches?(VENDORED_DIR)
  end

  # Top-level arguments of the call whose `(` is at `open_paren`, plus the
  # byte offset of its `)`.
  def call_args(source : String, open_paren : Int32) : Tuple(Array(String), Int32)?
    close = CppCalleeExtractor.find_matching_delimiter(source, open_paren, '(', ')')
    return unless close
    {TopLevelSplit.split(source.byte_slice(open_paren + 1, close - open_paren - 1), ',', TopLevelSplit::Rules::CPP), close}
  end

  # A string argument: literals, `mg_str("...")`, `#define`d names and
  # adjacent concatenations of those (`AREA_URL "page"`). Nil for anything
  # computed at runtime.
  def string_value(arg : String?, unit : Unit) : String?
    return unless arg
    s = arg.strip
    s = s[7..-2].strip if s.starts_with?("mg_str(") && s.ends_with?(')')
    return unless s.matches?(STRING_EXPR)
    String.build do |io|
      s.scan(STRING_PART) do |m|
        if literal = m[1]?
          io << literal
        else
          io << (unit.defines[m[2]]? || return)
        end
      end
    end
  end

  # The URI pattern as a Noir URL: Mongoose `#` and CivetWeb `**` (match
  # anything) become `*`, CivetWeb's `$` end anchor is dropped. Nil for
  # non-path patterns (`**.php$`, `""`).
  def route_path(raw : String?) : String?
    return unless raw && raw.starts_with?('/')
    raw.rchop('$').gsub("**", "*").gsub('#', '*')
  end

  def methods_in(text : String) : Array(String)
    methods = [] of String
    text.scan(METHOD_RE) { |m| methods << (m[1]? || m[2]? || m[3]).upcase }
    methods.uniq
  end

  def params_in(text : String) : Array(Param)
    params = [] of Param
    text.scan(VAR_RE) { |m| params << Param.new(m[2], "", m[1].matches?(/body|post/i) ? "form" : "query") }
    NAMED_RE.each { |re, type| text.scan(re) { |m| params << Param.new(m[1], "", type) } }
    text.scan(MHD_VALUE_RE) { |m| params << Param.new(m[2], "", MHD_KINDS[m[1]]) }
    seen = Set(Tuple(String, String)).new
    params.select { |p| seen.add?({p.name, p.param_type}) }
  end

  # `body` plus the bodies of the same-file functions it calls: handlers
  # routinely hand the request to a `handle_login(c, hm)` helper. Functions
  # `body` defines itself (a C++ handler class's methods) are already in it.
  def with_callees(unit : Unit, body : String) : String
    names = Set(String).new
    body.scan(CALL_RE) { |m| names << m[1] }
    String.build do |io|
      io << body
      names.each do |name|
        next if name.starts_with?("mg_") || name.starts_with?("MHD_") || CppCalleeExtractor::RESERVED.includes?(name)
        next if CppCalleeExtractor.function_body(body, name)
        if callee = CppCalleeExtractor.function_body(unit.source, name)
          io << '\n' << callee[0]
        end
      end
    end
  end

  # A route served by a whole handler (`body`, nil when unresolved): the
  # methods it compares the request method against, the params it and its
  # helpers read.
  def handler_route(unit : Unit, path : String, url : String, line : Int32, body : Tuple(String, Int32)?,
                    include_callee : Bool, methods : Array(String)? = nil) : Array(Endpoint)
    methods ||= body ? methods_in(body[0]) : [] of String
    scope = body ? with_callees(unit, body[0]) : ""
    endpoints(path, url, line, methods, scope, body, include_callee)
  end

  # The function named by a handler argument (`handler`, `&handler`).
  def handler_body(unit : Unit, arg : String?) : Tuple(String, Int32)?
    arg.try { |a| CppCalleeExtractor.function_body(unit.source, a.strip.lchop('&').strip) }
  end

  # A route found as a URI comparison inside a handler. The method comes
  # from the `if` condition, else from the branch it guards, else GET;
  # params come from the branch and the helpers it calls.
  def compared_route(unit : Unit, path : String, url : String, call_start : Int32, close : Int32,
                     include_callee : Bool) : Array(Endpoint)
    source = unit.source
    branch = branch_after(source, close)
    methods = methods_in(condition_around(source, call_start, close))
    methods = methods_in(branch[0]) if methods.empty? && branch
    scope = branch ? with_callees(unit, branch[0]) : ""
    protocol = scope.includes?("mg_ws_upgrade") ? "ws" : "http"
    endpoints(path, url, CppCalleeExtractor.line_number_for(source, call_start), methods, scope, branch, include_callee, protocol)
  end

  # The whole `if (...)` condition the URI test sits in: from the previous
  # statement boundary to the branch opener.
  private def condition_around(source : String, call_start : Int32, close : Int32) : String
    start = call_start - 1
    while start >= 0 && !source.byte_at(start).unsafe_chr.in?('{', '}', ';')
      start -= 1
    end
    stop = CppCalleeExtractor.find_next_code_char(source, '{', close) || source.bytesize
    semicolon = CppCalleeExtractor.find_next_code_char(source, ';', close, stop)
    stop = semicolon if semicolon
    source.byte_slice(start + 1, stop - start - 1)
  end

  # The `{ ... }` branch guarded by the URI test, or the single statement
  # of a brace-less branch.
  private def branch_after(source : String, close : Int32) : Tuple(String, Int32)?
    semicolon = CppCalleeExtractor.find_next_code_char(source, ';', close)
    brace = CppCalleeExtractor.find_next_code_char(source, '{', close)
    if brace && (semicolon.nil? || brace < semicolon)
      CppCalleeExtractor.extract_block_after(source, close)
    elsif semicolon
      {source.byte_slice(close + 1, semicolon - close), CppCalleeExtractor.line_number_for(source, close)}
    end
  end

  # One endpoint per method (GET when the handler never looks), carrying the
  # params read in `scope` and, when asked, the callees of `body`.
  def endpoints(path : String, url : String, line : Int32, methods : Array(String), scope : String,
                body : Tuple(String, Int32)?, include_callee : Bool, protocol = "http") : Array(Endpoint)
    params = params_in(scope)
    callees = include_callee && body ? CppCalleeExtractor.callees_for_body(body[0], path, body[1]) : nil
    (methods.empty? ? ["GET"] : methods).map do |method|
      endpoint = Endpoint.new(url, method, params.dup, Details.new(PathInfo.new(path, line)))
      endpoint.protocol = protocol
      CppCalleeExtractor.attach_to(endpoint, callees) if callees
      endpoint
    end
  end
end
