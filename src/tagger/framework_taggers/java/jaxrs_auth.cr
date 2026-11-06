require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../utils/c_comments"
require "../../../utils/js_literal_scanner"
require "./spring_module_scope"
require "./spring_auth"

# A JAX-RS `ContainerRequestFilter` that answers 401 to a caller without a
# credential guards every resource method it runs for. Only this shape of
# `filter(ContainerRequestContext ctx)` is read; anything else leaves the
# endpoints as they were (a missed guard is better than a false one):
#
#   [if (ctx instanceof T t) {]              -- an optional wrapper
#     if ("OPTIONS".equals(x.getMethod())) return;   -- preflights only
#     Principal principal = null;            -- a credential local
#     <statements without `return`>          -- they may assign it from calls
#     if (<absent>) { ..; <401 refusal>; }
#     | if (principal != null) { .. } else { [if (!m.isAnnotationPresent(A.class)) {] ..; <401 refusal>; [}] }
#
# `<absent>` is `principal == null`, `ctx.getSecurityContext().getUserPrincipal()
# == null` or a credential header read off `ctx` that is null, optionally
# `&& !m.isAnnotationPresent(A.class)`. A 401 refusal is `throw new
# NotAuthorizedException(..)`, or a `WebApplicationException` / `abortWith`
# whose code says UNAUTHORIZED or 401. The annotations read exempt the
# endpoints that carry them.
#
# The filter applies when it is `@Provider`, registered by an unconditional
# `register(..)`, or by a registered `DynamicFeature` whose `configure`
# registers it unconditionally or under `!..isAnnotationPresent(A.class)`.
# Any other annotation on the filter may be a `@NameBinding` (its
# declaration can live outside the scan): the filter then guards only
# endpoints carrying it. An app whose classpath holds more than one JAX-RS
# application definition is not judged: noir cannot tell which serves a
# resource.
@[Noir::TaggerFor(key: "jaxrs_auth", name: "JAX-RS Auth Tagger", desc: "Identifies JAX-RS ContainerRequestFilter authentication", order: 310)]
class JaxrsAuthTagger < FrameworkTagger
  include SpringModuleScope

  record RequestFilter,
    name : String,
    file_path : String,
    line : Int32,
    module_dir : String?,
    exempt : Set(String),
    provider : Bool,
    bound : Array(String)

  # A filter registration; `feature` is the `DynamicFeature` that makes it.
  record Registration, name : String, module_dir : String?, exempt : Set(String), feature : String?

  FILTER_CLASS   = /\bclass\s+([A-Za-z_$][\w$]*)[^{;]*?(?:\bimplements\s+[^{;]*?|:\s*[^{;]*?)\b(?:[\w.]+\.)?ContainerRequestFilter\b(?!\s*[<.])/
  FEATURE_CLASS  = /\bclass\s+([A-Za-z_$][\w$]*)[^{;]*?(?:\bimplements\s+[^{;]*?|:\s*[^{;]*?)\b(?:[\w.]+\.)?DynamicFeature\b(?!\s*[<.])/
  FILTER_METHOD  = /(?:\bvoid\s+filter\s*\(\s*(?:final\s+)?(?:[\w.]+\.)?ContainerRequestContext\s+([a-z_$][\w$]*)\s*\)|\bfun\s+filter\s*\(\s*([a-z_$][\w$]*)\s*:\s*(?:[\w.]+\.)?ContainerRequestContext\??\s*\))[^{;]*\{/
  CONFIGURE      = /\b(?:void|fun)\s+configure\s*\([^()]*\bResourceInfo\b[^()]*\)[^{;]*\{/
  REFUSAL        = /\Athrow\s+(?:new\s+)?(NotAuthorizedException|WebApplicationException|ClientErrorException)\s*\(|\A[\w$]+\s*\.\s*abortWith\s*\(/
  UNAUTHORIZED   = /\bUNAUTHORI[SZ]ED\b|\b401\b/
  OPTIONS_TEST   = /\A(?:(?:"OPTIONS"|HttpMethod\.OPTIONS)\s*\.\s*equals(?:IgnoreCase)?\s*\(\s*[\w$]+\s*\.\s*getMethod\s*\(\s*\)\s*\)|[\w$]+\s*\.\s*(?:getMethod\s*\(\s*\)|method)\s*(?:\.\s*equals(?:IgnoreCase)?\s*\(\s*(?:"OPTIONS"|HttpMethod\.OPTIONS)\s*\)|==\s*(?:"OPTIONS"|HttpMethod\.OPTIONS)))\z/
  ANNOTATION_NEG = /\A!\s*[\w$.()\s]*?\bisAnnotationPresent\s*\(\s*([A-Z][\w$]*)\s*(?:\.class|::class(?:\.java)?)\s*\)\z/
  REGISTER_CALL  = /\bregister(?:Classes|Instances)?\s*\(/
  REGISTERED     = /\b([A-Z][\w$]*)\s*(?:\.class\b|::class\b)|\bnew\s+([A-Z][\w$]*)\s*\(/
  # A JAX-RS application definition: two in one app leave noir unable to
  # tell which one serves a resource.
  APPLICATION = /\bnew\s+ResourceConfig\s*\(|\bextends\s+(?:ResourceConfig|(?:[\w.]*\.)?Application)\b|:\s*(?:ResourceConfig|(?:[\w.]*\.)?Application)\s*\(/
  # The type or name of a local holding the caller's identity.
  CREDENTIAL_LOCAL = /principal|securitycontext|subject|identity|credential|user|account|session|token/i
  # Annotations that bind nothing: any other one on a filter may be its `@NameBinding`.
  NON_BINDING = Set{"Provider", "Priority", "PreMatching", "Component", "Singleton", "ApplicationScoped", "RequestScoped", "Dependent", "Named", "Service", "Slf4j", "Log4j2", "CommonsLog", "SuppressWarnings", "Deprecated", "Generated", "Inject"}
  CLASS_LINE  = /\bclass\s+[A-Za-z_$]/
  # Block heads a registration may sit under: none of these.
  CONDITIONAL_HEAD = /(?:\b(?:if|else|for|while|do|switch|catch|when)\b[^;{}]*|->\s*)\z/

  @filters = [] of RequestFilter
  @registrations = [] of Registration
  @features = Hash(String, Bool).new
  @applications = [] of String?
  @masked_lines = Hash(String, Array(String)).new
  @class_lines = Hash(String, Array(Int32)).new

  def self.target_techs : Array(String)
    ["java_jaxrs"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    pre_scan
    return endpoints if @filters.empty?
    super
  end

  private def pre_scan
    @filters.clear
    @registrations.clear
    @features.clear
    @applications.clear
    sources = {".java", ".kt"}.flat_map { |ext| collect_files_by_extension(ext) }.reject { |file| test_source?(file) }
    sources.each do |file|
      next unless content = read_file(file)
      next unless content.includes?("ContainerRequestFilter") || content.includes?("register") || content.includes?("Application") || content.includes?("ResourceConfig")
      code = ascii(Noir::CComments.strip(content))
      mask = masked(code)
      module_dir = build_module(file)
      mask.scan(APPLICATION) { @applications << module_dir } if content.includes?("ws.rs") || content.includes?("ResourceConfig")
      scan_filters(code, mask, file, module_dir) if content.includes?("ContainerRequestFilter")
      scan_registrations(mask, module_dir) if content.includes?("register")
    end
    # A DynamicFeature's registrations count once the feature itself is registered.
    @registrations.select! do |reg|
      next true unless feature = reg.feature
      @features[feature]? || @registrations.any? { |other| other.name == feature && other.feature.nil? }
    end
    @filters.select! do |filter|
      filter.provider || @registrations.any? { |reg| reg.name == filter.name }
    end
  end

  # Non-ASCII characters as spaces: the walk indexes by character.
  private def ascii(text : String) : String
    text.ascii_only? ? text : text.gsub(/[^\x00-\x7F]/, " ")
  end

  # `code` with the inside of every string literal blanked to `x`, same length.
  private def masked(code : String) : String
    code.gsub(STRING_LITERAL) { |literal| "#{literal[0]}#{"x" * (literal.size - 2)}#{literal[-1]}" }
  end

  private def scan_filters(code : String, mask : String, file : String, module_dir : String?)
    mask.scan(FILTER_CLASS) do |match|
      name = match[1]
      next if name.matches?(SpringAuthTagger::NON_AUTH_FILTER_NAME)
      next unless (open = mask.index('{', match.end(0) - 1)) && (close = Noir::JSLiteralScanner.find_matching_brace(mask, open))
      next unless method = mask[open..close].match(FILTER_METHOD)
      body_open = open + method.end(0) - 1
      next unless body_close = Noir::JSLiteralScanner.find_matching_brace(mask, body_open)
      exempt = judge(code[(body_open + 1)...body_close], mask[(body_open + 1)...body_close]) || next
      annotations = annotations_before(mask, match.begin(0))
      @filters << RequestFilter.new(
        name: name,
        file_path: file,
        line: code[0, match.begin(0)].count('\n') + 1,
        module_dir: module_dir,
        exempt: exempt,
        provider: annotations.includes?("Provider"),
        bound: annotations.reject { |item| NON_BINDING.includes?(item) }
      )
    end
  end

  # The annotation names in front of the declaration at `start`, back to the
  # previous statement or block boundary.
  private def annotations_before(mask : String, start : Int32) : Array(String)
    from = (mask.rindex(/[;{}]/, start - 1) || -1) + 1
    mask[from...start].scan(/@([A-Za-z_$][\w$.]*)/).map(&.[1].split('.').last)
  end

  private def scan_registrations(mask : String, module_dir : String?)
    features = [] of {String, Int32, Int32}
    mask.scan(FEATURE_CLASS) do |match|
      @features[match[1]] = annotations_before(mask, match.begin(0)).includes?("Provider")
      next unless (open = mask.index('{', match.end(0) - 1)) && (close = Noir::JSLiteralScanner.find_matching_brace(mask, open))
      next unless found = mask[open..close].match(CONFIGURE)
      body_open = open + found.end(0) - 1
      body_close = Noir::JSLiteralScanner.find_matching_brace(mask, body_open) || next
      features << {match[1], body_open, body_close}
    end
    heads = block_heads(mask)
    mask.scan(REGISTER_CALL) do |call|
      open = call.end(0) - 1
      next unless close = Noir::JSLiteralScanner.find_matching_paren(mask, open)
      at = call.begin(0)
      feature = features.find { |_, from, to| from < at < to }
      exempt = Set(String).new
      if feature
        next unless marker = feature_condition(mask, feature[1], at)
        exempt << marker unless marker.empty?
      else
        # An unconditional registration: no `if`, loop, lambda or `?:` around it.
        next if heads.any? { |from, to, head| from < at < to && head.matches?(CONDITIONAL_HEAD) }
        lead_from = (mask.rindex(/[;{}]/, at - 1) || -1) + 1
        next if mask[lead_from...at].matches?(/\b(?:if|else|for|while)\b|\?|->/)
      end
      mask[(open + 1)...close].scan(REGISTERED) do |registered|
        @registrations << Registration.new(registered[1]? || registered[2], module_dir, exempt, feature.try(&.[0]))
      end
    end
  end

  # Every `{..}` block of `mask` as `{open, close, the text before it back to
  # the previous statement boundary}`, in one pass.
  private def block_heads(mask : String) : Array({Int32, Int32, String})
    blocks = [] of {Int32, Int32, String}
    stack = [] of Int32
    boundary = [] of Int32
    last = -1
    mask.each_char_with_index do |char, index|
      case char
      when '{'
        stack << index
        boundary << last
        last = index
      when '}'
        if open = stack.pop?
          from = boundary.pop + 1
          blocks << {open, index, mask[from...open].strip}
        end
        last = index
      when ';'
        last = index
      end
    end
    blocks
  end

  # Where a `DynamicFeature.configure` body starting at `open` registers the
  # filter at `at`: "" unconditionally, the annotation of a lone
  # `if (!..isAnnotationPresent(A.class)) {` around it, nil otherwise.
  private def feature_condition(mask : String, open : Int32, at : Int32) : String?
    inner = block_heads(mask[open..]).select { |from, to, _| from > 0 && from < at - open < to }
    return "" if inner.empty? && !mask[((mask.rindex(/[;{}]/, at - 1) || 0) + 1)...at].matches?(/\b(?:if|else)\b|\?|->/)
    return unless inner.size == 1
    return unless cond = inner[0][2].match(/\Aif\s*\((.*)\)\z/m)
    unwrap(cond[1]).match(ANNOTATION_NEG).try(&.[1])
  end

  # The exempting annotations when the `filter` body (`code`, and `mask`
  # with its strings blanked) has the shape this tagger reads, nil otherwise.
  private def judge(code : String, mask : String) : Set(String)?
    @current_code = code
    stmts = statements(mask, 0, mask.size)
    # `if (ctx instanceof ContainerRequest request) { .. }` wraps the body.
    if stmts.size == 1 && (wrap = mask[stmts[0][0]...stmts[0][1]].match(/\Aif\s*\(\s*[\w$]+\s+instanceof\s+(?:final\s+)?[\w$.]+(?:\s+[\w$]+)?\s*\)\s*\{/))
      start = stmts[0][0] + wrap.end(0)
      stmts = statements(mask, start, (Noir::JSLiteralScanner.find_matching_brace(mask, start - 1) || return))
    end
    credential = nil
    exempt = Set(String).new
    stmts.each do |from, to|
      text = mask[from...to]
      if (branch = if_parts(mask, from, to)) && branch[2].nil? && only_return?(mask, branch[1]) &&
         unwrap(code[branch[3][0]...branch[3][1]]).matches?(OPTIONS_TEST)
        next
      end
      if refusal_if?(code, mask, from, to, credential, exempt)
        return exempt if credential.nil? || assigned_plainly?(stmts, mask, credential)
        return
      end
      return if text.matches?(/\breturn\b/)
      if credential.nil? && (decl = text.match(/\A(?:final\s+)?(?:val\s+|var\s+)?([\w$.<>]+\s+)?([a-z_$][\w$]*)\s*(?::\s*([\w$.<>]+)\??\s*)?=\s*null\s*;?\z/))
        type = decl[1]?.try(&.strip) || decl[3]? || ""
        credential = decl[2] if "#{type} #{decl[2]}".matches?(CREDENTIAL_LOCAL)
      end
    end
    nil
  end

  # `{start, stop}` of each top-level statement of `mask[from...to]`.
  private def statements(mask : String, from : Int32, to : Int32) : Array({Int32, Int32})
    found = [] of {Int32, Int32}
    pos = from
    while pos < to
      if mask[pos].whitespace? || mask[pos] == ';'
        pos += 1
        next
      end
      start = pos
      depth = 0
      while pos < to
        char = mask[pos]
        if char.in?('(', '[', '{')
          depth += 1
        elsif char.in?(')', ']', '}')
          depth -= 1
          if depth == 0 && char == '}'
            rest = pos + 1
            while rest < to && mask[rest].whitespace?
              rest += 1
            end
            word = mask[rest, 8]
            unless word.matches?(/\A(?:else|catch|finally)\b/)
              pos += 1
              break
            end
          end
        elsif depth == 0 && char == ';'
          pos += 1
          break
        elsif depth == 0 && char == '\n' && kotlin_line_end?(mask, start, pos, to)
          break
        end
        pos += 1
      end
      found << {start, pos}
    end
    found
  end

  # A newline ends a Kotlin statement unless the expression goes on.
  private def kotlin_line_end?(mask : String, start : Int32, pos : Int32, to : Int32) : Bool
    before = mask[start...pos].rstrip
    return false if before.empty? || "=+-*/%&|,(.:?<>!{".includes?(before[-1])
    return false if before.matches?(/\A(?:if|else|for|while)\b[^;]*\)\z|\Aelse\z/)
    after = pos + 1
    while after < to && mask[after].whitespace?
      after += 1
    end
    !(after < to && ".?&|:+-*/".includes?(mask[after]))
  end

  # `{condition, then-range, else-range}` of a statement `if (..) .. [else ..]`.
  private def if_parts(mask : String, from : Int32, to : Int32) : {String, {Int32, Int32}, {Int32, Int32}?, {Int32, Int32}}?
    return unless mask[from...to].starts_with?("if") && (paren = mask.index('(', from)) && mask[from...paren].strip == "if"
    return unless close = Noir::JSLiteralScanner.find_matching_paren(mask, paren)
    cond = unwrap(mask[(paren + 1)...close])
    body_from = close + 1
    while body_from < to && mask[body_from].whitespace?
      body_from += 1
    end
    if mask[body_from]? == '{'
      body_to = (Noir::JSLiteralScanner.find_matching_brace(mask, body_from) || return) + 1
      then_range = {body_from + 1, body_to - 1}
    else
      body_to = statements(mask, body_from, to).first?.try(&.[1]) || return
      then_range = {body_from, body_to}
    end
    rest = mask[body_to...to].strip
    cond_range = {paren + 1, close}
    return {cond, then_range, nil, cond_range} if rest.empty?
    return unless rest.starts_with?("else")
    else_from = (mask.index("else", body_to) || return) + 4
    while else_from < to && mask[else_from].whitespace?
      else_from += 1
    end
    return if mask[else_from...to].starts_with?("if")
    if mask[else_from]? == '{'
      else_to = Noir::JSLiteralScanner.find_matching_brace(mask, else_from) || return
      {cond, then_range, {else_from + 1, else_to}, cond_range}
    else
      {cond, then_range, {else_from, to}, cond_range}
    end
  end

  private def only_return?(mask : String, range : {Int32, Int32}) : Bool
    mask[range[0]...range[1]].strip.matches?(/\A\{?\s*return\s*;?\s*\}?\z/)
  end

  # The refusing `if` of the shape above; adds what it reads to `exempt`.
  private def refusal_if?(code : String, mask : String, from : Int32, to : Int32, credential : String?, exempt : Set(String)) : Bool
    return false unless parts = if_parts(mask, from, to)
    cond, then_range, else_range, _ = parts
    markers = Set(String).new
    if else_range.nil?
      return false unless absence?(cond, mask, from, credential, markers)
      return false unless refusing_block?(code, mask, then_range)
    else
      return false unless credential && cond.matches?(/\A#{Regex.escape(credential)}\s*!=\s*null\z/)
      return false if mask[then_range[0]...then_range[1]].matches?(/\breturn\b/)
      inner = statements(mask, else_range[0], else_range[1])
      if (last = inner.last?) && (nested = if_parts(mask, last[0], last[1])) && nested[2].nil? &&
         (marker = nested[0].match(ANNOTATION_NEG))
        return false if inner[0...-1].any? { |s, e| mask[s...e].matches?(/\breturn\b/) }
        markers << marker[1]
        return false unless refusing_block?(code, mask, nested[1])
      else
        return false unless refusing_block?(code, mask, else_range)
      end
    end
    exempt.concat(markers)
    true
  end

  # `cond` is true for a caller without a credential: an absence test,
  # optionally joined with `!..isAnnotationPresent(A.class)` (added to `markers`).
  private def absence?(cond : String, mask : String, at : Int32, credential : String?, markers : Set(String)) : Bool
    return false if cond.includes?("||")
    absent = false
    cond.split("&&").each do |part|
      atom = unwrap(part)
      if marker = atom.match(ANNOTATION_NEG)
        markers << marker[1]
      elsif (credential && atom.matches?(/\A(?:#{Regex.escape(credential)}\s*==\s*null|null\s*==\s*#{Regex.escape(credential)})\z/)) ||
            atom.matches?(/\A[\w$]+\s*\.\s*getSecurityContext\s*\(\s*\)\s*\.\s*getUserPrincipal\s*\(\s*\)\s*==\s*null\z/)
        absent = true
      elsif atom.matches?(/\A[\w$]+\s*\.\s*getHeaderString\s*\(\s*(?:HttpHeaders\.AUTHORIZATION|"x*")\s*\)\s*==\s*null\z/)
        return false unless credential_header?(atom, mask, at)
        absent = true
      else
        return false
      end
    end
    absent
  end

  # The literal header name behind a blanked `"xxx"`: `atom` is found again
  # in the unmasked filter source by its position in `mask`.
  @current_code = ""

  private def credential_header?(atom : String, mask : String, at : Int32) : Bool
    return true if atom.includes?("HttpHeaders.AUTHORIZATION")
    return false unless offset = mask.index(atom, at)
    return false unless name = @current_code[offset, atom.size].match(/"([^"]*)"/)
    name[1].matches?(SpringAuthTagger::CREDENTIAL_NAME)
  end

  # A block whose statements hold no `return` and end in a 401 refusal.
  private def refusing_block?(code : String, mask : String, range : {Int32, Int32}) : Bool
    inner = statements(mask, range[0], range[1])
    return false unless last = inner.last?
    return false if inner.any? { |s, e| mask[s...e].matches?(/\breturn\b/) }
    statement = mask[last[0]...last[1]]
    return false unless found = statement.match(REFUSAL)
    return true if found[1]? == "NotAuthorizedException"
    text = statement
    # `throw new WebApplicationException(builder.build())` over a
    # `builder = Response.status(UNAUTHORIZED)` local of the block.
    inner.each { |s, e| text += " " + mask[s...e] if mask[s...e].matches?(/=(?!=)[^;]*\bResponse\s*\.\s*status\s*\(/) }
    text.matches?(UNAUTHORIZED)
  end

  # Every assignment of the credential local before the refusal is a plain
  # call result: no fallback (`?:`, ternary, `||`, itself) and none under a
  # test of its own absence.
  private def assigned_plainly?(stmts : Array({Int32, Int32}), mask : String, name : String) : Bool
    escaped = Regex.escape(name)
    assign = /(?<![\w$.])#{escaped}\s*=(?!=)\s*([^;\n]*)/
    absence = /(?<![\w$.])#{escaped}\s*==\s*null|null\s*==\s*#{escaped}\b/
    stmts.all? do |from, to|
      text = mask[from...to]
      next true unless text.matches?(assign)
      next false if text.matches?(absence)
      text.scan(assign).all? do |found|
        rhs = found[1]
        rhs == "null" || (rhs.includes?("(") && !rhs.matches?(/\?|\|\||(?<![\w$.])#{escaped}\b/))
      end
    end
  end

  private def unwrap(text : String) : String
    text = text.strip
    while text.starts_with?('(') && Noir::JSLiteralScanner.find_matching_paren(text, 0) == text.size - 1
      text = text[1...-1].strip
    end
    text
  end

  private def check_endpoint(endpoint : Endpoint)
    return if endpoint.internal
    annotations = nil
    filter = per_serving_classpath(endpoint, true) do |classpath, _|
      applies = ->(owner : String?) { owner.nil? || classpath.nil? || classpath.includes?(owner) }
      next if @applications.count { |owner| applies.call(owner) } > 1
      @filters.find do |item|
        registrations = @registrations.select { |reg| reg.name == item.name && applies.call(reg.module_dir) }
        # The filter class itself must be on the app's classpath: another
        # module's class of the same name is no registration of this one.
        next false if !applies.call(item.module_dir) || (!item.provider && registrations.empty?)
        annotations ||= endpoint_annotations(endpoint)
        exempt = item.exempt.dup
        registrations.each { |reg| exempt.concat(reg.exempt) } unless item.provider
        next false if annotations.any? { |name| exempt.includes?(name) }
        item.bound.empty? || item.bound.any? { |name| annotations.includes?(name) }
      end
    end
    return unless filter
    endpoint.add_tag(Tag.new("auth", "Protected by JAX-RS request filter #{filter.name} (401)", "jaxrs_auth", filter.file_path, filter.line))
  end

  # Annotation names on the endpoint's resource method and its class.
  private def endpoint_annotations(endpoint : Endpoint) : Set(String)
    names = Set(String).new
    read_source_context(endpoint).each do |ctx|
      next unless line = ctx.line
      lines = masked_lines(ctx.path, ctx.full_content)
      idx = line - 1
      next unless 0 <= idx < lines.size
      collect = ->(text : String) { text.scan(/@([A-Za-z_$][\w$.]*)/) { |found| names << found[1].split('.').last } }
      annotation_block_above(lines, idx).each { |text| collect.call(text) }
      collect.call(lines[idx])
      annotation_lines_below(lines, idx, "@", 200).each { |text| collect.call(text) }
      class_idx = nearest_match_above(@class_lines, ctx.path, lines, &.matches?(CLASS_LINE))[idx]
      if class_idx >= 0
        annotation_block_above(lines, class_idx).each { |text| collect.call(text) }
        collect.call(lines[class_idx])
      end
    end
    names
  end

  private def masked_lines(path : String, content : String) : Array(String)
    @masked_lines[path] ||= masked(ascii(Noir::CComments.strip(content))).split('\n')
  end

  # The annotation lines stacked above line `idx`, multi-line ones included,
  # up to a line that declares something (`@GET @Path("/a") String a() {..}`).
  private def annotation_block_above(lines : Array(String), idx : Int32) : Array(String)
    block = [] of String
    depth = 0
    i = idx - 1
    while i >= 0 && i >= idx - 200
      text = lines[i].strip
      depth += text.count(')') - text.count('(')
      if depth > 0
        block << text
      elsif text.starts_with?('@')
        break if scan_annotations(text, "@")[1]
        block << text
      elsif !text.empty?
        break
      end
      depth = 0 if depth < 0
      i -= 1
    end
    block
  end
end
