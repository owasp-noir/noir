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
describe "detector applicable? memo fidelity" do
  it "never drops a detector that applies to a real fixture path" do
    options = create_test_options
    detectors = every_detector(options)
    lookup = detector_build_applicable_lookup(detectors)

    paths = Dir.glob("spec/functional_test/fixtures/**/*").select { |path| File.file?(path) }
    paths.size.should be > 0

    missed = [] of String
    paths.each do |path|
      candidates = lookup.call(path).to_set
      detectors.each_with_index do |detector, idx|
        next unless detector.applicable?(path)
        next if candidates.includes?(idx)
        missed << "#{detector.name} skipped #{path}"
      end
    end

    # Show a bounded sample so a broad regression stays readable.
    missed.uniq.first(25).should eq([] of String)
  end
end
