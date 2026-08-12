require "../../spec_helper"
require "../../../src/utils/url_path"

describe "Noir::URLPath.join" do
  it "joins parent and child without slashes" do
    Noir::URLPath.join("/api", "users").should eq("/api/users")
  end

  it "joins parent with trailing slash and child without leading slash" do
    Noir::URLPath.join("/api/", "users").should eq("/api/users")
  end

  it "joins parent without trailing slash and child with leading slash" do
    Noir::URLPath.join("/api", "/users").should eq("/api/users")
  end

  it "joins parent with trailing slash and child with leading slash" do
    Noir::URLPath.join("/api/", "/users").should eq("/api/users")
  end

  it "returns child if parent is empty" do
    Noir::URLPath.join("", "/users").should eq("/users")
  end

  it "returns parent if child is empty" do
    Noir::URLPath.join("/api", "").should eq("/api")
  end

  it "handles empty strings for both" do
    Noir::URLPath.join("", "").should eq("")
  end

  it "preserves double slashes inside paths" do
    Noir::URLPath.join("/api//v1", "users").should eq("/api//v1/users")
  end
end

# `join_trimmed` replaced seven byte-identical `join_paths` copies (http4k,
# JAX-RS, Micronaut, the shared JVM lambda-DSL extractor, AdonisJS, Elysia,
# and the Scala Play analyzer). It sits next to `join` and is easy to reach
# for by mistake, so these pin the cases where the two disagree.
describe "Noir::URLPath.join_trimmed" do
  it "collapses every slash at the seam, not just one" do
    Noir::URLPath.join_trimmed("/api//", "/users").should eq "/api/users"
    Noir::URLPath.join_trimmed("/api", "//users").should eq "/api/users"
    Noir::URLPath.join_trimmed("/api///", "///users").should eq "/api/users"
  end

  it "drops a trailing slash when the suffix is empty" do
    Noir::URLPath.join_trimmed("/api/", "").should eq "/api"
    Noir::URLPath.join_trimmed("/api", "").should eq "/api"
  end

  it "returns the suffix untouched when the prefix is empty" do
    Noir::URLPath.join_trimmed("", "/users").should eq "/users"
    Noir::URLPath.join_trimmed("", "users").should eq "users"
  end

  it "agrees with join on already-normalised segments" do
    [{"/api", "users"}, {"/api/", "/users"}, {"/api", "/users"}].each do |prefix, suffix|
      Noir::URLPath.join_trimmed(prefix, suffix).should eq Noir::URLPath.join(prefix, suffix)
    end
  end

  # The reason it is a separate method rather than a call to `join`.
  it "differs from join where the seam has repeated or trailing slashes" do
    Noir::URLPath.join("/api//", "/users").should eq "/api//users"
    Noir::URLPath.join_trimmed("/api//", "/users").should eq "/api/users"

    Noir::URLPath.join("/api/", "").should eq "/api/"
    Noir::URLPath.join_trimmed("/api/", "").should eq "/api"
  end
end

# The Spring mapping-composition rule, shared by the Java and Kotlin
# tree-sitter route extractors.
describe "Noir::URLPath.join_absorbing" do
  it "absorbs a bare method mapping onto the class prefix" do
    Noir::URLPath.join_absorbing("/api/article", "").should eq "/api/article"
    Noir::URLPath.join_absorbing("/api/article/", "").should eq "/api/article"
  end

  it "keeps the root when an all-slash prefix has no path" do
    Noir::URLPath.join_absorbing("/", "").should eq "/"
    Noir::URLPath.join_absorbing("///", "").should eq "/"
  end

  it "carries an explicit @GetMapping(\"/\") through the seam" do
    Noir::URLPath.join_absorbing("/api", "/").should eq "/api/"
  end

  # Deliberate: an unmapped class with a bare mapping resolves to `""`, and
  # the extractors rely on that staying empty so the analyzer above them can
  # apply the context path. Adding a root guard here would silently move
  # every JVM route — `join_rooted` exists for callers that need one.
  it "returns the path untouched when the prefix is empty" do
    Noir::URLPath.join_absorbing("", "/users").should eq "/users"
    Noir::URLPath.join_absorbing("", "").should eq ""
  end

  it "differs from join_trimmed on an all-slash prefix" do
    Noir::URLPath.join_trimmed("/", "").should eq ""
    Noir::URLPath.join_absorbing("/", "").should eq "/"
  end
end

# `join_rooted` replaced a top-level `def join_paths(*paths) = File.join(paths)`
# that unqualified calls in `java/spring.cr` and `kotlin/spring.cr` fell
# through to. These pin the three inputs where `File.join` was wrong and the
# two where the other `URLPath` joins would regress.
describe "Noir::URLPath.join_rooted" do
  it "absorbs an empty path instead of leaving a trailing slash" do
    Noir::URLPath.join_rooted("/portal", "").should eq "/portal"
    Noir::URLPath.join_rooted("/portal/", "").should eq "/portal"
  end

  it "roots a path that carries no leading slash" do
    Noir::URLPath.join_rooted("", "users").should eq "/users"
    Noir::URLPath.join_rooted("", "/users").should eq "/users"
  end

  it "returns the root when both sides are empty" do
    Noir::URLPath.join_rooted("", "").should eq "/"
    Noir::URLPath.join_rooted("/", "").should eq "/"
  end

  it "collapses repeated slashes at the seam" do
    Noir::URLPath.join_rooted("/api//", "/users").should eq "/api/users"
    Noir::URLPath.join_rooted("/api", "//users").should eq "/api/users"
  end

  # What the File.join-based composition used to produce. Each of these is a
  # URL Spring's servlet container would not serve at that address.
  it "differs from File.join where File.join was wrong" do
    File.join("/portal", "").should eq "/portal/"
    Noir::URLPath.join_rooted("/portal", "").should eq "/portal"

    File.join("", "users").should eq "users"
    Noir::URLPath.join_rooted("", "users").should eq "/users"

    File.join("/api//", "/users").should eq "/api//users"
    Noir::URLPath.join_rooted("/api//", "/users").should eq "/api/users"
  end

  # And why neither of the existing joins could be reused: both emit an
  # empty URL for the unmapped-class-with-bare-mapping case.
  it "differs from join_trimmed and join_absorbing on the empty pair" do
    Noir::URLPath.join_trimmed("", "").should eq ""
    Noir::URLPath.join_absorbing("", "").should eq ""
    Noir::URLPath.join_rooted("", "").should eq "/"
  end
end

# Relocated verbatim from `spec/unit_test/utils/utils_spec.cr`, where they
# covered the top-level `join_path`. Only the receiver changed — the
# assertions standing unaltered is the evidence the move preserved
# behaviour.
describe "Noir::URLPath.absolute_join" do
  it "joins two segments" do
    Noir::URLPath.absolute_join("/api", "users").should eq("/api/users")
  end

  it "collapses a double slash at the boundary" do
    Noir::URLPath.absolute_join("/api", "/users").should eq("/api/users")
  end

  it "strips trailing slashes from segments" do
    Noir::URLPath.absolute_join("api/", "/v1/").should eq("/api/v1")
  end

  it "skips empty segments" do
    Noir::URLPath.absolute_join("", "users").should eq("/users")
  end

  it "joins three segments (variadic)" do
    Noir::URLPath.absolute_join("a", "b", "c").should eq("/a/b/c")
  end

  it "always prepends a leading slash" do
    Noir::URLPath.absolute_join("noslash").should eq("/noslash")
  end
end
