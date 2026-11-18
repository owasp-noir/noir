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

    it "does not tag item or action routes under a /files collection from the URL word alone" do
      tagger = FileUploadTagger.new(default_tagger_options)

      rename = Endpoint.new("/files/:id", "PATCH", [Param.new("name", "", "json")])
      cleanup = Endpoint.new("/files/purge", "POST")

      tagger.perform([rename, cleanup])

      rename.tags.size.should eq(0)
      cleanup.tags.size.should eq(0)
    end

    it "still tags the /files collection and item routes with file evidence" do
      tagger = FileUploadTagger.new(default_tagger_options)

      create = Endpoint.new("/api/files", "POST")
      replace = Endpoint.new("/files/:id", "PUT", [Param.new("data", "", "file")])

      tagger.perform([create, replace])

      create.tags.size.should eq(1)
      replace.tags.size.should eq(1)
    end

    it "does not tag a download or export route from the URL word alone" do
      tagger = FileUploadTagger.new(default_tagger_options)

      download = Endpoint.new("/api/doc/download/:seq", "POST", [Param.new("reason", "", "json")])
      export = Endpoint.new("/api/export/file", "POST")

      tagger.perform([download, export])

      download.tags.size.should eq(0)
      export.tags.size.should eq(0)
    end

    it "still tags a download-named route that carries a real file param" do
      tagger = FileUploadTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/upload/download-template", "POST", [Param.new("doc", "", "file")])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
    end

    it "keeps explicit upload words and raw-body item uploads tagged" do
      tagger = FileUploadTagger.new(default_tagger_options)

      zip = Endpoint.new("/upload/zip", "POST")
      archive = Endpoint.new("/import/export-archive", "POST")
      put_item = Endpoint.new("/files/:name", "PUT")
      compound = Endpoint.new("/user-files", "POST")
      suffixed = Endpoint.new("/api/files.json", "POST")

      tagger.perform([zip, archive, put_item, compound, suffixed])

      [zip, archive, put_item, compound, suffixed].each(&.tags.size.should(eq(1)))
    end

    it "does not tag JSON reference fields named like files as uploads" do
      tagger = FileUploadTagger.new(default_tagger_options)

      # A JSON payload cannot carry a multipart file: `files` here is a
      # list of stored-file references, `attachment` a message attachment
      # object.
      files = Endpoint.new("/api/orders/:id/report", "POST", [Param.new("files", "", "json")])
      attachment = Endpoint.new("/api/orders/:id/messages", "POST", [Param.new("attachment", "", "json")])
      documents = Endpoint.new("/api/orders/:id/reviews", "PUT", [Param.new("document_files", "", "json")])

      tagger.perform([files, attachment, documents])

      [files, attachment, documents].each(&.tags.size.should(eq(0)))
    end

    it "does not tag file-metadata names as uploads" do
      tagger = FileUploadTagger.new(default_tagger_options)

      json_name = Endpoint.new("/api/items", "POST", [Param.new("fileName", "", "json")])
      download = Endpoint.new("/api/items/zip/password/download", "POST", [
        Param.new("seq", "", "form"),
        Param.new("fileName", "", "form"),
      ])
      content_type = Endpoint.new("/api/items", "PUT", [Param.new("contentType", "", "json")])

      tagger.perform([json_name, download, content_type])

      [json_name, download, content_type].each(&.tags.size.should(eq(0)))
    end

    it "still tags multipart file fields and a bare file param" do
      tagger = FileUploadTagger.new(default_tagger_options)

      form_files = Endpoint.new("/api/items", "POST", [Param.new("files", "", "form")])
      form_attachment = Endpoint.new("/api/items", "POST", [Param.new("attachment", "", "form")])
      video_part = Endpoint.new("/api/items/:id/videos/parts", "POST", [
        Param.new("fileName", "", "form"),
        Param.new("video", "", "form"),
      ])
      # Rails reports permitted params as json whenever the controller
      # renders json, though they may arrive as multipart form data.
      json_file = Endpoint.new("/items/:id", "PATCH", [Param.new("file", "", "json")])

      tagger.perform([form_files, form_attachment, video_part, json_file])

      [form_files, form_attachment, video_part, json_file].each(&.tags.size.should(eq(1)))
    end

    it "still tags file words on a body param" do
      tagger = FileUploadTagger.new(default_tagger_options)

      # NestJS `@UploadedFiles()`, tsoa `@UploadedFile('document')` and
      # Scotty `files()` report the multipart part as `body`.
      endpoints = [
        Endpoint.new("/items/:id/gallery", "POST", [Param.new("files", "", "body")]),
        Endpoint.new("/items/:id/manual", "POST", [Param.new("document", "", "body")]),
        Endpoint.new("/items/:id/cover", "POST", [Param.new("cover_file", "", "body")]),
      ]

      tagger.perform(endpoints)

      endpoints.each(&.tags.size.should(eq(1)))
    end

    it "keeps Rails json file words tagged" do
      tagger = FileUploadTagger.new(default_tagger_options)

      # Rails reports permitted params as json whenever the controller
      # renders json, so `permit(attachments: [], files: [])` stays an upload
      # there, while the same json field elsewhere is a reference.
      rails = %w[attachments files document cover_file].map do |name|
        details = Details.new(PathInfo.new("app/controllers/items_controller.rb", 1))
        details.technology = "ruby_rails"
        Endpoint.new("/items", "POST", [Param.new(name, "", "json")], details)
      end
      other = Endpoint.new("/items", "POST", [Param.new("attachments", "", "json")])

      tagger.perform(rails + [other])

      rails.each(&.tags.size.should(eq(1)))
      other.tags.size.should eq(0)
    end
  end
end
