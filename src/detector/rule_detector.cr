require "../models/detector"
require "../miniparsers/cargo_dependency"

module Noir::DetectorRules
  # Parsed once. Every detector instance shares the compiled predicates and regexes.
  alias Matcher = Proc(Detector, String, String, Bool)

  record Gate, extensions : Array(String), basenames : Array(String), path_segments : Array(String) do
    def self.parse(node : YAML::Any) : self
      DetectorRules.check_keys(node, %w[extensions basenames path_segments])
      new(terms(node, "extensions"), terms(node, "basenames"), terms(node, "path_segments"))
    end

    private def self.terms(node, key)
      node[key]?.try { |values| DetectorRules.strings(values) } || [] of String
    end

    def matches?(path : String) : Bool
      return true if extensions.any? { |ext| path.ends_with?(ext) }
      return true if path_segments.any? { |segment| path.includes?(segment) }
      return true if !basenames.empty? && basenames.includes?(File.basename(path))
      return false if extensions.empty?
      folded = Noir::FileExtension.fold(path)
      !folded.same?(path) && extensions.any? { |ext| folded.ends_with?(ext) }
    end
  end

  record Rule, key : String, registry_name : String, gate : Gate, files : Gate?, matcher : Matcher

  SOURCES = {{ run("../tagger/rules/embed.cr", __DIR__ + "/rules") }}

  # The language and entry label occupy the same position as a Crystal
  # detector's qualified name in the ordered registry.
  def self.each_definition(&)
    SOURCES.each do |file, yaml|
      language = File.basename(file, File.extname(file))
      YAML.parse(yaml).as_h.each do |label, node|
        yield "Detector::#{language}::#{label.as_s}", node
      end
    end
  end

  BUILTIN = begin
    rules = [] of Rule
    each_definition { |name, node| rules << parse(name, node) }
    rules
  end

  def self.check_keys(node : YAML::Any, allowed : Array(String)) : Nil
    raise ArgumentError.new("empty mapping") if node.as_h.empty?
    node.as_h.each_key do |key|
      raise ArgumentError.new("unknown key #{key}") unless allowed.includes?(key.as_s)
    end
  end

  def self.strings(node : YAML::Any) : Array(String)
    values = node.as_a?.try(&.map(&.as_s)) || [node.as_s]
    raise ArgumentError.new("expected nonempty strings") if values.empty? || values.any?(&.empty?)
    values
  end

  private def self.parse(registry_name : String, node : YAML::Any) : Rule
    check_keys(node, %w[key gate files match examples])
    key = node["key"].as_s
    files = node["files"]?.try { |f| Gate.parse(f) }
    gate = node["gate"]?.try { |g| Gate.parse(g) } || files || raise ArgumentError.new("missing file gate")
    Rule.new(key, registry_name, gate, files, condition(node["match"]))
  rescue ex
    raise ArgumentError.new("#{registry_name}: #{ex.message}")
  end

  private def self.condition(node : YAML::Any) : Matcher
    raise ArgumentError.new("expected one match operator") unless node.as_h.size == 1
    key, value = node.as_h.first
    case key.as_s
    when "all", "any"
      children = value.as_a.map { |child| condition(child) }
      raise ArgumentError.new("empty #{key}") if children.empty?
      if key.as_s == "all"
        ->(d : Detector, p : String, s : String) { children.all?(&.call(d, p, s)) }
      else
        ->(d : Detector, p : String, s : String) { children.any?(&.call(d, p, s)) }
      end
    when "files"
      gate = Gate.parse(value)
      ->(_d : Detector, p : String, _s : String) { gate.matches?(p) }
    when "contains"
      markers = Regex.union(strings(value))
      ->(d : Detector, _p : String, s : String) { d.content_matches?(s, markers) }
    when "regex"
      patterns = strings(value).map { |source| Regex.new(source) }
      pattern = patterns.size == 1 ? patterns.first : Regex.union(patterns)
      ->(d : Detector, _p : String, s : String) { d.content_matches?(s, pattern) }
    else
      dependency(key.as_s, value)
    end
  end

  private def self.dependency(key : String, value : YAML::Any) : Matcher
    case key
    when "go_dependency"
      marker = Regex.new(value.as_s)
      ->(d : Detector, p : String, s : String) { d.go_dependency?(p, s, marker) }
    when "go_mod_dependency"
      name = value.as_s
      ->(d : Detector, p : String, s : String) { d.go_mod_dependency?(p, s, name) }
    when "cargo_dependency"
      crate = value.as_s
      ->(_d : Detector, _p : String, s : String) { Noir::CargoDependency.declares?(s, crate) }
    when "ruby_dependency"
      gem = value.as_s
      ->(d : Detector, p : String, s : String) {
        if p.includes?("Gemfile")
          d.gemfile_dependency?(s, gem)
        else
          p.ends_with?(".gemspec") && d.gemspec_dependency?(s, gem)
        end
      }
    when "composer_dependency"
      packages = strings(value)
      ->(d : Detector, p : String, s : String) { packages.any? { |pkg| d.composer_dependency?(p, s, pkg) } }
    when "package_json_or_ts_import"
      check_keys(value, %w[package import])
      package = Regex.new(value["package"].as_s)
      import = Regex.new(value["import"].as_s)
      ->(d : Detector, p : String, s : String) { d.package_json_or_ts_import?(p, s, package, import) }
    else
      raise ArgumentError.new("unknown match operator #{key}")
    end
  end
end

class RuleDetector < Detector
  def initialize(options, @rule : Noir::DetectorRules::Rule)
    super(options)
  end

  def name : String
    @rule.key
  end

  def applicable?(filename : String) : Bool
    @rule.gate.matches?(filename)
  end

  def path_sensitive? : Bool
    @rule.gate.path_segments.any?(&.includes?('/'))
  end

  def detect(filename : String, file_contents : String) : Bool
    return false if (files = @rule.files) && !files.matches?(filename)
    @rule.matcher.call(self, filename, file_contents)
  end
end
