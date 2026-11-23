require "json"
require "yaml"

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
end
