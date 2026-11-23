require "json"
require "yaml"
require "./endpoint"

# What a caller must hold to reach an endpoint, as a positive CNF: every
# clause must hold, and a clause holds when any of its atoms does. An
# `Unresolved` atom carries the source fragment a reader could not read and
# never counts as held.
module Access
  enum Kind
    Role
    Permission
    Scope
    Authenticated
    Anonymous
    Deny
    Unresolved
  end

  struct Atom
    include JSON::Serializable
    include YAML::Serializable
    include Comparable(Atom)

    getter kind : Kind
    @[JSON::Field(emit_null: false)]
    @[YAML::Field(emit_null: false)]
    getter value : String?

    def initialize(@kind : Kind, @value : String? = nil)
    end

    def <=>(other : Atom)
      {@kind.value, @value || ""} <=> {other.kind.value, other.value || ""}
    end

    def to_s(io : IO) : Nil
      io << @kind.to_s.downcase
      io << ':' << @value if @value && !@kind.unresolved?
    end
  end

  struct Clause
    include JSON::Serializable
    include YAML::Serializable

    getter any_of : Array(Atom)
    getter source : String
    @[JSON::Field(emit_null: false)]
    @[YAML::Field(emit_null: false)]
    getter path : String?
    @[JSON::Field(emit_null: false)]
    @[YAML::Field(emit_null: false)]
    getter line : Int32?

    def initialize(@any_of : Array(Atom), @source : String, @path : String? = nil, @line : Int32? = nil)
      after_initialize
    end

    def self.unresolved(fragment : String, source : String, path : String? = nil, line : Int32? = nil) : Clause
      new([Atom.new(Kind::Unresolved, fragment)], source, path, line)
    end

    # Deserialization skips `initialize`, so canonical form is set here.
    def after_initialize
      raise ArgumentError.new("an access clause needs at least one atom") if @any_of.empty?
      @any_of = @any_of.uniq.sort!
    end
  end

  # The empty CNF is TRUE: it requires nothing.
  alias CNF = Array(Array(Atom))

  MAX_CLAUSES = 8

  def self.both(a : CNF, b : CNF) : CNF
    a + b
  end

  def self.either(a : CNF, b : CNF) : CNF
    a.flat_map { |left| b.map { |right| (left + right).uniq.sort! } }.uniq!
  end

  def self.clauses(cnf : CNF, source : String, path : String? = nil, line : Int32? = nil) : Array(Clause)
    return [Clause.unresolved(source, source, path, line)] if cnf.size > MAX_CLAUSES
    cnf.map { |atoms| Clause.new(atoms, source, path, line) }.uniq!
  end

  # A guard tag whose tagger records no requirement still states that a guard
  # exists, so it reads as signed-in plus something noir could not read.
  def self.of(tag : Tag) : Array(Clause)
    if requires = tag.requires
      return requires
    end
    case tag.name
    when "auth"
      [Clause.new([Atom.new(Kind::Authenticated)], tag.description, tag.path, tag.line),
       Clause.unresolved(tag.description, tag.description, tag.path, tag.line)]
    when "authz"
      [Clause.unresolved(tag.description, tag.description, tag.path, tag.line)]
    else
      [] of Clause
    end
  end

  # Empty means no guard was found. An `anonymous` tag overrides every guard
  # tag, as it does in `NoirAIContext`.
  def self.of(endpoint : Endpoint) : Array(Clause)
    if open = endpoint.tags.find { |tag| tag.name == "anonymous" }
      return [Clause.new([Atom.new(Kind::Anonymous)], open.description, open.path, open.line)]
    end
    endpoint.tags.flat_map { |tag| of(tag) }.uniq!
  end

  # true allowed, false denied, nil unknown. `principal` is a caller holding
  # exactly that one value, signed in unless it is the anonymous principal.
  def self.cell(clauses : Array(Clause), principal : Atom) : Bool?
    results = clauses.map { |clause| admits?(clause, principal) }
    return false if results.any? { |result| result == false }
    return if results.any?(Nil)
    true
  end

  def self.principals(clauses : Enumerable(Clause)) : Array(Atom)
    held = clauses.flat_map(&.any_of).select { |atom| atom.kind.role? || atom.kind.permission? || atom.kind.scope? }
    [Atom.new(Kind::Anonymous), Atom.new(Kind::Authenticated)] + held.uniq.sort!
  end

  private def self.admits?(clause : Clause, principal : Atom) : Bool?
    results = clause.any_of.map { |atom| admits?(atom, principal) }
    return true if results.any? { |result| result == true }
    return false if results.all? { |result| result == false }
    nil
  end

  private def self.admits?(atom : Atom, principal : Atom) : Bool?
    case atom.kind
    in .anonymous?                   then true
    in .deny?                        then false
    in .authenticated?               then !principal.kind.anonymous?
    in .unresolved?                  then nil
    in .role?, .permission?, .scope? then atom == principal
    end
  end
end
