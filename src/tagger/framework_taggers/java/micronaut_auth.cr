require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "./java_access"

@[Noir::TaggerFor(key: "micronaut_auth", name: "Micronaut Auth Tagger", desc: "Identifies Micronaut @Secured rules, including anonymous access", order: 265)]
class MicronautAuthTagger < FrameworkTagger
  # The argument decides. `IS_ANONYMOUS` admits everyone. `IS_AUTHENTICATED`
  # and a role do not. A missing argument stays a guard.
  SECURED = /[@.]Secured\b\s*(?:\(([^)]*)\))?/
  # An app's own `SecurityRule` may decide ahead of `SecuredAnnotationRule`.
  APP_RULE = /\bclass\s+([A-Za-z_$][\w$]*)[^{;]*?(?:\b(?:implements|extends)\s+[^{;]*?|:\s*[^{;]*?)\b(?:SecurityRule|AbstractSecurityRule)\b/

  # JSR-250 annotations, which micronaut-security's annotation processor
  # maps onto `@Secured` (`Jakarta*AnnotationMapper`).
  JSR250      = /@(?:[\w.]*\.)?(RolesAllowed|PermitAll|DenyAll)\b/
  MAPPER      = /micronaut-security-(?:processor|annotations)\b/
  IP_PATTERNS = /\bip-patterns\b|\bipPatterns\b/
  CONFIG_FILE = /\Aapplication(?:-[^\/]+)?\.(?:ya?ml|properties|toml|groovy|json)\z/

  record Decision, public_access : Bool, description : String, access : Array(Access::Clause)

  @app_rules = [] of Access::Clause
  @mapped = false

  def self.target_techs : Array(String)
    ["java_micronaut"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @app_rules = {".java", ".kt"}.flat_map { |ext| collect_files_by_extension(ext) }.flat_map do |file|
      next [] of Access::Clause unless (content = read_file(file)) && content.includes?("SecurityRule")
      Noir::CComments.strip(content).scan(APP_RULE).map { |found| Access::Clause.unresolved("SecurityRule #{found[1]}", "app SecurityRule #{found[1]}", file) }
    end
    # `IpPatternsRule` runs ahead of `SecuredAnnotationRule` and only rejects.
    {".yml", ".yaml", ".properties", ".toml", ".groovy", ".json"}.flat_map { |ext| collect_files_by_extension(ext) }.each do |file|
      next unless File.basename(file).matches?(CONFIG_FILE) && (content = read_file(file)) && content.matches?(IP_PATTERNS)
      @app_rules << Access::Clause.unresolved("micronaut.security.ip-patterns", "micronaut.security.ip-patterns", file)
    end
    @mapped = {"pom.xml", "build.gradle", "build.gradle.kts"}.any? do |name|
      get_files_by_basename(name).any? { |file| read_file(file).try(&.matches?(MAPPER)) }
    end
    super
  end

  private def check_endpoint(endpoint : Endpoint)
    read_source_context(endpoint).each do |ctx|
      decision = secured_decision(ctx)
      next unless decision
      access = decision.access + @app_rules
      if decision.public_access
        endpoint.add_tag(Tag.new("anonymous", "Micronaut @Secured(IS_ANONYMOUS) admits anonymous callers", "micronaut_auth", requires: access.empty? ? nil : access))
      else
        endpoint.add_tag(Tag.new("auth", decision.description, "micronaut_auth", requires: guard(access, decision.description)))
      end
      return
    end
  end

  # A guard read as open (`@Secured("isAnonymous()")`, which the tag's own
  # test misses) says so with an `anonymous` clause: an empty list would
  # read the same, but a guard never carries one.
  private def guard(access : Array(Access::Clause), description : String) : Array(Access::Clause)
    return [Access::Clause.new([Access::Atom.new(:anonymous)], description)] if access.empty?
    JavaAccess.signed_in(access, description)
  end

  # `@Secured` on the method replaces the class's: Micronaut's method
  # annotation metadata takes the class annotation of the same type only
  # when the method has none, and `SecuredAnnotationRule` reads that.
  private def secured_decision(ctx : SourceContext) : Decision?
    line = ctx.line
    return unless line

    lines = Noir::CComments.strip(ctx.full_content).split('\n', remove_empty: false)
    found = member_secured(lines, line - 1, ctx.path)
    return pick_secured(found) unless found.empty?

    class_found = class_annotation_lines(lines).compact_map { |idx| secured_annotation(lines, idx, ctx.path) }
    return unless picked = pick_secured(class_found)
    # The annotation is the file's first class's: with another class in the
    # file it may not be the endpoint's.
    if lines.count(&.matches?(/(?:^|\s)class\s+\w/)) >= 2
      picked = Decision.new(picked.public_access, picked.description, [Access::Clause.unresolved("@Secured of the file's first class", "@Secured of the file's first class", ctx.path)])
    end
    jsr250_over(picked, lines, line - 1, ctx.path)
  end

  # A JSR-250 annotation on the method replaces the class's `@Secured` once
  # it is mapped onto `@Secured`: `@RolesAllowed` keeps its values,
  # `@DenyAll` becomes `denyAll()`, `@PermitAll` `isAnonymous()`. Without
  # the mapper in the build, the class's `@Secured` still decides, so the
  # requirement holds either way and stays partly unread. `@PermitAll` keeps
  # an `auth` tag, so it is read as unread rather than open.
  private def jsr250_over(picked : Decision, lines : Array(String), endpoint_idx : Int32, path : String) : Decision
    member = member_indices(lines, endpoint_idx).compact_map do |idx|
      next unless found = lines[idx].match(JSR250)
      if found[1] == "PermitAll"
        Access::Clause.unresolved("@PermitAll", "@PermitAll", path, idx + 1)
      elsif ann = JavaAccess.annotation_in(lines, idx, found[1])
        cnf = found[1] == "DenyAll" ? [[Access::Atom.new(:deny)]] : JavaAccess.micronaut(JavaAccess::Annotation.new("Secured", ann.args, ann.text))
        {cnf, ann.text, idx + 1}
      else
        Access::Clause.unresolved(lines[idx].strip, lines[idx].strip, path, idx + 1)
      end
    end
    return picked if member.empty?
    first = member.first
    jsr = case first
          when Access::Clause then [first]
          else                     Access.clauses(first[0], first[1], path, first[2])
          end
    return Decision.new(picked.public_access, picked.description, jsr) if @mapped
    either = Access.either(jsr.map(&.any_of), picked.access.map(&.any_of))
    unread = Access::Clause.unresolved("#{jsr.first.source} without micronaut-security-processor", "JSR-250 mapping", path)
    Decision.new(picked.public_access, picked.description, Access.clauses(either, jsr.first.source, path) + [unread])
  end

  # The indices of the annotation lines of the member at `endpoint_idx`.
  private def member_indices(lines : Array(String), endpoint_idx : Int32) : Array(Int32)
    found = [] of Int32
    return found unless 0 <= endpoint_idx < lines.size
    idx = endpoint_idx - 1
    while idx >= 0 && idx >= endpoint_idx - 15
      current = lines[idx].strip
      if current.empty?
        idx -= 1
        next
      end
      break if member_boundary?(current)
      found << idx
      idx -= 1
    end
    found + below_indices(lines, endpoint_idx) + [endpoint_idx]
  end

  private def member_secured(lines : Array(String), endpoint_idx : Int32, path : String) : Array(Decision)
    found = [] of Decision
    return found unless 0 <= endpoint_idx < lines.size

    idx = endpoint_idx - 1
    while idx >= 0 && idx >= endpoint_idx - 15
      current = lines[idx].strip
      if current.empty?
        idx -= 1
        next
      end
      break if member_boundary?(current)
      if item = secured_annotation(lines, idx, path)
        found << item
      end
      idx -= 1
    end

    below_indices(lines, endpoint_idx).each do |below|
      if item = secured_annotation(lines, below, path)
        found << item
      end
    end
    found
  end

  # The indices of `annotation_lines_below`'s lines.
  private def below_indices(lines : Array(String), endpoint_idx : Int32) : Array(Int32)
    cursor = endpoint_idx
    annotation_lines_below(lines, endpoint_idx, "@").map do |text|
      cursor += 1
      while cursor < lines.size - 1 && lines[cursor].strip != text
        cursor += 1
      end
      cursor
    end
  end

  private def secured_annotation(lines : Array(String), idx : Int32, path : String) : Decision?
    return unless match = lines[idx].strip.match(SECURED)
    arg = match[1]?
    access =
      if ann = JavaAccess.annotation_in(lines, idx, "Secured")
        Access.clauses(JavaAccess.micronaut(ann), ann.text, path, idx + 1)
      else
        [Access::Clause.unresolved(lines[idx].strip, lines[idx].strip, path, idx + 1)]
      end
    if arg && arg.match(/\bIS_ANONYMOUS\b/)
      Decision.new(true, "", access)
    else
      Decision.new(false, "Protected by Micronaut @Secured", access)
    end
  end

  private def pick_secured(found : Array(Decision)) : Decision?
    found.find { |item| !item.public_access } || found.first?
  end

  private def member_boundary?(line : String) : Bool
    return true if line.starts_with?("public ") || line.starts_with?("private ") || line.starts_with?("protected ")
    return true if line.starts_with?("class ") || line.matches?(/(?:^|\s)class\s+\w/)
    return true if line.starts_with?('}') || line.ends_with?('}') || line.ends_with?(';')
    line.matches?(/(?:^|\s)fun\s/)
  end

  # The indices of the annotation lines stacked above the first class.
  private def class_annotation_lines(lines : Array(String)) : Array(Int32)
    lines.each_with_index do |raw, idx|
      stripped = raw.strip
      next unless stripped.matches?(/(?:^|\s)class\s+\w/)
      collected = [] of Int32
      cursor = idx - 1
      while cursor >= 0
        prev = lines[cursor].strip
        if prev.empty?
          cursor -= 1
          next
        end
        break unless prev.starts_with?('@')
        collected << cursor
        cursor -= 1
      end
      return collected
    end
    [] of Int32
  end
end
