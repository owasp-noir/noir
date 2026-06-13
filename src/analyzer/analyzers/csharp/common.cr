require "../../../miniparsers/csharp_callee_extractor"
require "../../../minilexers/csharp_lexer"

module Analyzer::CSharp::Common
  # Standard .NET test-source conventions:
  #
  #   * `/test/` and `/tests/` parent directories — Microsoft's
  #     own repos park unit + integration tests under
  #     `src/<Project>/test/...` (aspnetcore) or `tests/...`
  #     (smaller solutions).
  #   * `/testassets/` — aspnetcore's helper-controller convention
  #     for spinning up a real server inside the test harness.
  #   * `Tests.cs` / `Test.cs` filename — xUnit / NUnit / MSTest
  #     suffix convention.
  #
  # dotnet/aspnetcore alone parks ~3,600 phantom endpoints under
  # `src/Mvc/test/...` and similar trees. Production code never
  # adopts any of these.
  def self.csharp_test_path?(path : String) : Bool
    return true if path.includes?("/test/")
    return true if path.includes?("/tests/")
    return true if path.includes?("/testassets/")
    base = File.basename(path)
    return true if base.ends_with?("Tests.cs")
    base.ends_with?("Test.cs")
  end

  # `IFormFile`/`IFormFileCollection`/`IFormCollection` are interfaces but
  # bind from the request body (file upload / form), not from DI — keep
  # them as request inputs even though they match the interface rule below.
  SERVICE_FORM_INPUT_TYPES = Set{"IFormFile", "IFormFileCollection", "IFormCollection"}

  # Concrete framework types that are always resolved from DI / the
  # request pipeline rather than bound from user input.
  KNOWN_SERVICE_TYPES = Set{
    "CancellationToken", "HttpContext", "HttpRequest", "HttpResponse",
    "ClaimsPrincipal", "IServiceProvider", "LinkGenerator", "ILoggerFactory",
    "IConfiguration", "IWebHostEnvironment", "IHostEnvironment",
  }

  # High-precision suffixes that mark a type as a dependency-injected
  # collaborator. Deliberately conservative: suffixes that collide with
  # common domain/entity names (e.g. `Client`, `Provider`, `Factory`) are
  # left out so request DTOs aren't dropped by mistake. Interface-typed
  # DI is caught separately by the `I<Pascal>` rule.
  SERVICE_TYPE_SUFFIXES = %w[
    Repository Service Services Manager Mediator Mapper Accessor
    Dispatcher Publisher DbContext Context Logger
  ]

  # Heuristic for whether a parameter's *type* names a dependency-injected
  # service (DbContext, repository, MediatR sender, mapper, …) rather than a
  # value bound from the request. ASP.NET Core can't be statically resolved
  # against its DI container, so we lean on near-universal naming
  # conventions in real code:
  #
  #   * Interfaces (`I` + PascalCase) are never deserialized from a request
  #     body and never bound from the query string — they're DI or special
  #     pipeline types. The `[a-z]` third-char guard keeps acronym value
  #     types like `IPAddress` (I-P-A) out of the net.
  #   * A small set of concrete framework types and service suffixes.
  #
  # Returns false for the form-upload interfaces, which *are* request inputs.
  def self.csharp_service_type?(type_name : String) : Bool
    base = type_name.gsub(/<.*>/, "").split('.').last.strip
    return false if base.empty?
    return false if SERVICE_FORM_INPUT_TYPES.includes?(base)
    return true if KNOWN_SERVICE_TYPES.includes?(base)
    return true if base.matches?(/\AI[A-Z][a-z]/)
    SERVICE_TYPE_SUFFIXES.any? { |suffix| base.ends_with?(suffix) }
  end

  # `masked` is the string/comment-blanked twin of `lines` (from
  # `CSharpLexer#masked_lines`). Delimiter counting runs over `masked` so a
  # `(` inside a string default (`expr = "2 * (3 + 4"`) can't keep the paren
  # counter open and run the signature away, while the returned text is built
  # from the real `lines`.
  protected def build_signature(lines : Array(String), masked : Array(String), start_index : Int32) : Tuple(String, Int32)
    # A caller can hand us a `start_index` that ran past the end of the file
    # (e.g. after folding an unbalanced multi-line attribute that consumed
    # every remaining line). Bail out instead of indexing out of bounds.
    return {"", start_index} if start_index < 0 || start_index >= lines.size

    signature = lines[start_index]
    start_mask = masked[start_index]?
    paren_count = start_mask ? start_mask.count('(') - start_mask.count(')') : 0
    index = start_index + 1

    while paren_count > 0 && index < lines.size
      signature += " " + lines[index]
      if m = masked[index]?
        paren_count += m.count('(') - m.count(')')
      end
      index += 1
    end

    {signature, index - 1}
  end

  protected def split_csharp_parameters(param_list : String) : Array(String)
    params = [] of String
    current = String::Builder.new
    generic_depth = 0
    paren_depth = 0
    bracket_depth = 0
    brace_depth = 0
    in_string = false
    escaped = false

    param_list.each_char do |char|
      # Inside a string literal commas/brackets are data, not structure —
      # e.g. a route literal `"/a,b"` or a `new[] { "GET", "POST" }` arg.
      if in_string
        current << char
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == '"'
          in_string = false
        end
        next
      end

      case char
      when '"'
        in_string = true
      when '<'
        generic_depth += 1
      when '>'
        generic_depth -= 1 if generic_depth > 0
      when '('
        paren_depth += 1
      when ')'
        paren_depth -= 1 if paren_depth > 0
      when '['
        bracket_depth += 1
      when ']'
        bracket_depth -= 1 if bracket_depth > 0
      when '{'
        brace_depth += 1
      when '}'
        brace_depth -= 1 if brace_depth > 0
      when ','
        if generic_depth == 0 && paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
          params << current.to_s.strip
          current = String::Builder.new
          next
        end
      end

      current << char
    end

    tail = current.to_s.strip
    params << tail unless tail.empty?
    params
  end

  # Returns the substring inside the first balanced parameter-list parens of
  # a method signature. Unlike a greedy `\((.*)\)`, this stops at the matching
  # close paren so an expression body (`(int id) => Repo.Find(id)`) doesn't
  # leak the call's own arguments into the parameter list.
  protected def extract_balanced_param_list(signature : String) : String?
    # Count parens over the masked signature so a `(`/`)` inside a string
    # default value doesn't unbalance the parameter-list bounds. The masked
    # twin is character-aligned with `signature`, so the slice indices apply.
    masked = Noir::CSharpLexer.new(signature).masked
    open = masked.index('(')
    return unless open

    depth = 0
    i = open
    while i < masked.size
      case masked[i]
      when '('
        depth += 1
      when ')'
        depth -= 1
        return signature[(open + 1)...i] if depth == 0
      end
      i += 1
    end
    nil
  end

  # Counts braces over `masked` (string/comment-blanked) so a `}` inside a
  # string literal (`var json = T("a } b");`) can't terminate the block early
  # and drop every callee below it. The emitted text comes from raw `lines`.
  protected def extract_method_block(lines : Array(String), masked : Array(String), start_index : Int32) : String
    io = String::Builder.new
    brace = 0
    started = false
    index = start_index

    while index < lines.size
      line = lines[index]
      m = masked[index]
      brace += m.count('{') - m.count('}')
      started ||= brace > 0 || m.includes?("{")
      io << line
      io << '\n'
      if started && brace <= 0 && m.includes?("}")
        break
      end
      # Expression-bodied member (`=> expr;`): there is no brace block, so the
      # statement terminator ends it. Without this guard the scanner would run
      # to end-of-file and swallow every following member.
      if !started && m.includes?(";")
        break
      end
      index += 1
    end

    io.to_s
  end

  # Extracts a method's body starting from the line where its signature
  # closes. Handles both brace bodies (`{ ... }`) and expression bodies
  # (`=> expr;`). Returns `{block, start_line_index, skip_first_line}` —
  # the caller passes `skip_first_line` through to the callee scanner so a
  # brace body's own declaration line isn't recorded as a self-callee.
  protected def extract_callable_body(lines : Array(String), masked : Array(String), start_index : Int32) : Tuple(String, Int32, Bool)
    i = start_index
    while i < lines.size
      m = masked[i]
      if m.includes?("{")
        # Brace body: hand the `{`-line to the scanner with skip_first so
        # the method name on that line isn't recorded as its own callee.
        return {extract_method_block(lines, masked, i), i, true}
      elsif arrow = m.index("=>")
        # Expression body: crop everything up to and including `=>` on the
        # first line, then read until the statement terminator. Delimiter
        # depth and the `;` terminator are read from `masked` so braces/parens
        # and semicolons inside string literals don't end the body early.
        io = String::Builder.new
        depth = 0
        j = i
        while j < lines.size
          raw = lines[j]
          mraw = masked[j]
          text = j == i ? raw[(arrow + 2)..]? || "" : raw
          io << text << '\n'
          depth += mraw.count('(') - mraw.count(')') + mraw.count('{') - mraw.count('}')
          break if depth <= 0 && mraw.includes?(";")
          j += 1
        end
        return {io.to_s, i, false}
      elsif m.includes?(";")
        # Abstract/interface declaration with no body.
        return {"", i, false}
      end
      i += 1
    end
    {"", start_index, false}
  end

  protected def attach_csharp_callees(endpoint : Endpoint,
                                      block : String,
                                      file : String,
                                      start_line : Int32,
                                      include_callee : Bool,
                                      *,
                                      skip_first_line : Bool = false)
    return unless include_callee

    callees = Noir::CSharpCalleeExtractor.callees_for_block(block, file, start_line, skip_first_line: skip_first_line)
    Noir::CSharpCalleeExtractor.attach_to(endpoint, callees)
  end
end
