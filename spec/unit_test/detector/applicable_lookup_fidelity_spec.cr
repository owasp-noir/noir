require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/models/detector"

# Instantiate every concrete Detector subclass. Using `all_subclasses`
# rather than a hand-written list is deliberate: a new detector joins
# this sweep automatically, so it cannot silently regress the memo.
private def every_detector(options) : Array(Detector)
  detectors = [] of Detector
  {% for sub in Detector.all_subclasses %}
    {% unless sub.abstract? %}
      detector = {{ sub }}.new(options)
      detector.set_name
      detectors << detector.as(Detector)
    {% end %}
  {% end %}
  detectors
end

# `detector_build_applicable_lookup` memoizes `applicable?` by basename
# for every detector that `detector_path_sensitive?` does not flag. That
# classifier is probe-based, and a probe whose *basename* independently
# satisfies `applicable?` masks a directory gate behind it — which is how
# the Hasura `metadata/**` gate was lost (46/46 → 16 failures) without any
# unit test noticing.
#
# This sweep is the oracle: for every real fixture path, a detector that
# genuinely applies must survive the memo. Missing candidates mean the
# detector never runs, which means silently dropped endpoints.
private def memo_misses(paths : Array(String)) : Array(String)
  options = create_test_options
  detectors = every_detector(options)
  lookup = detector_build_applicable_lookup(detectors)

  missed = [] of String
  paths.each do |path|
    candidates = lookup.call(path).to_set
    detectors.each_with_index do |detector, idx|
      next unless detector.applicable?(path)
      next if candidates.includes?(idx)
      missed << "#{detector.name} skipped #{path}"
    end
  end
  missed.uniq
end

# Layouts that isolate a directory gate from the basename: the path
# matches the gate while the basename on its own does NOT. The fixture
# corpus does not cover these — its Kamal fixture is `config/deploy.yml`,
# whose basename contains "deploy" and so matches independently, leaving
# the `/config/deploy` + `/.kamal/` clauses unguarded. Without these,
# dropping a `path_sensitive?` declaration passes the corpus sweep.
#
# Add an entry here whenever a detector gains a directory gate.
DIRECTORY_GATE_PROBES = [
  # hasura: metadata/** with a per-table basename (CLI v3 layout)
  "proj/metadata/databases/default/tables/public_movies.yaml",
  "proj/metadata/actions.yaml",
  # kamal: destination-named deploy files and the .kamal/ directory
  "proj/config/deploy/production.yml",
  "proj/.kamal/production.yml",
  # supabase
  "proj/supabase/migrations/001_init.sql",
  "proj/migrations/001_init.sql",
  # directus
  "proj/directus/snapshots/snap.json",
  # strapi
  "proj/src/api/article/content-types/article/schema.json",
  # grails: extension-free path under grails-app
  "proj/grails-app/conf/application",
]

describe "detector applicable? memo fidelity" do
  it "never drops a detector that applies to a real fixture path" do
    paths = Dir.glob("spec/functional_test/fixtures/**/*").select { |path| File.file?(path) }
    paths.size.should be > 0

    # Show a bounded sample so a broad regression stays readable.
    memo_misses(paths).first(25).should eq([] of String)
  end

  it "never drops a detector whose directory gate is isolated from the basename" do
    memo_misses(DIRECTORY_GATE_PROBES).should eq([] of String)
  end
end
