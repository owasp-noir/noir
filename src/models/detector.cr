require "./logger"
require "../utils/utils"
require "yaml"

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

  # Tolerant matcher for a Gemfile `gem "<name>"` line. Accepts both the
  # bare and parenthesized call forms with arbitrary spacing — `gem 'x'`,
  # `gem "x"`, `gem('x')`, `gem( "x" )` — and a trailing version
  # constraint, while still requiring the closing quote right after the
  # name so `gem 'sinatra'` never matches `gem 'sinatra-contrib'`.
  def gemfile_dependency?(file_contents : String, gem_name : String) : Bool
    file_contents.matches?(/\bgem\s*\(?\s*['"]#{Regex.escape(gem_name)}['"]/)
  end

  # Tolerant matcher for a gemspec runtime dependency on `<name>`, in
  # either the space or parenthesized call form — gems routinely write
  # `s.add_dependency('sinatra', "~> 4.0")` (geminabox) or
  # `spec.add_runtime_dependency "railties"`, neither of which the old
  # `"add_dependency 'sinatra'"` substring markers matched.
  def gemspec_dependency?(file_contents : String, gem_name : String) : Bool
    file_contents.matches?(/\badd(?:_runtime)?_dependency\s*\(?\s*['"]#{Regex.escape(gem_name)}['"]/)
  end

  getter name, logger
end
