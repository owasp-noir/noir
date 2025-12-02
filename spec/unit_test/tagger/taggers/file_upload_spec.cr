require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/file_upload.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "FileUploadTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = FileUploadTagger.new(default_tagger_options)
      tagger.should_not be_nil
    end
  end

  describe "perform" do
    it "tags POST endpoint with file parameter" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/upload", "POST", [
        Param.new("file", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end

    it "tags PUT endpoint with upload URL" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/upload/document", "PUT")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end

    it "tags endpoint with attachment parameter" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/submit", "POST", [
        Param.new("attachment", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end

    it "does not tag GET endpoint with file parameter" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/download", "GET", [
        Param.new("file", "document.pdf", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag endpoint without upload indicators" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/users", "POST", [
        Param.new("name", "John", "form"),
        Param.new("email", "john@example.com", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags endpoint with multipart parameter" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/submit", "POST", [
        Param.new("multipart", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end

    it "tags endpoint with import URL" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/import", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end

    it "handles multiple endpoints" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint1 = Endpoint.new("/api/upload", "POST", [
        Param.new("file", "", "form"),
      ])

      endpoint2 = Endpoint.new("/api/users", "GET", [
        Param.new("name", "John", "query"),
      ])

      tagger.perform([endpoint1, endpoint2])

      endpoint1.tags.size.should eq(1)
      endpoint2.tags.size.should eq(0)
    end

    it "is case-insensitive for parameter matching" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/submit", "POST", [
        Param.new("File", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
    end

    it "tags endpoint with content-disposition header" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/submit", "POST", [
        Param.new("content-disposition", "attachment; filename=document.pdf", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end
  end
end
