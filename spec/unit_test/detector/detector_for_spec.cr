require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/models/detector"

# `detector_for` replaced the hand-written `set_name` / `applicable?` /
# `idempotent?` trio that every one of the 241 detectors carried. These specs
# pin the macro's expansion, and the sweep at the bottom pins the invariant
# that made the macro worth introducing: the tech name is declared exactly
# once per detector, so `Class.tech_name` and the instance's `name` can never
# disagree.

private class ExtOnlyDetector < Detector
  detector_for "spec_ext_only", extensions: %w[.foo .bar]
end

private class BasenameDetector < Detector
  detector_for "spec_basename", basenames: %w[config.toml Makefile]
end

private class MixedDetector < Detector
  detector_for "spec_mixed", extensions: %w[.zz], basenames: %w[zz.mod], idempotent: false
end

private class DirSegmentDetector < Detector
  detector_for "spec_dir_segment", path_segments: %w[/metadata/]
end

private class BareSubstringDetector < Detector
  detector_for "spec_bare_substring", path_segments: %w[zz.mod]
end

private class NameOnlyDetector < Detector
  detector_for "spec_name_only"
end

describe "detector_for" do
  options = create_test_options

  it "declares the tech name for both the instance and the class" do
    detector = ExtOnlyDetector.new(options)
    detector.set_name
    detector.name.should eq "spec_ext_only"
    ExtOnlyDetector.tech_name.should eq "spec_ext_only"
  end

  it "gates on every declared extension and nothing else" do
    detector = ExtOnlyDetector.new(options)
    detector.applicable?("a/b/thing.foo").should be_true
    detector.applicable?("thing.bar").should be_true
    detector.applicable?("thing.baz").should be_false
    detector.applicable?("foo").should be_false
  end

  it "compares basenames rather than substrings" do
    detector = BasenameDetector.new(options)
    detector.applicable?("deep/dir/config.toml").should be_true
    detector.applicable?("Makefile").should be_true
    # A substring gate would wrongly accept these.
    detector.applicable?("config.toml.bak").should be_false
    detector.applicable?("dir/config.tomlx").should be_false
  end

  it "ORs extensions and basenames together" do
    detector = MixedDetector.new(options)
    detector.applicable?("x/y.zz").should be_true
    detector.applicable?("x/zz.mod").should be_true
    detector.applicable?("x/y.qq").should be_false
  end

  it "carries idempotent: false through, and defaults to true" do
    MixedDetector.new(options).idempotent?.should be_false
    ExtOnlyDetector.new(options).idempotent?.should be_true
  end

  # The reason `path_segments` exists as its own key. `applicable?` is
  # memoized by basename, so a directory gate that does not declare itself
  # path-sensitive is silently dropped — the way the Hasura `metadata/**`
  # gate was lost.
  it "derives path_sensitive? from a segment that names a directory" do
    detector = DirSegmentDetector.new(options)
    detector.path_sensitive?.should be_true
    detector.applicable?("app/metadata/tables.yaml").should be_true
    detector.applicable?("tables.yaml").should be_false
  end

  # A separator-free term is a plain substring test over the whole path, and
  # `detector_path_sensitive?`'s probe does not flag those: it compares
  # `applicable?("a/b/c/zz.mod")` with `applicable?("zz.mod")`, which agree.
  # Declaring them sensitive would drop the detector out of the basename memo
  # for no correctness gain.
  it "leaves a separator-free substring term basename-memoizable" do
    detector = BareSubstringDetector.new(options)
    detector.path_sensitive?.should be_false
    detector.applicable?("a/b/c/zz.mod").should eq detector.applicable?("zz.mod")
  end

  it "emits no gate when only a name is declared" do
    detector = NameOnlyDetector.new(options)
    NameOnlyDetector.tech_name.should eq "spec_name_only"
    # Falls through to Detector's permissive default.
    detector.applicable?("anything.at.all").should be_true
  end
end

describe "detector identity" do
  it "declares each real detector's name exactly once" do
    options = create_test_options
    mismatched = [] of String

    # `Detector::` is the production namespace — see the same filter in
    # applicable_lookup_fidelity_spec.cr for why the sweep is scoped.
    {% for sub in Detector.all_subclasses %}
      {% if !sub.abstract? && sub.name.starts_with?("Detector::") %}
        detector = {{ sub }}.new(options)
        detector.set_name
        unless detector.name == {{ sub }}.tech_name
          mismatched << "{{ sub }}: name=#{detector.name} tech_name=#{{{ sub }}.tech_name}"
        end
      {% end %}
    {% end %}

    fail "detectors whose instance name and class tech_name disagree: #{mismatched}" unless mismatched.empty?
  end
end
