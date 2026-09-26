require "../../spec_helper"
require "../../../src/utils/path_scope"

# Yields the current directory and a fresh scratch directory, and restores
# the working directory afterwards: the pin specs `Dir.cd` so that a lost pin
# resolves against the wrong directory instead of silently agreeing.
private def with_scratch_dir(&)
  original = Dir.current
  target = File.join(Dir.tempdir, "noir-path-scope-spec-#{Random.new.hex(6)}")
  Dir.mkdir_p(target)
  begin
    yield original, File.realpath(target)
  ensure
    Dir.cd(original)
    Dir.delete(target)
  end
end

describe Noir::PathScope do
  describe ".normalize_base" do
    # `-b` is echoed verbatim into every reported `code_path`, so three
    # spellings of the same tree used to produce three different reports.
    it "pins the normalization table" do
      {
        "rem2"     => "rem2",
        "rem2/"    => "rem2",
        "rem2///"  => "rem2",
        "./rem2"   => "rem2",
        "././rem2" => "rem2",
        "rem2/./a" => "rem2/a",
        "a//b//c/" => "a/b/c",
        "."        => ".",
        "./"       => ".",
        ""         => "",
        ".."       => "..",
        "../app/"  => "../app",
        "/"        => "/",
        "///"      => "/",
        "/a//b/"   => "/a/b",
        "/app"     => "/app",
      }.each do |input, expected|
        Noir::PathScope.normalize_base(input).should eq(expected)
      end
    end

    it "keeps a relative base relative (never expands it)" do
      normalized = Noir::PathScope.normalize_base("./app///")
      normalized.should eq("app")
      normalized.starts_with?("/").should be_false
    end

    it "is idempotent" do
      ["rem2///", "./rem2", "/a//b/", "./", "..", "/"].each do |input|
        once = Noir::PathScope.normalize_base(input)
        Noir::PathScope.normalize_base(once).should eq(once)
      end
    end

    it "leaves a backslash alone on POSIX" do
      # Only Windows treats `\\` as a separator; elsewhere it is an
      # ordinary filename character.
      {% if flag?(:windows) %}
        Noir::PathScope.normalize_base("a\\\\b\\\\").should eq("a\\b")
      {% else %}
        Noir::PathScope.normalize_base("a\\b\\").should eq("a\\b\\")
      {% end %}
    end
  end

  describe ".normalize_root" do
    it "strips a trailing slash from a normalized root" do
      Noir::PathScope.normalize_root("/app/").should eq("/app")
    end

    it "leaves a root without a trailing slash unchanged" do
      Noir::PathScope.normalize_root("/app").should eq("/app")
    end
  end

  describe ".under_root?" do
    it "matches a path under its root" do
      Noir::PathScope.under_root?("/app/x", "/app").should be_true
    end

    it "matches a path equal to its root" do
      Noir::PathScope.under_root?("/app", "/app").should be_true
    end

    it "respects path boundaries (does not match a sibling prefix)" do
      Noir::PathScope.under_root?("/app2/x", "/app").should be_false
    end

    it "treats an empty root as matching everything" do
      Noir::PathScope.under_root?("/anything", "").should be_true
    end

    it "normalizes a root with a trailing slash before comparing" do
      Noir::PathScope.under_root?("/app/x", "/app/").should be_true
    end
  end

  describe ".under_normalized_root?" do
    it "matches an expanded path beneath an already-normalized root" do
      Noir::PathScope.under_normalized_root?("/app/x", "/app").should be_true
    end

    it "does not match a sibling prefix" do
      Noir::PathScope.under_normalized_root?("/app2/x", "/app").should be_false
    end

    it "matches the root itself" do
      Noir::PathScope.under_normalized_root?("/app", "/app").should be_true
    end

    it "does not match a path shorter than the root" do
      Noir::PathScope.under_normalized_root?("/ap", "/app").should be_false
    end

    it "agrees with the concatenating boundary check it replaced" do
      roots = ["/app", "/app/sub", "", "/a"]
      paths = ["/app", "/app/", "/app/x", "/app2", "/ap", "/app/sub/y", "/a", "/ab", "", "/"]
      roots.each do |root|
        paths.each do |path|
          expected = path == root || path.starts_with?(root + File::SEPARATOR)
          Noir::PathScope.under_normalized_root?(path, root).should eq(expected)
        end
      end
    end
  end

  describe ".expand" do
    it "agrees with File.expand_path for absolute and relative paths" do
      ["/app/./x/../y", "/", "/app/", "rel/./a/../b", ".", "..", "", "a//b/"].each do |path|
        Noir::PathScope.expand(path).should eq(File.expand_path(path))
      end
    end

    it "keeps resolving against the pinned directory after a Dir.cd inside the scope" do
      with_scratch_dir do |original, target|
        Noir::PathScope.with_pinned_cwd do
          Dir.cd(target)
          Noir::PathScope.expand("x").should eq(File.expand_path("x", original))
          Noir::PathScope.expand("rel/../b").should eq(File.expand_path("rel/../b", original))
          Noir::PathScope.expand("/app/./x").should eq("/app/x")
        end
      end
    end

    it "does not keep the pinned directory after the scope ends" do
      with_scratch_dir do |_original, target|
        Noir::PathScope.with_pinned_cwd { Noir::PathScope.expand("x") }
        Dir.cd(target)
        Noir::PathScope.expand("x").should eq(File.expand_path("x"))
      end
    end

    it "keeps the outer pin through a nested scope" do
      with_scratch_dir do |original, target|
        Noir::PathScope.with_pinned_cwd do
          Noir::PathScope.with_pinned_cwd { }
          Dir.cd(target)
          Noir::PathScope.expand("x").should eq(File.expand_path("x", original))
        end
      end
    end
  end

  describe ".longest_base" do
    it "picks the most specific containing base" do
      Noir::PathScope.longest_base("/app/api/x", ["/app", "/app/api"]).should eq("/app/api")
    end

    it "returns the original (non-normalized) base string" do
      Noir::PathScope.longest_base("/app/api/x", ["/app/api/"]).should eq("/app/api/")
    end

    it "returns nil when no base contains the path" do
      Noir::PathScope.longest_base("/other/x", ["/app", "/app/api"]).should be_nil
    end
  end

  describe ".relative_under" do
    it "returns the path remainder beneath the base" do
      Noir::PathScope.relative_under("/app/api/x.cr", "/app").should eq("api/x.cr")
    end

    it "returns the basename when the path is outside the base" do
      Noir::PathScope.relative_under("/other/x.cr", "/app").should eq("x.cr")
    end

    it "returns the basename when no base is given" do
      Noir::PathScope.relative_under("/other/x.cr", nil).should eq("x.cr")
    end

    it "returns the basename when the path equals the base" do
      Noir::PathScope.relative_under("/app", "/app").should eq("app")
    end
  end
end
