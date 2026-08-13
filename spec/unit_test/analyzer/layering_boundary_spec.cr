require "../../spec_helper"

# AGENTS.md §"Analyzer Layering" states the rule this spec enforces:
#
#   **Rule**: the framework adapter receives routes; it does not walk the
#   filesystem or parse tokens itself.
#
# That rule has been prose for as long as it has existed, and prose binds
# nobody — least of all a contributor (or an agent) who never opens
# AGENTS.md. The three layers exist precisely so that file walking lives in
# one place per language (`src/analyzer/engines/{lang}_engine.cr`, which owns
# the walk, the worker pool and the content cache) and parsing in another
# (`src/miniparsers/`). An adapter that opens its own directory bypasses the
# detector's subtree pruning, `--exclude-path`, the media filter and the
# content cache all at once — silently, and only on the codebases that
# happen to have the directory in question.
#
# This spec is a *ratchet*, not a cleanup: the known offenders are listed
# below with the reason each one is still there. Entries may be deleted,
# never added. A new analyzer that reaches for `Dir.glob` fails here and is
# told which layer the work belongs in.
#
# Companion to `spec/unit_test/analyzer/options_boundary_spec.cr`, which
# ratchets the same way for the options hash.

# Repo-relative glob: `crystal spec` runs from the repository root (same
# assumption as options_boundary_spec.cr and
# spec/unit_test/detector/applicable_lookup_fidelity_spec.cr).
private def adapter_sources : Array(String)
  Dir.glob("src/analyzer/analyzers/**/*.cr").sort
end

private def offending_lines(pattern : Regex, allowed : Array(String)) : Array(String)
  adapter_sources.reject { |file| allowed.includes?(file) }.flat_map do |file|
    File.read_lines(file).each_with_index.compact_map do |line, index|
      stripped = line.strip
      next if stripped.starts_with?("#") # a comment describing the rule is not a violation
      "#{file}:#{index + 1}: #{stripped}" if stripped.matches?(pattern)
    end
  end
end

# Directory enumeration: the walk belongs to layer L0.
DIRECTORY_WALK_RE = /\bDir\.(?:glob|each_child|children|entries)\b/

# Raw `File.*` I/O. The negative lookbehind is what keeps `Noir::TextFile.read`
# — the sanctioned reader, and the fallback inside `read_file_content` itself —
# from matching: the literal `File.read` is a substring of `TextFile.read`, so
# a bare `\bFile\.read\b` would flag every correct call site in the tree.
RAW_FILE_IO_RE = /(?<![\w:])File\.(?:open|read|read_lines|write|each_line)\b/

# Hand-rolled copies of `read_file_content`'s cache-miss body.
CONTENT_FALLBACK_RE = /CodeLocator\.instance\.content_for\([^)]*\)\s*\|\|/

# Adapters that still enumerate directories themselves, with the reason.
#
# Each of these walks a tree the detector's `file_map` does not usefully
# index — build metadata, resource bundles, or a user-supplied path outside
# the scan base. Folding them into their language engine (or exposing the
# lookup on `CodeLocator`, the way `files_by_basename` was added for
# Django's ROOT_URLCONF) is the fix; none of it belongs in this commit.
DIRECTORY_WALK_ALLOWLIST = [
  # Static-resource directories declared in Spring config: the endpoint set
  # is "every file under this directory", which no per-extension index
  # answers.
  "src/analyzer/analyzers/kotlin/spring.cr",
  # Same shape for Quarkus' `META-INF/resources` and Dropwizard's config
  # YAML, which is located by convention relative to the project root
  # rather than by extension.
  "src/analyzer/analyzers/java/quarkus.cr",
  "src/analyzer/analyzers/java/dropwizard.cr",
  # Android navigation graphs / `buildSrc` / `res/values`: XML resource
  # directories addressed by their role in the project layout.
  "src/analyzer/analyzers/mobile/android.cr",
  # Xcode project metadata (`*.xcconfig`, `project.pbxproj`,
  # `*.xcodeproj`) — a documented fallback for when the scanned-file index
  # has no entry.
  "src/analyzer/analyzers/mobile/ios.cr",
  # `--ai-provider` analyzer: globs a user-supplied include pattern, which
  # is by construction not a `file_map` lookup.
  "src/analyzer/analyzers/llm_analyzers/unified_ai.cr",
]

# Adapters that still open files through the stdlib rather than
# `read_file_content` / `Noir::TextFile.read`.
RAW_FILE_IO_ALLOWLIST = [
  # Reads a fixed-size byte buffer to sniff the mitmproxy flow format's
  # binary header. `Noir::TextFile.read` decodes as UTF-8 and is the wrong
  # tool for a binary probe.
  "src/analyzer/analyzers/specification/mitmproxy.cr",
  # Streams a user-supplied file line by line under a token budget, so it
  # deliberately avoids reading whole contents into memory.
  "src/analyzer/analyzers/llm_analyzers/unified_ai.cr",
]

# Hand-rolled `content_for(...) || read` copies that are not fixable by
# calling `read_file_content`.
CONTENT_FALLBACK_ALLOWLIST = [
  # Not an `Analyzer` subclass, so it has no `read_file_content` to call —
  # it is a plain helper class the Express adapter drives. Gains the
  # accessor if it ever grows an analyzer base.
  "src/analyzer/analyzers/javascript/express/router_mount_scanner.cr",
]

# Every (allowlist, pattern) pair, so the staleness guard below covers all of
# them rather than just the first. An allowlist whose entries are never
# re-checked is how a rule quietly stops applying to a file that no longer
# needs the exemption.
ALLOWLISTS = [
  {DIRECTORY_WALK_ALLOWLIST, DIRECTORY_WALK_RE},
  {RAW_FILE_IO_ALLOWLIST, RAW_FILE_IO_RE},
  {CONTENT_FALLBACK_ALLOWLIST, CONTENT_FALLBACK_RE},
]

describe "analyzer layering boundary" do
  # `Dir.glob` from an adapter walks the tree from a root of its own
  # choosing, which is exactly what layer L0 exists to own. It also costs an
  # `opendir` pass per call: Django's ROOT_URLCONF resolution used to run one
  # per `settings.py` and was ~73% of the whole analysis phase on a 44k-file
  # monorepo, which is why `CodeLocator#files_by_basename` exists.
  it "does not enumerate directories outside the language engines" do
    offenders = offending_lines(DIRECTORY_WALK_RE, DIRECTORY_WALK_ALLOWLIST)

    fail <<-MSG unless offenders.empty?
      framework adapters receive their file set from the language engine
      (`scan_target_files` / `parallel_file_scan`) or from the detector-built
      indexes (`get_files_by_extension`, `CodeLocator#files_by_basename`).
      Walking a directory here bypasses subtree pruning, --exclude-path, the
      media filter and the content cache. Move the walk into
      `src/analyzer/engines/{lang}_engine.cr`, or add the lookup you need to
      `CodeLocator`. Offending lines:
        #{offenders.join("\n  ")}
      MSG
  end

  # `Analyzer#read_file_content` is the one supported way for an adapter to
  # get a file's content: it prefers the detector's cache and falls back to
  # a disk read. `python/tornado.cr` shadowed it with a private override of
  # the same name that added a memo and an `IO::Error` rescue, and re-spelled
  # the base body (`content_for(path) || TextFile.read(path)`) inline — so a
  # change to the cache-miss path would have missed the copy. Nothing failed,
  # because the base never calls it internally. That is the whole problem: a
  # silent fork only grep could find. It is now `memoized_file_content` and
  # delegates.
  it "does not shadow read_file_content with a local copy" do
    offenders = offending_lines(/^\s*(?:private\s+|protected\s+)?def\s+read_file_content\b/, [] of String)

    fail <<-MSG unless offenders.empty?
      `read_file_content` is defined once, on `Analyzer`. A subclass copy is
      a silent fork of the read semantics — name the wrapper something else
      and delegate to it. Offending lines:
        #{offenders.join("\n  ")}
      MSG
  end

  # The cache-miss fallback belongs inside `read_file_content`, not spelled
  # out at each call site. Every hand-rolled copy is a place that keeps
  # reading from disk if the caching strategy ever changes.
  it "does not hand-roll the content-cache fallback" do
    offenders = offending_lines(CONTENT_FALLBACK_RE, CONTENT_FALLBACK_ALLOWLIST)

    fail <<-MSG unless offenders.empty?
      call `read_file_content(path)` instead of re-spelling
      `CodeLocator.instance.content_for(path) || Noir::TextFile.read(path)`.
      Offending lines:
        #{offenders.join("\n  ")}
      MSG
  end

  # The other half of "does not walk the filesystem": reading a path the
  # stdlib way skips `Noir::TextFile`'s decoding contract (`utf-8`,
  # `invalid: :skip`) and the size guard, and skips the detector's content
  # cache entirely. `Noir::TextFile.read` is deliberately NOT matched — it is
  # the sanctioned reader and the fallback inside `read_file_content` itself.
  it "does not read files through the stdlib directly" do
    offenders = offending_lines(RAW_FILE_IO_RE, RAW_FILE_IO_ALLOWLIST)

    fail <<-MSG unless offenders.empty?
      adapters read content through `read_file_content(path)` (cache-first)
      or `Noir::TextFile.read(path)` (decoding contract + size guard), not
      through `File.open` / `File.read`. Offending lines:
        #{offenders.join("\n  ")}
      MSG
  end

  # Guards the guard. A typo in the glob would make every example above pass
  # vacuously, which is the failure mode that makes source-scanning specs
  # worthless — and it is why the allowlists are asserted to be live rather
  # than merely present.
  it "scans a non-trivial number of adapter sources" do
    adapter_sources.size.should be > 200
    adapter_sources.count { |f| File.read(f).includes?("read_file_content") }.should be > 50
  end

  # A stale entry is worse than no entry: it silently re-permits the rule for
  # a file that no longer needs it, and nothing ever notices. Deleting the
  # entry is the last step of fixing a violation, so this fails when someone
  # fixes the code and forgets the list. Covers all three allowlists — an
  # exemption that is never re-checked is how a rule stops applying.
  it "keeps every allowlist entry pointing at a real, still-offending file" do
    ALLOWLISTS.each do |paths, pattern|
      paths.each do |path|
        File.exists?(path).should be_true
        File.read(path).matches?(pattern).should be_true
      end
    end
  end
end
