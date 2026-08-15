require "../../spec_helper"
require "../../../src/models/locator_keys"

# `LocatorKey#owner` names the subsystem that writes the slot. Its own doc
# comment says it is "read by the integrity spec" — and it was, but only to
# check it was non-blank. Nothing verified that the named subsystem is the one
# that actually writes the key.
#
# So the field that exists to answer "who writes this slot?" could be wrong,
# and one of them was: `EXPRESS_ROUTER_PREFIX` declared
# `analyzer/javascript/express` while `javascript/koa.cr` also writes it. The
# prose above the declaration even said "and by Koa"; the metadata and the
# comment had drifted apart with nothing in between them.
#
# `CodeLocator` is the one channel that carries state across a phase boundary —
# 63 keys written by the detector pass and drained during analysis — so knowing
# who writes what is how anyone reasons about it at all. These examples make the
# ownership metadata true by construction instead of by good intentions.
#
# Companion to `locator_keys_spec.cr` (shape and lifecycle) and
# `registry_integrity_spec.cr` (analyzer/detector/catalog agreement).

# `detector/specification/har` -> `src/detector/detectors/specification/har`
#
# The owner is a logical subsystem path, not a literal one: the layer segment is
# singular (`detector/`) while the directory is plural (`detector/detectors/`).
private def owner_prefix(owner : String) : String
  layer, rest = owner.split("/", 2)
  "src/#{layer}/#{layer}s/#{rest}"
end

private def source_files : Array(String)
  Dir.glob("src/**/*.cr").sort!
end

# path => source with comment lines dropped, read once; every example below
# scans the whole tree.
#
# Comments are stripped because the declarations in `locator_keys.cr` document
# the very call shapes these examples grep for — a doc comment naming
# `ExpressConstants.file_key` would otherwise report the declaration site as a
# writer of its own key.
private def sources : Hash(String, String)
  source_files.to_h do |path|
    stripped = File.read_lines(path).reject(&.lstrip.starts_with?('#')).join('\n')
    {path, stripped}
  end
end

private def declared_keys : Array(Noir::LocatorKey(String) | Noir::LocatorKey(Array(String)))
  keys = [] of Noir::LocatorKey(String) | Noir::LocatorKey(Array(String))
  Noir::LocatorKeys::ARRAY_KEYS.each { |key| keys << key }
  Noir::LocatorKeys::SINGLE_KEYS.each { |key| keys << key }
  keys
end

# Constant name for a key, derived from its wire name: `apisix-json` ->
# `APISIX_JSON`. The table generates the constants from the same string, so this
# reverses that rather than duplicating the list.
private def constant_name_for(key_name : String) : String
  key_name.gsub('-', '_').upcase
end

describe "locator key ownership" do
  it "declares an owner whose subsystem exists" do
    missing = (declared_keys.map(&.owner) + Noir::LocatorKeys::NAMESPACES.map(&.owner))
      .uniq!
      .reject { |owner| Dir.exists?(owner_prefix(owner)) || File.exists?("#{owner_prefix(owner)}.cr") }

    fail <<-MSG unless missing.empty?
      these owners do not resolve to a file or directory under src/: #{missing.sort}
      MSG
  end

  # The load-bearing one. Every `push`/`set` of a declared key must come from
  # the subsystem that claims it.
  it "is written only by the subsystem that owns it" do
    all_sources = sources
    offenders = [] of String

    declared_keys.each do |key|
      constant = constant_name_for(key.name)
      prefix = owner_prefix(key.owner)
      write_call = /\.(?:push|set)\(\s*(?:Noir::)?LocatorKeys::#{Regex.escape(constant)}\b/

      all_sources.each do |path, source|
        next unless source.matches?(write_call)
        next if path.starts_with?(prefix)
        offenders << "#{key.name} (owner #{key.owner}) written by #{path}"
      end
    end

    fail <<-MSG unless offenders.empty?
      a locator key written from outside its declared owner. Either the write
      belongs in the owning subsystem, or the key is shared and `owner` should
      name the layer that actually covers both — an owner that excludes a real
      writer is worse than none, because it is the field everyone trusts to
      answer "who writes this slot".
        #{offenders.sort.join("\n  ")}
      MSG
  end

  # Every declared key must have at least one writer, or it is a slot that can
  # only ever read back empty.
  it "has a writer for every declared key" do
    all_sources = sources
    unwritten = declared_keys.reject do |key|
      constant = constant_name_for(key.name)
      write_call = /\.(?:push|set)\(\s*(?:Noir::)?LocatorKeys::#{Regex.escape(constant)}\b/
      all_sources.any? { |_, source| source.matches?(write_call) }
    end

    fail <<-MSG unless unwritten.empty?
      these keys are declared but never written, so every read returns empty:
      #{unwritten.map(&.name).sort!}
      MSG
  end

  # The runtime-minted family cannot be found by constant name at the push site:
  # the key is a local built from the scanned path. What is greppable is the
  # minting call, centralised in `ExpressConstants`.
  #
  # Minting alone is not writing — `Noir::JSRouteExtractor` mints the same keys
  # to *read* them back, which is the whole point of the namespace. A writer is a
  # file that mints and then pushes, and a push of a minted key takes a local
  # variable rather than a `LocatorKeys::` constant. That pair is what identifies
  # `koa.cr`, `oak.cr`, and `express/router_mount_scanner.cr` — all three resolve
  # cross-file router mount prefixes the same way — and it is the check the
  # `analyzer/javascript/express` owner failed.
  it "writes namespace keys only from the owning subsystem" do
    namespace = Noir::LocatorKeys::EXPRESS_ROUTER_PREFIX
    prefix = owner_prefix(namespace.owner)
    minting = /ExpressConstants\.(?:file|function)_key\b|LocatorKeys::EXPRESS_ROUTER_PREFIX\.key\b/
    local_push = /\.push\(\s*[a-z_][a-z_0-9]*\s*,/

    writers = sources.select { |_, source| source.matches?(minting) && source.matches?(local_push) }.keys
    offenders = writers.reject(&.starts_with?(prefix)).sort!

    fail <<-MSG unless offenders.empty?
      these files write `#{namespace.prefix}` keys from outside the declared
      owner (#{namespace.owner}):
        #{offenders.join("\n  ")}
      MSG

    # Guards this example specifically: if the minting helper is renamed, the
    # scan would find no writers and pass while checking nothing.
    writers.size.should eq 3
  end

  # Guards the guards. Every example above is a source scan, so a broken glob or
  # a mis-derived constant name would make all of them pass vacuously.
  it "resolves every declared key to a constant that exists" do
    declared_keys.size.should eq 63
    source_files.size.should be > 500

    # The regex used above must actually match something for a key known to be
    # written, or the ownership check is inspecting nothing.
    har = sources["src/detector/detectors/specification/har.cr"]
    har.matches?(/\.push\(\s*Noir::LocatorKeys::HAR_PATH\b/).should be_true
  end
end
