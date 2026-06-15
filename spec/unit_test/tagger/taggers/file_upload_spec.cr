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

    it "tags a param whose type is \"file\" regardless of its name" do
      tagger = FileUploadTagger.new(default_tagger_options)

      # PHP `$_FILES['cv']` / Symfony `$request->files->get('resume')`
      # surface the raw variable name, which is not in WORDS.
      endpoint = Endpoint.new("/upload.php", "POST", [
        Param.new("cv", "", "file"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end

    it "tags POST endpoint with an images path" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/images", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end

    it "tags PATCH endpoint with avatar body parameter" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/users/me/avatar", "PATCH", [
        Param.new("avatar", "", "body"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end

    it "tags multipart content-type header values" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/profile", "POST", [
        Param.new("Content-Type", "multipart/form-data; boundary=abc", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end

    it "does not tag non-multipart content-type headers" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/profile", "POST", [
        Param.new("Content-Type", "application/json", "header"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag GET media endpoints as uploads" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/users/123/avatar", "GET", [
        Param.new("avatar", "", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a JSON image-reference field as a file upload" do
      tagger = FileUploadTagger.new(default_tagger_options)

      # RealWorld `PUT /api/user` carries `image` as a profile-image URL
      # string in the JSON body, not an uploaded file. A media word in a
      # JSON/body payload on a non-upload URL must not trip the tagger.
      endpoint = Endpoint.new("/api/user", "PUT", [
        Param.new("username", "", "json"),
        Param.new("image", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "still tags a multipart form image field as a file upload" do
      tagger = FileUploadTagger.new(default_tagger_options)

      # When the media word is carried as a multipart `form` field it is a
      # real upload even without an upload-ish URL.
      endpoint = Endpoint.new("/api/profile", "POST", [
        Param.new("image", "", "form"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end

    it "does not tag a media-* config route as an upload" do
      tagger = FileUploadTagger.new(default_tagger_options)

      # koel `PUT /api/settings/media-path` sets the media-library
      # directory — `media` here is a sub-token of `media-path`, not a
      # `/media` upload collection.
      endpoint = Endpoint.new("/api/settings/media-path", "PUT")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "still tags a standalone /media collection upload" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/media", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("file_upload")
    end
  end
end
