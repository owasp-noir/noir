require "../../spec_helper"
require "../../../src/models/locator_keys"

# The typed key API means the compiler rejects an undeclared key outright, so
# these specs cover what a type cannot: that the declarations stay coherent
# and that none of them is dead.
#
# Every example is generated from `DECLARATIONS`, so a key added tomorrow is
# covered without anyone remembering to cover it.
describe "locator key registry" do
  array_keys = Noir::LocatorKeys::ARRAY_KEYS
  single_keys = Noir::LocatorKeys::SINGLE_KEYS

  it "derives one constant per declaration" do
    (array_keys.size + single_keys.size).should eq Noir::LocatorKeys::DECLARATIONS.size
  end

  it "declares each name exactly once" do
    names = array_keys.map(&.name) + single_keys.map(&.name)
    duplicates = names.tally.select { |_, count| count > 1 }.keys
    fail "duplicate key names alias two subsystems onto one slot: #{duplicates.sort}" unless duplicates.empty?
  end

  it "gives every key a name and an owning subsystem" do
    blank = (array_keys.map { |k| {k.name, k.owner} } + single_keys.map { |k| {k.name, k.owner} })
      .select { |name, owner| name.blank? || owner.blank? }
    fail "keys missing a name or owner: #{blank}" unless blank.empty?
  end

  # A key referenced only by its own declaration is dead — that is how
  # `cs-aspnet-core-mvc-entrypoints` survived with zero readers until #2499.
  # This greps for the constant *identifier*, not the string literal, so it
  # has no interpolation blind spot.
  it "keeps every declared key in use" do
    sources = Dir.glob("src/**/*.cr").reject(&.ends_with?("locator_keys.cr"))
    contents = sources.map { |file| File.read(file) }

    unused = Noir::LocatorKeys::DECLARATIONS.compact_map do |declaration|
      constant = declaration[0].to_s
      constant unless contents.any?(&.includes?(constant))
    end

    fail "declared keys nothing references: #{unused.sort}" unless unused.empty?
    sources.size.should be > 500
  end

  it "namespaces mint keys that carry the namespace lifecycle and owner" do
    ns = Noir::LocatorKeys::EXPRESS_ROUTER_PREFIX
    key = ns.key("/app/server.js", "mountRoutes")

    key.name.should eq "express_router_prefix:/app/server.js:mountRoutes"
    key.lifecycle.should eq ns.lifecycle
    key.owner.should eq ns.owner
    ns.matches?(key.name).should be_true
    ns.matches?("express_router_prefix").should be_false
    ns.matches?("other:/app/server.js").should be_false
  end

  it "keeps namespace-minted keys out of the declared constants" do
    # They cannot be constants — the names come from scanned paths — which is
    # why the namespace exists rather than a per-path declaration.
    ns_prefix = Noir::LocatorKeys::EXPRESS_ROUTER_PREFIX.prefix
    array_keys.map(&.name).any?(&.starts_with?(ns_prefix)).should be_false
  end
end

describe "CodeLocator with typed keys" do
  it "keeps the two value shapes in separate maps" do
    locator = CodeLocator.new
    single = Noir::LocatorKey(String).new("shape-single", Noir::LocatorKey::Lifecycle::Process, "spec")
    array = Noir::LocatorKey(Array(String)).new("shape-array", Noir::LocatorKey::Lifecycle::Process, "spec")

    locator.set(single, "one")
    locator.push(array, "two")

    locator.get(single).should eq "one"
    locator.all(array).should eq ["two"]
  end

  it "clears a namespace by prefix without touching declared keys" do
    locator = CodeLocator.new
    ns = Noir::LocatorKeys::EXPRESS_ROUTER_PREFIX

    locator.push(ns.key("/a.js"), "/api")
    locator.push(ns.key("/b.js", "mount"), "/v2")
    locator.push(Noir::LocatorKeys::OAS3_JSON, "/spec/openapi.json")

    locator.clear_namespace(ns)

    locator.all(ns.key("/a.js")).should be_empty
    locator.all(ns.key("/b.js", "mount")).should be_empty
    locator.all(Noir::LocatorKeys::OAS3_JSON).should eq ["/spec/openapi.json"]
  end
end
