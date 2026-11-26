require "spec"
require "../../../src/utils/jvm_media_type"

describe Noir::JvmMediaType do
  describe ".body_format" do
    it "reads JSON from the constant and the string literal" do
      Noir::JvmMediaType.body_format("MediaType.APPLICATION_JSON").should eq("json")
      Noir::JvmMediaType.body_format(%("application/json")).should eq("json")
    end

    it "reads a URL-encoded form from the constant and the string literal" do
      Noir::JvmMediaType.body_format("MediaType.APPLICATION_FORM_URLENCODED").should eq("form")
      Noir::JvmMediaType.body_format(%("application/x-www-form-urlencoded")).should eq("form")
    end

    it "reads a multipart form from the constant and the string literal" do
      Noir::JvmMediaType.body_format("MediaType.MULTIPART_FORM_DATA").should eq("form")
      Noir::JvmMediaType.body_format(%("multipart/form-data")).should eq("form")
    end

    it "returns nil for a type that is neither" do
      Noir::JvmMediaType.body_format("MediaType.TEXT_PLAIN").should be_nil
      Noir::JvmMediaType.body_format(%("application/xml")).should be_nil
      Noir::JvmMediaType.body_format("").should be_nil
    end

    it "reads the type out of a longer argument" do
      Noir::JvmMediaType.body_format("consumes = MediaType.APPLICATION_JSON").should eq("json")
      Noir::JvmMediaType.body_format(%("application/json; charset=utf-8")).should eq("json")
    end

    # The form check runs first, so it wins whichever order the two are in.
    it "prefers a URL-encoded form when an argument also names JSON" do
      Noir::JvmMediaType.body_format("{MediaType.APPLICATION_JSON, MediaType.APPLICATION_FORM_URLENCODED}").should eq("form")
      Noir::JvmMediaType.body_format("{MediaType.APPLICATION_FORM_URLENCODED, MediaType.APPLICATION_JSON}").should eq("form")
    end

    # The multipart check runs after the JSON one.
    it "prefers JSON when an argument also names a multipart form" do
      Noir::JvmMediaType.body_format("{MediaType.MULTIPART_FORM_DATA, MediaType.APPLICATION_JSON}").should eq("json")
    end
  end
end
