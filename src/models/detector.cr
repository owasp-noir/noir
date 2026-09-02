require "./logger"
require "./code_locator"
require "./skipped_files"
require "../utils/text_file"
require "../utils/utils"
require "json"
require "yaml"

module Noir
  # Raised when a user-supplied `--exclude-path` glob is malformed.
  # `File.match?` only raises once the walk reaches the bad construct, so
  # this surfaces from inside the detector's file walk rather than at CLI
  # parse time; `noir scan` catches it and exits with a clean error.
  class InvalidExcludePathError < Exception
  end
end

class Detector
  @logger : NoirLogger
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @name : String
  @base_path : String
  @base_paths : Array(String)

  def initialize(options : Hash(String, YAML::Any))
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @name = ""
    @base_paths = options["base"].as_a.map(&.to_s)
    @base_path = @base_paths.first? || ""

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log
  end

  def detect(filename : String, file_contents : String) : Bool
    # After inheriting the class, write an action code here.
    false
  end

  # `filename` relative to the scan base that owns it, `/`-separated and
  # rooted with a leading `/`.
  #
  # A detector that keys off a DIRECTORY (`wp-content/`, `vendor/yiisoft/`,
  # `routes/`) rather than a filename must match on this: on the absolute
  # path, a checkout that merely sat under a same-named directory made
  # every file in the project look like the framework's. Filename markers
  # (`composer.json`, `Cargo.toml`) are unaffected either way — an
  # ancestor directory contributes no filename.
  #
  # Reads the roots from `CodeLocator`, which `NoirRunner#detect` publishes
  # before the walk; with none registered (detector unit specs) the path is
  # returned unchanged.
  def base_relative_path(filename : String) : String
    CodeLocator.instance.base_relative(filename)
  end

  # Declares the detector's tech name and the cheap filename gate that lets
  # the detect loop skip `detect` on files this detector cannot match.
  #
  #     class Gin < Detector
  #       detector_for "go_gin", extensions: %w[.go], basenames: %w[go.mod]
  #     end
  #
  # Expands to the same short-circuiting chain the detectors used to write by
  # hand — one `ends_with?` / `==` per declared term, *not* a runtime loop
  # over an array — so the hot path is unchanged. Terms are emitted
  # extension, then path segment, then basename: extensions reject the most
  # files for the least work, and only a surviving candidate pays for
  # `File.basename`.
  #
  # A `path_segments` term that names a directory (`"/metadata/"`) implies
  # `path_sensitive?`, and that link is the whole point. `applicable?` is
  # memoized by basename, so a detector that consults directory segments
  # without declaring itself path-sensitive has its gate silently deleted —
  # that is how the Hasura `metadata/**` gate was lost. Declaring the
  # segment *is* declaring the sensitivity, so the two can no longer drift
  # apart.
  #
  # A separator-free term (`"go.mod"`) is a plain substring test on the whole
  # path and deliberately does *not* imply sensitivity, because
  # `Noir::Detection.path_sensitive?` does not flag those today: the probe compares
  # `applicable?("a/b/c/go.mod")` with `applicable?("go.mod")`, which agree.
  # Declaring them sensitive would drop those detectors out of the basename
  # memo and slow the hot loop for no correctness gain here.
  #
  # Pass `idempotent: false` for a detector whose `detect` has side effects
  # (registering spec paths in `CodeLocator`), so the pass keeps calling it
  # after its first match.
  #
  # A gate that is more than a term list — one that normalises separators,
  # checks a parent directory, or excludes `.d.ts` — keeps its hand-written
  # `applicable?`. Pass just the tech name and define the method below; with
  # no terms the macro emits no gate to collide with.
  macro detector_for(tech, extensions = nil, basenames = nil, path_segments = nil, idempotent = nil)
    def set_name
      @name = {{ tech }}
    end

    # The tech name without needing an instance, so the registry can be
    # read off the classes themselves rather than from a parallel list.
    def self.tech_name : String
      {{ tech }}
    end

    {% if extensions || basenames || path_segments %}
      def applicable?(filename : String) : Bool
        {% for ext in (extensions || [] of String) %}
          return true if filename.ends_with?({{ ext }})
        {% end %}
        {% for segment in (path_segments || [] of String) %}
          return true if filename.includes?({{ segment }})
        {% end %}
        {% if basenames %}
          base = File.basename(filename)
          {% for name in basenames %}
            return true if base == {{ name }}
          {% end %}
        {% end %}
        false
      end
    {% end %}

    {% if path_segments && path_segments.any?(&.includes?("/")) %}
      def path_sensitive? : Bool
        true
      end
    {% end %}

    {% if idempotent == false %}
      def idempotent? : Bool
        false
      end
    {% end %}
  end

  # Cheap filename-only filter the detector pass uses to skip
  # `detect` on files the detector cannot possibly match. The
  # default `true` preserves prior behavior (every detector runs on
  # every file). Override with the same predicate the body of
  # `detect` starts with — e.g., `filename.ends_with?(".py")` for a
  # Python framework detector — so the detector loop avoids the
  # `detect` dispatch on files outside the detector's language.
  #
  # On large codebases (saleor's 4255 `.py` files) this lifts ~100
  # virtual `detect` calls per file out of the hot loop because
  # most detectors' inner first-line is exactly this kind of cheap
  # filename check.
  def applicable?(filename : String) : Bool
    true
  end

  # Whether `applicable?` inspects more than the basename — directory
  # segments (`/metadata/`, `/.kamal/`) or root placement.
  #
  # The detect loop memoizes `applicable?` by basename, so a detector
  # that consults the path but does not declare it here has its path
  # gate silently deleted: `applicable?` is only ever asked about the
  # bare filename. That is a false-negative, not a crash, so nothing
  # fails loudly. `Noir::Detection.path_sensitive?` also probes for this, but
  # the probe is fail-open — a probe whose basename independently
  # matches masks the directory gate behind it (this is exactly how the
  # Hasura `metadata/**` gate was lost). Declare it explicitly.
  #
  # Guarded by `spec/unit_test/detector/applicable_lookup_fidelity_spec.cr`.
  def path_sensitive? : Bool
    false
  end

  # Whether the detector can be skipped on subsequent files once it
  # has matched. Defaults to `true` (idempotent — the detector only
  # signals tech presence). Detectors that perform side effects in
  # `detect` (e.g., the C# ASP.NET ones populate the `CodeLocator`
  # with route-config paths, the OAS/RAML detectors register spec
  # paths) must override to `false` so the detector pass keeps
  # invoking them on every file.
  def idempotent? : Bool
    true
  end

  # Detector content always arrives from `Noir::TextFile.read`, so the
  # subject is known-valid UTF-8 and PCRE2's per-call revalidation is
  # skippable. See `Noir::TextFile::MATCH_OPTIONS`.
  CONTENT_MATCH_OPTIONS = Noir::TextFile::MATCH_OPTIONS

  # Whether any alternative of a precompiled `Regex.union` appears in
  # `file_contents`. With a union of plain literals this is exactly
  # OR-ing `String#includes?` over the same literals — `Regex.union`
  # escapes every String argument — but it costs one pass instead of N.
  #
  # `String#includes?` runs Rabin-Karp: a rolling hash over every byte
  # position, restarted for each marker. PCRE2 JIT-compiles the union
  # into a program that skips ahead on a start-byte bitmap. Measured on
  # a 467 KB locale file against four non-matching markers: 2.16 ms of
  # chained `includes?` versus 26 µs here (82x). Even a single marker
  # over 300 small Ruby files is 13x, so the win is not a big-file
  # artifact.
  #
  # Use this for the marker sweep at the top of `detect`. A union is not
  # a substitute for a real pattern: keep purpose-built regexes as they
  # are, and keep a single `includes?` that merely gates an expensive
  # parse (there the substring check is the cheap half, not the cost).
  def content_matches?(file_contents : String, markers : Regex) : Bool
    markers.matches?(file_contents, options: CONTENT_MATCH_OPTIONS)
  end

  # Per-gem regex memos for `gemfile_dependency?`/`gemspec_dependency?`.
  # The interpolated literals used to recompile on every call — the Ruby
  # CLI detector alone probes 8 gems against every Gemfile/gemspec, and
  # each framework detector adds its own. Gem-name cardinality is a tiny
  # static set, so cache the compiled patterns process-wide.
  @@gemfile_dependency_res = {} of String => Regex
  @@gemspec_dependency_res = {} of String => Regex
  @@dependency_res_mutex = Mutex.new

  # Tolerant matcher for a Gemfile `gem "<name>"` line. Accepts both the
  # bare and parenthesized call forms with arbitrary spacing — `gem 'x'`,
  # `gem "x"`, `gem('x')`, `gem( "x" )` — and a trailing version
  # constraint, while still requiring the closing quote right after the
  # name so `gem 'sinatra'` never matches `gem 'sinatra-contrib'`.
  def gemfile_dependency?(file_contents : String, gem_name : String) : Bool
    re = @@dependency_res_mutex.synchronize do
      @@gemfile_dependency_res[gem_name] ||= /\bgem\s*\(?\s*['"]#{Regex.escape(gem_name)}['"]/
    end
    content_matches?(file_contents, re)
  end

  # Tolerant matcher for a gemspec runtime dependency on `<name>`, in
  # either the space or parenthesized call form — gems routinely write
  # `s.add_dependency('sinatra', "~> 4.0")` (geminabox) or
  # `spec.add_runtime_dependency "railties"`, neither of which the old
  # `"add_dependency 'sinatra'"` substring markers matched.
  def gemspec_dependency?(file_contents : String, gem_name : String) : Bool
    re = @@dependency_res_mutex.synchronize do
      @@gemspec_dependency_res[gem_name] ||= /\badd(?:_runtime)?_dependency\s*\(?\s*['"]#{Regex.escape(gem_name)}['"]/
    end
    content_matches?(file_contents, re)
  end

  # A document that matched this format's content marker but could not be
  # parsed at all.
  #
  # The spec detectors wrap "parse, then check the root key" in one
  # `rescue`, and the two halves fail for very different reasons.
  # `data["openapi"].as_s` raising `KeyError` / `TypeCastError` means "this
  # JSON is simply not my format" — the gate doing its job, and reporting it
  # would flag every document that merely mentions the word. A
  # `JSON::ParseException` / `YAML::ParseException` is the other case: the
  # file is not readable as JSON/YAML by anything, so it is never registered,
  # no analyzer ever opens it, and every endpoint it declares is lost.
  #
  # That half used to leave a `--debug` line and nothing else. An OpenAPI
  # document nested deeper than Crystal's 512-level `JSON.parse` ceiling —
  # or one truncated by a failed download — reported zero endpoints,
  # `"errors": []`, and exit 0 under `--strict`, which is indistinguishable
  # from a repository that declares no API at all.
  def record_unparsable_document(filename : String, error : Exception) : Nil
    return unless error.is_a?(JSON::ParseException) || error.is_a?(YAML::ParseException)

    Noir::SkippedFiles.record(@name, filename,
      error.message.presence || error.class.name,
      noun: "unparsable document", phase: Noir::SkippedFiles::Phase::Scan)
  end

  getter name, logger
end
