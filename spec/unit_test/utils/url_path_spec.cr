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
