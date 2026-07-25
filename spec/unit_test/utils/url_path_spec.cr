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
