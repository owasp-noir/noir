require "json"
require "yaml"
require "../../models/access"

# Reads an OAS2/OAS3 `security` requirement into what it asks of a caller.
# The requirement objects are alternatives; every scheme one object names is
# needed, and an OAuth2 / OpenID Connect scheme needs every scope it lists.
module OasSecurityAccess
  extend self

  # A scheme's scopes, or their JSON text when they are not a list of strings.
  alias Scopes = Array(String) | String
  # One requirement object, or its JSON text when it is not an object.
  alias Requirement = Hash(String, Scopes) | String

  SCOPED_TYPES = {"oauth2", "openIdConnect"}

  # `node` is one entry of a `security` array, a `JSON::Any` or a `YAML::Any`.
  def requirement(node) : Requirement
    return text(node) unless object = node.as_h?
    object.to_h do |name, scopes|
      list = scopes.as_a?.try(&.map(&.as_s?))
      {name.to_s, list && list.all? ? list.compact : text(scopes)}
    end
  end

  # `schemes` maps each defined scheme name to its `type` (nil when it is
  # unreadable, such as a `$ref`), or is nil when the document defines none.
  # `requirements` must not be empty: no `security` requires nothing.
  def cnf(requirements : Array(Requirement), schemes : Hash(String, String?)?) : Access::CNF
    requirements.map { |requirement| requirement_cnf(requirement, schemes) }.reduce { |a, b| Access.either(a, b) }
  end

  private def requirement_cnf(requirement : Requirement, schemes) : Access::CNF
    return unresolved(requirement) if requirement.is_a?(String)
    requirement.reduce(Access::CNF.new) { |cnf, (name, scopes)| Access.both(cnf, scheme_cnf(name, scopes, schemes)) }
  end

  private def scheme_cnf(name : String, scopes : Scopes, schemes) : Access::CNF
    # A server checks no scheme the document leaves undefined.
    return unresolved(name) unless schemes && schemes.has_key?(name)
    if scopes.is_a?(Array)
      return [[Access::Atom.new(:authenticated)]] if scopes.empty?
      return scopes.map { |scope| [Access::Atom.new(:scope, scope)] } if SCOPED_TYPES.includes?(schemes[name])
    end
    # OAS 3.1 lets other scheme types list role names, which no type defines.
    [[Access::Atom.new(:authenticated)]] + unresolved("#{name}: #{scopes.is_a?(Array) ? scopes.join(", ") : scopes}")
  end

  # JSON cannot encode every YAML node (`!!binary`).
  private def text(node) : String
    node.to_json
  rescue
    node.to_s
  end

  private def unresolved(text : String) : Access::CNF
    [[Access::Atom.new(:unresolved, text)]]
  end
end
