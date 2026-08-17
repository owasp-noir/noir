require "../../spec_helper"
require "../../../src/utils/jvm_literal"

describe Noir::JvmLiteral do
  describe ".value_of" do
    it "unwraps string literals" do
      Noir::JvmLiteral.value_of(%q("json")).should eq "json"
      Noir::JvmLiteral.value_of(%q("new,hot")).should eq "new,hot"
      Noir::JvmLiteral.value_of("'c'").should eq "c"
    end

    it "keeps numeric literals, dropping the type suffix and separators" do
      Noir::JvmLiteral.value_of("1").should eq "1"
      Noir::JvmLiteral.value_of("25").should eq "25"
      Noir::JvmLiteral.value_of("10L").should eq "10"
      Noir::JvmLiteral.value_of("1.5f").should eq "1.5"
      Noir::JvmLiteral.value_of("1_000").should eq "1000"
    end

    it "keeps booleans" do
      Noir::JvmLiteral.value_of("true").should eq "true"
      Noir::JvmLiteral.value_of("false").should eq "false"
    end

    it "treats every spelling of absence as no value" do
      Noir::JvmLiteral.value_of("null").should eq ""
      Noir::JvmLiteral.value_of("None").should eq ""
      Noir::JvmLiteral.value_of("Nil").should eq ""
      Noir::JvmLiteral.value_of("Optional.empty()").should eq ""
      Noir::JvmLiteral.value_of("").should eq ""
      Noir::JvmLiteral.value_of("   ").should eq ""
    end

    # The regression this exists for: `Param#value` is what the curl /
    # httpie / PowerShell builders put on the wire and what the OAS builders
    # publish as an `enum`, so a default with no literal form must not leak
    # its source text there.
    it "gives a non-literal expression no value" do
      Noir::JvmLiteral.value_of("LocalDateTime.now()").should eq ""
      Noir::JvmLiteral.value_of("title.toSlug()").should eq ""
      Noir::JvmLiteral.value_of("List.empty").should eq ""
      Noir::JvmLiteral.value_of(%q(Some("x"))).should eq ""
      Noir::JvmLiteral.value_of("new ArrayList<>()").should eq ""
      Noir::JvmLiteral.value_of("SOME_CONSTANT").should eq ""
    end
  end
end
