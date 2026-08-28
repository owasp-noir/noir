require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/prefix_scope"

describe PrefixScope do
  describe ".prefix_covers?" do
    it "covers the prefix itself" do
      PrefixScope.prefix_covers?("/web", "/web").should be_true
    end

    it "covers a child path" do
      PrefixScope.prefix_covers?("/web", "/web/x").should be_true
    end

    it "does not cover a longer sibling segment" do
      PrefixScope.prefix_covers?("/admin", "/administration/report").should be_false
      PrefixScope.prefix_covers?("/web", "/website").should be_false
    end

    it "treats the root prefix as covering everything" do
      PrefixScope.prefix_covers?("/", "/anything/at/all").should be_true
      PrefixScope.prefix_covers?("/", "").should be_true
    end

    it "does not cover an unrelated url" do
      PrefixScope.prefix_covers?("/api", "/admin/users").should be_false
    end

    it "handles prefixes with a trailing slash" do
      PrefixScope.prefix_covers?("/web/", "/web/").should be_true
      PrefixScope.prefix_covers?("/web/", "/web/x").should be_false
    end

    it "handles an empty url" do
      PrefixScope.prefix_covers?("/web", "").should be_false
    end

    it "is case sensitive" do
      PrefixScope.prefix_covers?("/web", "/WEB/x").should be_false
      PrefixScope.prefix_covers?("/WEB", "/web").should be_false
    end
  end
end
