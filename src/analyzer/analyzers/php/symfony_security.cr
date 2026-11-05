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
  # An `allow_if` expression that every caller must satisfy and that asks for
  # a login or a permission, never one that can also pass anonymously.
  ALLOW_IF_CHECK_RE  = /\b(?:is_authenticated|is_fully_authenticated|is_remember_me|is_granted|has_role)\s*\(/
  ALLOW_IF_OPENER_RE = /\bor\b|\|\||\bnot\b|!|\bPUBLIC_ACCESS\b|\bIS_AUTHENTICATED_ANONYMOUSLY\b|\?/

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
      firewall = @firewalls.find { |f| f.conditional || f.pattern.nil? || f.pattern.try(&.matches?(path)) }
      return if firewall.nil? || firewall.conditional || firewall.open

      rule = @rules.find do |r|
        r.conditional || ((r.path.nil? || r.path.try(&.matches?(path))) && (r.methods.empty? || r.methods.includes?(method.upcase)))
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
      Firewall.new(regex(fw[YAML::Any.new("pattern")]?), fw[YAML::Any.new("security")]?.try(&.raw) == false, conditional?(fw))
    end
    rules = (security[YAML::Any.new("access_control")]?.try(&.as_a?) || [] of YAML::Any).compact_map do |node|
      rule = node.as_h? || next
      roles = rule[YAML::Any.new("roles")]? || rule[YAML::Any.new("role")]?
      names = strings(roles)
      expression = rule[YAML::Any.new("allow_if")]?.try(&.as_s?)
      guarding = !expression.nil? && expression.matches?(ALLOW_IF_CHECK_RE) && !expression.matches?(ALLOW_IF_OPENER_RE)
      names << "allow_if: #{expression}" if guarding
      Rule.new(regex(rule[YAML::Any.new("path")]?), strings(rule[YAML::Any.new("methods")]?).map(&.upcase), names, conditional?(rule, guarding))
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
