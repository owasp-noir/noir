require "yaml"

# Symfony `security:` config (`config/packages/security.yaml`, or
# `app/config/security.yml` before Flex): which firewall a request lands in
# and the `access_control` rule that then decides who may call it.
#
# Symfony's semantics, read here:
#   * the first firewall whose `pattern` matches the path handles the request;
#     `security: false` (or no matching firewall) means no access control runs;
#   * the first `access_control` rule whose `path` (and `methods`) matches
#     decides; its roles are alternatives, and `PUBLIC_ACCESS` /
#     `IS_AUTHENTICATED_ANONYMOUSLY` (or no roles at all) let anyone through.
# A firewall or rule that also conditions on host, IP, port, `allow_if` or a
# request matcher cannot be decided statically, so the answer is "unknown".
module Analyzer::Php::SymfonySecurity
  PUBLIC_ROLES = %w[PUBLIC_ACCESS IS_AUTHENTICATED_ANONYMOUSLY]
  CONDITIONS   = %w[host ip ips port allow_if request_matcher attributes route]
  # An `allow_if` expression is a guard only when, with its string literals
  # masked, it is nothing but check calls joined by `and` / `&&`: no
  # comparison, `xor`, `in`, negation, `or`, ternary or boolean literal.
  ALLOW_IF_STRING_RE = /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/
  ALLOW_IF_CHECK     = /(?:is_authenticated|is_fully_authenticated)\(\s*\)|is_granted\(\s*\x01\s*\)/.source
  ALLOW_IF_ALL       = Regex.new("\\A\\s*(?:#{ALLOW_IF_CHECK})(?:\\s*(?:and|&&)\\s*(?:#{ALLOW_IF_CHECK}))*\\s*\\z")

  # Only a role or an authentication level is certain to refuse an anonymous
  # caller; any other attribute is decided by an application voter, which
  # may grant it to anonymous callers (a default group, say).
  CERTAIN_ATTRIBUTE_RE = /\A(?:ROLE_\w+|IS_AUTHENTICATED(?:_\w+)?|IS_IMPERSONATOR|IS_REMEMBERED)\z/
  VOTER_NOTE           = " (an application voter or setting may grant anonymous callers)"

  def self.voter_note(attribute : String) : String
    attribute.matches?(CERTAIN_ATTRIBUTE_RE) ? "" : VOTER_NOTE
  end

  # Voter note for the `roles:` of an `access_control` rule; its `allow_if`
  # entry (prefixed `allow_if:`) carries its own note.
  def self.roles_note(roles : Array(String)) : String
    return "" if roles.any?(&.includes?(VOTER_NOTE))
    roles.all? { |r| r.starts_with?("allow_if:") || r.matches?(CERTAIN_ATTRIBUTE_RE) } ? "" : VOTER_NOTE
  end

  # The guard an `allow_if` expression puts on every caller, or nil when
  # it can pass anonymously or cannot be decided statically.
  def self.allow_if_guard(expression : String) : String?
    masked = expression.gsub(ALLOW_IF_STRING_RE, "\u{1}")
    return unless ALLOW_IF_ALL.matches?(masked)
    # Only check calls are left, so every literal is an `is_granted` attribute.
    attributes = expression.scan(ALLOW_IF_STRING_RE).map { |m| m[0][1...-1] }
    return if attributes.any? { |attribute| PUBLIC_ROLES.includes?(attribute) }
    # A conjunct that needs a login already refuses anonymous callers.
    login = masked.matches?(/is_(?:fully_)?authenticated/)
    note = login || attributes.all?(&.matches?(CERTAIN_ATTRIBUTE_RE)) ? "" : VOTER_NOTE
    "allow_if: #{expression}#{note}"
  end

  record Firewall, pattern : Regex?, open : Bool, conditional : Bool
  record Rule, path : Regex?, methods : Array(String), roles : Array(String), conditional : Bool

  struct Config
    # Directory of the app the config belongs to: controllers under it use it.
    getter root : String

    def initialize(@root : String, @firewalls : Array(Firewall), @rules : Array(Rule))
    end

    # Roles an anonymous caller of `method url` lacks, or nil when it gets
    # through (or the config cannot tell).
    def required_roles(method : String, url : String) : Array(String)?
      # ponytail: placeholders become one sample segment, so a rule only some
      # values of `{slug}` would match is decided by that one sample.
      path = url.gsub(/\{[^}]*\}/, "1")
      # An undecidable entry only blocks the answer for paths it covers; it
      # is tried against a second sample too, so `^/page/[a-z]` covers `{slug}`.
      other = url.gsub(/\{[^}]*\}/, "a")
      covers = ->(re : Regex?, undecidable : Bool) { re.nil? || re.matches?(path) || (undecidable && re.matches?(other)) }
      firewall = @firewalls.find { |f| covers.call(f.pattern, f.conditional) }
      return if firewall.nil? || firewall.conditional || firewall.open

      rule = @rules.find do |r|
        covers.call(r.path, r.conditional) && (r.methods.empty? || r.methods.includes?(method.upcase))
      end
      return if rule.nil? || rule.conditional || rule.roles.empty?
      return if rule.roles.any? { |role| PUBLIC_ROLES.includes?(role) }
      rule.roles
    end
  end

  # The security config in `path`, if it is one.
  def self.config?(path : String, & : -> String) : Config?
    return unless {"security.yaml", "security.yml"}.includes?(File.basename(path))
    dir = File.dirname(File.expand_path(path))
    return unless {"packages", "config"}.includes?(File.basename(dir))

    security = YAML.parse(yield).as_h?.try(&.[YAML::Any.new("security")]?).try(&.as_h?)
    return unless security

    firewalls = (security[YAML::Any.new("firewalls")]?.try(&.as_h?) || {} of YAML::Any => YAML::Any).values.compact_map do |node|
      fw = node.as_h? || next
      # Symfony ignores `pattern:` when a `request_matcher:` is set.
      Firewall.new(fw.has_key?(YAML::Any.new("request_matcher")) ? nil : regex(fw[YAML::Any.new("pattern")]?), fw[YAML::Any.new("security")]?.try(&.raw) == false, conditional?(fw))
    end
    rules = (security[YAML::Any.new("access_control")]?.try(&.as_a?) || [] of YAML::Any).compact_map do |node|
      rule = node.as_h? || next
      roles = rule[YAML::Any.new("roles")]? || rule[YAML::Any.new("role")]?
      names = strings(roles)
      expression = rule[YAML::Any.new("allow_if")]?.try(&.as_s?)
      guard = expression.try { |source| allow_if_guard(source) }
      names << guard if guard
      Rule.new(regex(rule[YAML::Any.new("path")]?), strings(rule[YAML::Any.new("methods")]?).map(&.upcase), names, conditional?(rule, !guard.nil?))
    end

    # `.../app/config/security.yml` serves `.../src`; `.../config/packages/` serves `.../src` too.
    root = dir.rchop("/packages").rchop("/config").rchop("/app")
    Config.new(root, firewalls, rules)
  rescue YAML::ParseException
    nil
  end

  private def self.conditional?(entry : Hash(YAML::Any, YAML::Any), allow_if_guards : Bool = false) : Bool
    CONDITIONS.any? { |key| entry.has_key?(YAML::Any.new(key)) && !(allow_if_guards && key == "allow_if") }
  end

  private def self.regex(node : YAML::Any?) : Regex?
    node.try(&.as_s?).try { |source| Regex.new(source) }
  rescue ArgumentError
    # An unparsable pattern matches nothing we can vouch for.
    Regex.new("(?!)")
  end

  # A scalar, a comma-separated scalar, or a list.
  private def self.strings(node : YAML::Any?) : Array(String)
    return [] of String unless node
    return node.as_a.compact_map(&.as_s?) if node.as_a?
    node.as_s?.try(&.split(',').map(&.strip).reject(&.empty?)) || [] of String
  end
end
