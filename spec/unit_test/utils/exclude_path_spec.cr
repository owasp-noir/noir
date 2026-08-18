require "../../spec_helper"
require "../../../src/utils/exclude_path"

# `--exclude-path` used to be spelled out inline in the detector's walk, so
# the only way to state what a pattern means was to run a scan. It is now
# `Noir::ExcludePath`, which both the detector and the analyzers that walk
# the filesystem themselves (`Analyzer#excluded_path?`) go through — these
# examples are the contract they share.
describe Noir::ExcludePath do
  it "is inactive when no pattern was given" do
    Noir::ExcludePath.new("").active?.should be_false
    Noir::ExcludePath.new(" , ").active?.should be_false
    Noir::ExcludePath.new("").excluded?("anything/at/all.go").should be_false
  end

  it "matches a pattern without a slash against the basename" do
    matcher = Noir::ExcludePath.new("*.test.js")
    matcher.excluded?("src/app.test.js").should be_true
    matcher.excluded?("app.test.js").should be_true
    matcher.excluded?("src/app.js").should be_false
  end

  it "matches a pattern with a slash against the scan-base-relative path" do
    matcher = Noir::ExcludePath.new("tests/*")
    matcher.excluded?("tests/integration.js").should be_true
    matcher.excluded?("src/tests/integration.js").should be_false
  end

  it "treats a plain directory pattern as everything under it" do
    matcher = Noir::ExcludePath.new("src/legacy")
    matcher.excluded?("src/legacy").should be_true
    matcher.excluded?("src/legacy/old.go").should be_true
    matcher.excluded?("src/legacy/deep/old.go").should be_true
    # Boundary: a sibling whose name merely starts the same way stays in.
    matcher.excluded?("src/legacy2/old.go").should be_false
  end

  it "accepts a rooted relative path, which is what analyzers hold" do
    # `Analyzer#base_relative_path` returns `/`-rooted paths; the detector
    # computes an unrooted one. Both must mean the same thing.
    matcher = Noir::ExcludePath.new("src/legacy,secret.yml")
    matcher.excluded?("/src/legacy/old.go").should be_true
    matcher.excluded?("/config/secret.yml").should be_true
  end

  it "splits on commas and ignores blank entries" do
    matcher = Noir::ExcludePath.new(" *.min.js , , vendor/** ")
    matcher.excluded?("assets/app.min.js").should be_true
    matcher.excluded?("vendor/lib/x.go").should be_true
    matcher.excluded?("assets/app.js").should be_false
  end

  it "classifies a backslash-separated pattern as a path pattern" do
    matcher = Noir::ExcludePath.new("src\\legacy")
    matcher.excluded?("src/legacy/old.go").should be_true
  end

  it "raises on a malformed glob rather than excluding nothing" do
    # The detector turns this into `Noir::InvalidExcludePathError`: an
    # unusable pattern must stop the scan, not silently match nothing.
    expect_raises(File::BadPatternError) do
      Noir::ExcludePath.new("[bad").excluded?("x.go")
    end
  end

  {% if flag?(:darwin) || flag?(:windows) %}
    it "folds case on case-insensitive filesystems" do
      Noir::ExcludePath.new("MyFile.go").excluded?("src/myfile.go").should be_true
      Noir::ExcludePath.new("Src/Legacy").excluded?("src/legacy/old.go").should be_true
    end
  {% else %}
    it "keeps case significant where the filesystem does" do
      Noir::ExcludePath.new("MyFile.go").excluded?("src/myfile.go").should be_false
    end
  {% end %}
end
