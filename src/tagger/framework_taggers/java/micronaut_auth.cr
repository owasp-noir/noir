require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "micronaut_auth", name: "Micronaut Auth Tagger", desc: "Identifies Micronaut @Secured rules, including anonymous access", order: 265)]
class MicronautAuthTagger < FrameworkTagger
  # The argument decides. `IS_ANONYMOUS` admits everyone. `IS_AUTHENTICATED`
  # and a role do not. A missing argument stays a guard.
  SECURED = /[@.]Secured\b\s*(?:\(([^)]*)\))?/

  def self.target_techs : Array(String)
    ["java_micronaut"]
  end

  private def check_endpoint(endpoint : Endpoint)
    read_source_context(endpoint).each do |ctx|
      decision = secured_decision(ctx)
      next unless decision
      if decision[:public_access]
        endpoint.add_tag(Tag.new("anonymous", "Micronaut @Secured(IS_ANONYMOUS) admits anonymous callers", "micronaut_auth"))
      else
        endpoint.add_tag(Tag.new("auth", decision[:description], "micronaut_auth"))
      end
      return
    end
  end

  private def secured_decision(ctx : SourceContext) : NamedTuple(public_access: Bool, description: String)?
    line = ctx.line
    return unless line

    lines = Noir::CComments.strip(ctx.full_content).split('\n', remove_empty: false)
    found = member_secured(lines, line - 1)
    return pick_secured(found) unless found.empty?

    class_found = [] of NamedTuple(public_access: Bool, description: String)
    class_annotation_lines(lines).each do |raw|
      item = secured_annotation(raw)
      class_found << item if item
    end
    pick_secured(class_found)
  end

  private def member_secured(lines : Array(String), endpoint_idx : Int32) : Array(NamedTuple(public_access: Bool, description: String))
    found = [] of NamedTuple(public_access: Bool, description: String)
    return found unless 0 <= endpoint_idx < lines.size

    idx = endpoint_idx - 1
    while idx >= 0 && idx >= endpoint_idx - 15
      current = lines[idx].strip
      if current.empty?
        idx -= 1
        next
      end
      break if member_boundary?(current)
      if item = secured_annotation(current)
        found << item
      end
      idx -= 1
    end

    annotation_lines_below(lines, endpoint_idx, "@").each do |below|
      if item = secured_annotation(below)
        found << item
      end
    end
    found
  end

  private def secured_annotation(line : String) : NamedTuple(public_access: Bool, description: String)?
    return unless match = line.match(SECURED)
    arg = match[1]?
    if arg && arg.match(/\bIS_ANONYMOUS\b/)
      {public_access: true, description: ""}
    else
      {public_access: false, description: "Protected by Micronaut @Secured"}
    end
  end

  private def pick_secured(found : Array(NamedTuple(public_access: Bool, description: String))) : NamedTuple(public_access: Bool, description: String)?
    found.find { |item| !item[:public_access] } || found.first?
  end

  private def member_boundary?(line : String) : Bool
    return true if line.starts_with?("public ") || line.starts_with?("private ") || line.starts_with?("protected ")
    return true if line.starts_with?("class ") || line.matches?(/(?:^|\s)class\s+\w/)
    return true if line.starts_with?('}') || line.ends_with?('}') || line.ends_with?(';')
    line.matches?(/(?:^|\s)fun\s/)
  end

  private def class_annotation_lines(lines : Array(String)) : Array(String)
    lines.each_with_index do |raw, idx|
      stripped = raw.strip
      next unless stripped.matches?(/(?:^|\s)class\s+\w/)
      collected = [] of String
      cursor = idx - 1
      while cursor >= 0
        prev = lines[cursor].strip
        if prev.empty?
          cursor -= 1
          next
        end
        break unless prev.starts_with?('@')
        collected << prev
        cursor -= 1
      end
      return collected
    end
    [] of String
  end
end
