require "file_utils"
require "../../spec_helper"
require "../../../src/tagger/tagger"

# Regression guard for tagger line-bounds safety.
#
# Framework taggers read a source file fresh and walk `lines[idx]` around
# `code_path.line`. If that line number falls outside the content actually
# read (stale metadata, a file truncated/changed between detection and
# tagging, an off-by-one), an unguarded walk raises IndexError — and since
# framework taggers run inside WaitGroup fibers, a single bad endpoint used
# to abort the whole tagging pass. These cases lock in the guards.
describe "Tagger line-bounds safety" do
  # A real on-disk file the taggers can read; small on purpose so most of
  # the probed line numbers land beyond EOF.
  tmpdir = File.tempname("tagger_bounds")
  Dir.mkdir_p(tmpdir)
  sample_path = File.join(tmpdir, "sample.txt")
  File.write(sample_path, "line1\nline2\nline3\n")
  empty_path = File.join(tmpdir, "empty.txt")
  File.write(empty_path, "")
  one_path = File.join(tmpdir, "one.txt")
  File.write(one_path, "only")

  Spec.after_suite { FileUtils.rm_rf(tmpdir) }

  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)

  # nil, zero, in-range, boundary, and far-past-EOF line numbers.
  line_values = [nil, 0, 1, 2, 3, 4, 100, 100_000]
  file_paths = [sample_path, empty_path, one_path]

  build_endpoint = ->(path : String, line : Int32?, tech : String?) {
    details = Details.new(PathInfo.new(path, line))
    details.technology = tech
    Endpoint.new("/test/login/auth", "POST", [
      Param.new("token", "eyJabc.def.ghi", "json"),
      Param.new("id", "1", "path"),
      Param.new("redirect", "http://example.com", "query"),
    ] of Param, details)
  }

  NoirTaggers::HasFrameworkTaggers.each do |key, info|
    runner = info[:runner]
    tech = runner.target_techs.first? || "unknown"
    it "#{key} does not crash on edge/out-of-range line numbers" do
      file_paths.each do |fp|
        line_values.each do |lv|
          endpoint = build_endpoint.call(fp, lv, tech)
          tagger = runner.new(options)
          # Must not raise regardless of how stale the line ref is.
          tagger.perform([endpoint])
        end
      end
    end
  end

  NoirTaggers::HasTaggers.each do |key, info|
    runner = info[:runner]
    it "#{key} does not crash on edge/out-of-range line numbers" do
      file_paths.each do |fp|
        line_values.each do |lv|
          endpoint = build_endpoint.call(fp, lv, nil)
          tagger = runner.new(options)
          tagger.perform([endpoint])
        end
      end
    end
  end
end
