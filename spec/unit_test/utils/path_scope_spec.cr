require "../../spec_helper"
require "../../../src/utils/path_scope"

describe Noir::PathScope do
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
