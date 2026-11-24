require "../analyzer/engines/oas_security_access"
require "../utils/top_level_split"

# Reads one alternative of a Huma `[]map[string][]string{...}` security
# literal (`{"bearer": {"read", "write"}, "key": {}}`) into the requirement
# object OpenAPI `security` would hold.
module HumaSecurity
  extend self

  ENTRY = /\A(?:"([^"\\]*)"|([A-Za-z_][\w.]*))\s*:\s*(.+)\z/m
  LIST  = /\A(?:\[\]string\s*)?\{(.*)\}\z/m
  WORD  = /\A"([^"\\]*)"\z/
  RULES = Noir::TopLevelSplit::Rules.new(empties: Noir::TopLevelSplit::Empties::DropAll)

  # Every entry names a scheme, so it still asks for a credential when its
  # name or scopes are not literals: those stay text, which reads as a
  # credential plus what was not read.
  def requirement(alternative : String) : OasSecurityAccess::Requirement
    requirement = Hash(String, OasSecurityAccess::Scopes).new
    Noir::TopLevelSplit.split(alternative.strip.lchop('{').rchop('}'), ',', RULES).each do |entry|
      unless found = entry.match(ENTRY)
        requirement[entry] = entry
        next
      end
      if name = found[1]?
        requirement[name] = scopes(found[3].strip)
      else
        requirement[found[2]] = entry
      end
    end
    requirement
  end

  # A nil `[]string` holds no scopes, like `{}`.
  private def scopes(value : String) : OasSecurityAccess::Scopes
    return [] of String if value == "nil"
    list = value.match(LIST) || return value
    Noir::TopLevelSplit.split(list[1], ',', RULES).map { |item| item.match(WORD).try(&.[1]) || return value }
  end
end
