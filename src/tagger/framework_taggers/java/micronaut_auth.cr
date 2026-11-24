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

  record Decision, public_access : Bool, description : String, access : Array(Access::Clause)

  @app_rules = [] of Access::Clause

  def self.target_techs : Array(String)
    ["java_micronaut"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    @app_rules = {".java", ".kt"}.flat_map { |ext| collect_files_by_extension(ext) }.flat_map do |file|
      next [] of Access::Clause unless (content = read_file(file)) && content.includes?("SecurityRule")
      Noir::CComments.strip(content).scan(APP_RULE).map { |found| Access::Clause.unresolved("SecurityRule #{found[1]}", "app SecurityRule #{found[1]}", file) }
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
    return picked if lines.count(&.matches?(/(?:^|\s)class\s+\w/)) < 2
    Decision.new(picked.public_access, picked.description, [Access::Clause.unresolved("@Secured of the file's first class", "@Secured of the file's first class", ctx.path)])
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
