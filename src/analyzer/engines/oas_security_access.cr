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
  # `source` is the guard's text, which stands for the requirement once it
  # passes `Access::MAX_CLAUSES`. The fold stops there: the product of the
  # alternatives grows as the product of their sizes.
  def cnf(requirements : Array(Requirement), schemes : Hash(String, String?)?, source : String) : Access::CNF
    alternatives = requirements.map { |requirement| requirement_cnf(requirement, schemes) }
    joined = alternatives.reduce do |product, alternative|
      return capped(alternatives, source) if product.size > Access::MAX_CLAUSES || alternative.size > Access::MAX_CLAUSES
      Access.either(product, alternative)
    end
    joined.size > Access::MAX_CLAUSES ? capped(alternatives, source) : joined
  end

  # Past the cap, a requirement every alternative of which refuses anonymous
  # callers still does.
  private def capped(alternatives : Array(Access::CNF), source : String) : Access::CNF
    anonymous = Access::Atom.new(:anonymous)
    floor = alternatives.all? do |alternative|
      Access.cell(alternative.map { |atoms| Access::Clause.new(atoms, source) }, anonymous) == false
    end
    floor ? [[Access::Atom.new(:authenticated)]] + unresolved(source) : unresolved(source)
  end

  private def requirement_cnf(requirement : Requirement, schemes) : Access::CNF
    return unresolved(requirement) if requirement.is_a?(String)
    requirement.reduce(Access::CNF.new) { |cnf, (name, scopes)| Access.both(cnf, scheme_cnf(name, scopes, schemes)) }
  end

  private def scheme_cnf(name : String, scopes : Scopes, schemes) : Access::CNF
    # A server checks no scheme the document leaves undefined. A document
    # with no registry at all still asks for a credential of unknown type.
    return unresolved(name) if schemes && !schemes.has_key?(name)
    if scopes.is_a?(Array)
      return [[Access::Atom.new(:authenticated)]] if scopes.empty?
      if SCOPED_TYPES.includes?(schemes.try(&.[name]?))
        blank, named = scopes.partition(&.blank?)
        cnf = named.map { |scope| [Access::Atom.new(:scope, scope)] }
        return cnf if blank.empty?
        # A blank scope names nothing a token can hold.
        return (cnf.empty? ? [[Access::Atom.new(:authenticated)]] : cnf) + unresolved("#{name}: #{blank.to_json}")
      end
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
