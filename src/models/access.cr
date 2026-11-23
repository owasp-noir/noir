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

    def to_s(io : IO) : Nil
      io << '(' if @any_of.size > 1
      @any_of.join(io, " | ")
      io << ')' if @any_of.size > 1
    end
  end

  # What changed between two requirements of one endpoint. `widened` holds
  # old clauses no new clause implies even when every unread check is taken
  # for the same one; `unverified` holds those implied only under that
  # lenient reading, i.e. an unread check whose text changed.
  record Change, widened : Array(Clause), unverified : Array(Clause) do
    def empty? : Bool
      widened.empty? && unverified.empty?
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
      return requires unless requires.empty?
      # A guard whose condition always holds (`hasRole('A') or permitAll()`).
      return [Clause.new([Atom.new(Kind::Anonymous)], tag.description, tag.path, tag.line)]
    end
    case tag.name
    when "auth"
      [Clause.new([Atom.new(Kind::Authenticated)], tag.description, tag.path, tag.line),
       Clause.unresolved(tag.description, tag.description, tag.path, tag.line)]
    when "authz"
      [Clause.unresolved(tag.description, tag.description, tag.path, tag.line)]
    when "anonymous"
      [Clause.new([Atom.new(Kind::Anonymous)], tag.description, tag.path, tag.line)]
    else
      [] of Clause
    end
  end

  # Empty means no guard was found. A declaration that admits anonymous
  # callers does not lift a guard another layer applies: a Spring chain rule
  # still refuses them ahead of a `@PermitAll` handler.
  def self.of(endpoint : Endpoint) : Array(Clause)
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

  # Clauses are matched on their atoms alone: source and location are kept
  # for the reviewer, and a moved or reformatted declaration is no change.
  def self.compare(old : Array(Clause), new : Array(Clause)) : Change
    lost = old.reject do |clause|
      clause.any_of.any?(&.kind.anonymous?) || new.any? { |held| implies?(held, clause, lenient: false) }
    end
    # An unread check stands in for one reworded check at most: a new clause
    # that already accounts for an old one, or that adds an unread
    # alternative, covers nothing more. Otherwise deleting one of two unread
    # guards would pass as a rewording of the other.
    spare = new.reject { |held| old.any? { |clause| implies?(held, clause, lenient: false) } }
    widened = [] of Clause
    unverified = [] of Clause
    lost.each do |clause|
      index = spare.index do |held|
        implies?(held, clause, lenient: true) && held.any_of.count(&.kind.unresolved?) <= clause.any_of.count(&.kind.unresolved?)
      end
      if index
        spare.delete_at(index)
        unverified << clause
      else
        widened << clause
      end
    end
    Change.new(widened, unverified)
  end

  private def self.implies?(held : Clause, required : Clause, lenient : Bool) : Bool
    held.any_of.all? { |a| required.any_of.any? { |b| implies?(a, b, lenient) } }
  end

  private def self.implies?(a : Atom, b : Atom, lenient : Bool) : Bool
    return true if b.kind.anonymous? || a.kind.deny? || a == b
    return true if b.kind.authenticated? && (a.kind.role? || a.kind.permission? || a.kind.scope?)
    lenient && a.kind.unresolved? && b.kind.unresolved?
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

  VALUED_KINDS = [Kind::Role, Kind::Permission, Kind::Scope]

  # `role:ADMIN`, `permission:posts:write`, or a bare kind (`authenticated`).
  # Split at the first colon: values carry colons of their own. A bare
  # `unresolved` matches any fragment, so it takes none.
  def self.parse_atom(text : String) : Atom
    name, colon, value = text.strip.partition(':')
    name = name.strip
    value = value.strip
    # `Kind.parse?` would also take `r_o_l_e`.
    unless kind = Kind.values.find { |candidate| candidate.to_s.compare(name, case_insensitive: true) == 0 }
      raise ArgumentError.new("unknown kind #{name.empty? ? "(none)" : name}. Valid: #{Kind.names.map(&.downcase).join(", ")}")
    end
    if VALUED_KINDS.includes?(kind)
      raise ArgumentError.new("#{kind.to_s.downcase} needs a value (#{kind.to_s.downcase}:<value>)") if value.empty?
      Atom.new(kind, value)
    else
      raise ArgumentError.new("#{kind.to_s.downcase} takes no value") unless colon.empty?
      Atom.new(kind)
    end
  end
end
