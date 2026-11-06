require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../../../utils/c_comments"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"
require "./spring_module_scope"
require "./spring_auth"

# A JAX-RS `ContainerRequestFilter` that turns a caller without a credential
# away guards every resource method it is registered for: Jersey and
# RESTEasy run it before the method. A filter is read only in one shape
# (anything else leaves the endpoints as they were):
#
#   void filter(ContainerRequestContext ctx) {
#     [if (OPTIONS / <credential present> / <annotation present>) return;]
#     .. if (<credential absent> [&& !<method>.isAnnotationPresent(A.class)]) {
#          throw new NotAuthorizedException(..) | ctx.abortWith(<401/403>) }
#   }
#
# where the refusal sits under `if` / `else` / `try` blocks only, every
# condition on its path holds for a caller who sends no credential, and no
# `return` before it can be taken by that caller. A credential is absent
# when a local that nothing assigns a fallback to is still `null`
# (`principal == null`, the `else` of `securityContext != null`), or a
# credential header the request lacks is. The filter is registered by
# `@Provider`, a `register(..)` call, or a `DynamicFeature` that registers
# it under readable conditions; a `@NameBinding` annotation on it limits it
# to the resources that carry the annotation. Every annotation a condition
# on the way reads (`@PermitAll`, `@AuthenticationNotRequired`) exempts the
# endpoints that carry it.
@[Noir::TaggerFor(key: "jaxrs_auth", name: "JAX-RS Auth Tagger", desc: "Identifies JAX-RS ContainerRequestFilter authentication", order: 310)]
class JaxrsAuthTagger < FrameworkTagger
  include SpringModuleScope

  record RequestFilter,
    name : String,
    file_path : String,
    line : Int32,
    module_dir : String?,
    refusal : String,
    exempt : Set(String),
    provider : Bool,
    bound : Array(String)

  # Where a filter is registered: `exempt` are the annotations the
  # registering condition reads.
  record Registration, name : String, module_dir : String?, exempt : Set(String)

  FILTER_CLASS    = /\bclass\s+([A-Za-z_$][\w$]*)[^{;]*?(?:\bimplements\s+[^{;]*?|:\s*[^{;]*?)\b(?:[\w.]+\.)?ContainerRequestFilter\b(?!\s*[<.])/
  FILTER_METHOD   = /(?:\bvoid\s+filter\s*\(\s*(?:final\s+)?(?:[\w.]+\.)?ContainerRequestContext\s+([a-z_$][\w$]*)\s*\)|\bfun\s+filter\s*\(\s*([a-z_$][\w$]*)\s*:\s*(?:[\w.]+\.)?ContainerRequestContext\??\s*\))[^{]*\{/
  REFUSAL         = /\bthrow\s+(?:new\s+)?(NotAuthorizedException|ForbiddenException|WebApplicationException|ClientErrorException)\s*\(|\.\s*abortWith\s*\(/
  REFUSAL_STATUS  = /\bUNAUTHORI[SZ]ED\b|\bFORBIDDEN\b|\b40[13]\b/
  ANNOTATION_READ = /\A[\w$.()\s]*?\b(isAnnotationPresent|getAnnotation|getDeclaredAnnotation)\s*\(\s*([A-Z][\w$]*)\s*(?:\.class|::class(?:\.java)?)\s*\)(?:\s*(==|!=)\s*null)?\z/
  NAME_BINDING    = /@(?:jakarta\.ws\.rs\.|javax\.ws\.rs\.)?NameBinding\b[^;]*?(?:@interface|annotation\s+class)\s+([A-Z][\w$]*)/
  REGISTER_CALL   = /\bregister(?:Classes|Instances)?\s*\(/
  REGISTERED      = /\b([A-Z][\w$]*)\s*(?:\.class\b|::class\b)|\bnew\s+([A-Z][\w$]*)\s*\(/
  CTX_ABSENT      = /\.\s*(?:getUserPrincipal|getSecurityContext|getHeaderString|getCookies)\s*\([^()]*\)\s*\z/
  HEADER_READ     = /\.\s*getHeaderString\s*\(\s*(?:HttpHeaders\.AUTHORIZATION\b|"([^"]*)")/
  CLASS_LINE      = /\bclass\s+[A-Za-z_$]/
  KEYWORD_HEADS   = Set{"if", "catch", "for", "while", "switch", "synchronized", "when"}

  @filters = [] of RequestFilter
  @registrations = [] of Registration
  @name_bindings = Set(String).new
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
    @name_bindings.clear
    sources = {".java", ".kt"}.flat_map { |ext| collect_files_by_extension(ext) }.reject { |file| test_source?(file) }
    sources.each do |file|
      next unless (content = read_file(file)) && content.includes?("@NameBinding")
      ascii(Noir::CComments.strip(content)).scan(NAME_BINDING) { |match| @name_bindings << match[1] }
    end
    sources.each do |file|
      next unless content = read_file(file)
      code = ascii(Noir::CComments.strip(content))
      module_dir = build_module(file)
      scan_filters(code, file, module_dir) if content.includes?("ContainerRequestFilter")
      scan_registrations(code, module_dir) if content.includes?("register")
    end
    @filters.select! do |filter|
      filter.provider || @registrations.any? { |reg| reg.name == filter.name }
    end
  end

  # Non-ASCII characters as spaces: the walk indexes by character.
  private def ascii(text : String) : String
    text.ascii_only? ? text : text.gsub(/[^\x00-\x7F]/, " ")
  end

  # `code` with every character of a string literal but its letters, digits,
  # `-` and `_` turned into `x`: brackets and keywords in a message do not
  # read as code, and `"OPTIONS"` or `"Authorization"` stay readable.
  private def masked(code : String) : String
    code.gsub(STRING_LITERAL) { |literal| "#{literal[0]}#{literal[1...-1].gsub(/[^\w-]/, "x")}#{literal[-1]}" }
  end

  private def scan_filters(code : String, file : String, module_dir : String?)
    mask = masked(code)
    mask.scan(FILTER_CLASS) do |match|
      name = match[1]
      next if name.matches?(SpringAuthTagger::NON_AUTH_FILTER_NAME)
      start = match.begin(0)
      next unless (open = mask.index('{', match.end(0) - 1)) && (close = Noir::JSLiteralScanner.find_matching_brace(mask, open))
      class_mask = mask[open..close]
      next if class_mask.matches?(/csrf|xsrf/i)
      next unless method = class_mask.match(FILTER_METHOD)
      ctx = method[1]? || method[2]
      body_open = open + method.end(0) - 1
      next unless body_close = Noir::JSLiteralScanner.find_matching_brace(mask, body_open)
      body = code[(body_open + 1)...body_close]
      reading = judge(body, ctx) || next
      refusal, exempt = reading
      annotations = annotations_before(mask, start)
      @filters << RequestFilter.new(
        name: name,
        file_path: file,
        line: code[0, start].count('\n') + 1,
        module_dir: module_dir,
        refusal: refusal,
        exempt: exempt,
        provider: annotations.includes?("Provider"),
        bound: annotations.select { |item| @name_bindings.includes?(item) }
      )
    end
  end

  # The annotation names in front of the declaration at `start`, back to the
  # previous statement or block boundary.
  private def annotations_before(mask : String, start : Int32) : Array(String)
    from = (mask.rindex(/[;{}]/, start - 1) || -1) + 1
    mask[from...start].scan(/@([A-Za-z_$][\w$.]*)/).map(&.[1].split('.').last)
  end

  private def scan_registrations(code : String, module_dir : String?)
    mask = masked(code)
    feature = configure_body(mask)
    mask.scan(REGISTER_CALL) do |call|
      open = call.end(0) - 1
      next unless close = Noir::JSLiteralScanner.find_matching_paren(mask, open)
      exempt = Set(String).new
      if feature && feature[0] < open < feature[1]
        body = mask[(feature[0] + 1)...feature[1]]
        found = conditions_at(body, open - feature[0] - 1)
        next if found.nil? || found[1]
        next unless found[0].all? { |cond, negated| holds?(cond, negated, body, nil, exempt) == :true }
      end
      mask[(open + 1)...close].scan(REGISTERED) do |registered|
        @registrations << Registration.new(registered[1]? || registered[2], module_dir, exempt)
      end
    end
  end

  # `{open, close}` of a `DynamicFeature`'s `configure(ResourceInfo, FeatureContext)` body.
  private def configure_body(mask : String) : {Int32, Int32}?
    return unless mask.includes?("DynamicFeature")
    return unless found = mask.match(/\b(?:void|fun)\s+configure\s*\([^()]*\bResourceInfo\b[^()]*\)[^{]*\{/)
    open = found.end(0) - 1
    return unless close = Noir::JSLiteralScanner.find_matching_brace(mask, open)
    {open, close}
  end

  # `{refusal code, exempting annotations}` when `body` (a `filter` method
  # body) refuses a caller without a credential, nil otherwise.
  private def judge(body : String, ctx : String) : {String, Set(String)}?
    mask = masked(body)
    exempt = Set(String).new
    refusal = nil
    mask.scan(REFUSAL) do |found|
      next if refusal
      at = found.begin(0)
      stop = mask.index(';', at) || mask.size
      next unless code = refusal_code(found[1]?, body[at...stop], body, mask)
      found_conds = conditions_at(mask, at)
      next if found_conds.nil? || found_conds[1]
      seen = Set(String).new
      next unless found_conds[0].all? { |cond, negated| holds?(cond, negated, mask, ctx, seen) == :true }
      exempt.concat(seen)
      refusal = {at, code}
    end
    return unless refusal
    at, code = refusal
    # A `return` before the refusal that this caller can take lets it through.
    mask[0, at].scan(/\breturn\b/) do |found|
      return unless conds = conditions_at(mask, found.begin(0))
      next if conds[1]
      return unless conds[0].any? { |cond, negated| holds?(cond, negated, mask, ctx, exempt) == :false }
    end
    {code, exempt}
  end

  private def refusal_code(exception : String?, statement : String, body : String, mask : String) : String?
    case exception
    when "NotAuthorizedException" then return "401"
    when "ForbiddenException"     then return "403"
    end
    text = statement
    # `throw new WebApplicationException(builder.build())` over a
    # `builder = Response.status(UNAUTHORIZED)` local.
    masked(statement).scan(/\b([a-z_$][\w$]*)\b/) do |ident|
      mask.scan(/\b#{Regex.escape(ident[1])}\s*=(?!=)[^;]*;/) { |assign| text += " " + body[assign.begin(0)...assign.end(0)] }
    end
    return unless found = text.match(REFUSAL_STATUS)
    found[0].matches?(/401|UNAUTHORI/) ? "401" : "403"
  end

  # The conditions on the way from the start of `mask` to `pos`: each `if`
  # and `else` block (and unbraced `if`) around it as `{condition,
  # negated}`, and whether it sits in a lambda or anonymous class (whose
  # `return` does not leave the filter). nil when a block around it is a
  # loop, `catch`, `switch` or anything else noir does not read.
  private def conditions_at(mask : String, pos : Int32) : {Array({String, Bool}), Bool}?
    conds = [] of {String, Bool}
    stack = [] of Int32
    index = 0
    while index < pos
      case mask[index]
      when '{' then stack << index
      when '}' then stack.pop?
      end
      index += 1
    end
    stack.each do |open|
      head = block_head(mask, open)
      case head[0]
      when :try    then next
      when :lambda then return {conds, true}
      when :if
        chain = if_chain(mask, head[1], head[2]) || return
        conds.concat(chain)
      when :else
        chain = else_chain(mask, head[1]) || return
        conds.concat(chain)
      else
        return
      end
    end
    from = (mask.rindex(/[;{}]/, pos - 1) || -1) + 1
    lead = mask[from...pos]
    if found = lead.match(/\A\s*(?:else\s+)?if\s*\(/)
      paren = from + found.end(0) - 1
      return unless (close = Noir::JSLiteralScanner.find_matching_paren(mask, paren)) && mask[(close + 1)...pos].strip.empty?
      chain = if_chain(mask, from + lead.index!("if"), paren) || return
      conds.concat(chain)
    elsif lead.matches?(/\A\s*else\s*\z/)
      chain = else_chain(mask, from + lead.index!("else")) || return
      conds.concat(chain)
    elsif !lead.matches?(/\A[\w$.\s]*\z/)
      return
    end
    {conds, false}
  end

  # What opens the block at `open`: `{:if, if-keyword index, paren index}`,
  # `{:else, else index, 0}`, `{:try, ..}`, `{:lambda, ..}` or `{:other, ..}`.
  private def block_head(mask : String, open : Int32) : {Symbol, Int32, Int32}
    head = mask[0, open].rstrip
    return {:try, 0, 0} if head.ends_with?("try") || head.ends_with?("finally")
    return {:else, head.size - 4, 0} if head.matches?(/\belse\z/)
    return {:lambda, 0, 0} if head.ends_with?("->")
    return {:other, 0, 0} unless head.ends_with?(')')
    depth = 0
    paren = head.size - 1
    while paren >= 0
      depth += 1 if head[paren] == ')'
      depth -= 1 if head[paren] == '('
      break if depth == 0
      paren -= 1
    end
    return {:other, 0, 0} if paren < 0
    word = head[0, paren].match(/([A-Za-z_$][\w$]*)\s*\z/)
    return {:lambda, 0, 0} unless word && KEYWORD_HEADS.includes?(word[1])
    word[1] == "if" ? {:if, word.begin(1), paren} : {:other, 0, 0}
  end

  # The conditions an `if` at `keyword` holds under: its own, and every
  # earlier branch of its `else if` chain negated.
  private def if_chain(mask : String, keyword : Int32, paren : Int32) : Array({String, Bool})?
    return unless close = Noir::JSLiteralScanner.find_matching_paren(mask, paren)
    conds = [{mask[(paren + 1)...close], false}]
    before = mask[0, keyword].rstrip
    return conds unless before.matches?(/\belse\z/)
    earlier = else_chain(mask, before.size - 4) || return
    earlier + conds
  end

  # The conditions an `else` at `keyword` holds under: every branch before it negated.
  private def else_chain(mask : String, keyword : Int32) : Array({String, Bool})?
    before = mask[0, keyword].rstrip
    return unless before.ends_with?('}')
    close = before.size - 1
    depth = 0
    open = close
    while open >= 0
      depth += 1 if mask[open] == '}'
      depth -= 1 if mask[open] == '{'
      break if depth == 0
      open -= 1
    end
    return if open < 0
    head = block_head(mask, open)
    return unless head[0] == :if
    chain = if_chain(mask, head[1], head[2]) || return
    *earlier, own = chain
    earlier + [{own[0], !own[1]}]
  end

  # `cond` (negated when `negated`) for a non-OPTIONS caller without a
  # credential, on an endpoint without the annotations it reads: :true,
  # :false or :unknown. Every annotation read is added to `seen`.
  private def holds?(cond : String, negated : Bool, mask : String, ctx : String?, seen : Set(String)) : Symbol
    verdict = evaluate(cond, mask, ctx, seen)
    return verdict if verdict == :unknown || !negated
    verdict == :true ? :false : :true
  end

  private def evaluate(cond : String, mask : String, ctx : String?, seen : Set(String)) : Symbol
    rules = Noir::TopLevelSplit::Rules.new
    cond = unwrap(cond)
    disjuncts = Noir::TopLevelSplit.split(cond, "||", rules)
    if disjuncts.size > 1
      verdicts = disjuncts.map { |part| evaluate(part, mask, ctx, seen) }
      return :true if verdicts.includes?(:true)
      return verdicts.all?(:false) ? :false : :unknown
    end
    conjuncts = Noir::TopLevelSplit.split(cond, "&&", rules)
    if conjuncts.size > 1
      verdicts = conjuncts.map { |part| evaluate(part, mask, ctx, seen) }
      return :false if verdicts.includes?(:false)
      return verdicts.all?(:true) ? :true : :unknown
    end
    if cond.starts_with?('!') && !cond.starts_with?("!=")
      inner = evaluate(cond[1..], mask, ctx, seen)
      return inner == :unknown ? inner : (inner == :true ? :false : :true)
    end
    atom(cond, mask, ctx, seen)
  end

  private def unwrap(text : String) : String
    text = text.strip
    while text.starts_with?('(') && Noir::JSLiteralScanner.find_matching_paren(text, 0) == text.size - 1
      text = text[1...-1].strip
    end
    text
  end

  private def atom(cond : String, mask : String, ctx : String?, seen : Set(String)) : Symbol
    return :true if cond == "true" || (ctx && cond.starts_with?("#{ctx} ") && cond.matches?(/\A[\w$]+\s+(?:instanceof|is)\s/))
    return :false if cond == "false"
    if read = cond.match(ANNOTATION_READ)
      seen << read[2]
      return read[3]? == "==" ? :true : :false
    end
    # Only a non-OPTIONS request is asked about: an OPTIONS test is false.
    return :false if cond.includes?("OPTIONS") && cond.matches?(/\b(?:getMethod|method)\b/)
    # `principal instanceof T` is false for an absent (null) principal.
    if (found = cond.match(/\A(.+?)\s+instanceof\s/)) && absent?(found[1].strip, mask, ctx)
      return :false
    end
    return :unknown unless found = cond.match(/\A(?:null\s*(==|!=)\s*(.+)|(.+?)\s*(==|!=)\s*null)\z/)
    op = found[1]? || found[4]
    subject = (found[2]? || found[3]).strip
    return :unknown unless absent?(subject, mask, ctx)
    op == "==" ? :true : :false
  end

  # Whether `subject` is null for a caller without a credential: a
  # credential read off the request context, or a local that holds one (or
  # starts null and is only assigned from calls).
  private def absent?(subject : String, mask : String, ctx : String?) : Bool
    if ctx && subject.starts_with?("#{ctx}.") && subject.matches?(CTX_ABSENT)
      return credential_header?(subject)
    end
    return false unless subject.matches?(/\A[a-z_$][\w$]*\z/)
    name = Regex.escape(subject)
    declaration = mask.match(/(?:\b(?:val|var)\s+|[\w$>\]?]\s+)#{name}\s*(?::\s*[\w$.<>?]+\s*)?=(?!=)\s*([^;\n]*)/)
    return false unless declaration
    initial = declaration[1].strip
    unless initial == "null"
      return false unless initial.includes?("(")
      return false unless credential_header?(initial)
    end
    mask.scan(/(?<![\w$.])#{name}\s*=(?!=)\s*([^;\n]*)/) do |assign|
      next if assign.begin(0) < declaration.end(0)
      return false unless assign[1].includes?("(")
      conds = conditions_at(mask, assign.begin(0))
      return false if conds.nil? || conds[1]
      return false if conds[0].any? { |cond, _| cond.matches?(/(?<![\w$.])#{name}\s*==\s*null|null\s*==\s*#{name}\b/) }
    end
    true
  end

  # A header read names a credential (`Authorization`, `X-Api-Key`).
  private def credential_header?(text : String) : Bool
    return true unless text.includes?("getHeaderString")
    return false unless read = text.match(HEADER_READ)
    read[1]?.nil? || read[1].matches?(SpringAuthTagger::CREDENTIAL_NAME)
  end

  private def check_endpoint(endpoint : Endpoint)
    return if endpoint.internal
    annotations = nil
    filter = per_serving_classpath(endpoint, true) do |classpath, _|
      @filters.find do |item|
        applies = ->(owner : String?) { owner.nil? || classpath.nil? || classpath.includes?(owner) }
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
    endpoint.add_tag(Tag.new("auth", "Protected by JAX-RS request filter #{filter.name} (#{filter.refusal})", "jaxrs_auth", filter.file_path, filter.line))
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

  # The annotation lines stacked above line `idx`, multi-line ones included.
  private def annotation_block_above(lines : Array(String), idx : Int32) : Array(String)
    block = [] of String
    depth = 0
    i = idx - 1
    while i >= 0 && i >= idx - 200
      text = lines[i].strip
      depth += text.count(')') - text.count('(')
      if depth > 0 || text.starts_with?('@')
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
