require "../../models/tagger"
require "../../models/endpoint"

class FileUploadTagger < Tagger
  # Param names that denote an actual uploaded file regardless of how the
  # value is carried — a `filename`, an `attachment`, a `multipart`
  # boundary. Safe to flag on any writable param type.
  WORDS = Set{
    "file", "files", "upload", "attachment", "attachments", "document", "documents",
    "multipart", "content_type", "filename", "content_disposition",
  }

  # Media words that frequently name a *reference* — a profile-image URL,
  # an avatar link — inside a JSON/body payload rather than an uploaded
  # file. Treated as an upload only when carried as multipart form data
  # (a `file`/`form` param) or corroborated by an upload-ish URL, so a
  # JSON `{"image": "https://..."}` field (e.g. RealWorld's
  # `PUT /user`) is not mis-tagged as a file upload.
  MEDIA_WORDS = Set{
    "image", "images", "photo", "photos", "avatar", "media",
  }

  # Form-style carriage: a genuine browser file upload arrives as a
  # `file` param or a multipart `form` field. JSON/body media fields are
  # almost always a URL/reference string.
  MEDIA_UPLOAD_PARAM_TYPES = Set{"file", "form"}

  UPLOAD_PARAM_TYPES = Set{"file", "form", "body", "json"}
  UPLOAD_METHODS     = Set{"POST", "PUT", "PATCH"}
  UPLOAD_PATH_PARTS  = Set{
    "upload", "uploads", "attach", "attachment", "attachments",
    "import", "imports", "avatar", "photo", "photos",
    "file", "files", "image", "images", "picture", "pictures",
  }

  # `media` is matched only as a whole `/media` path segment, never as a
  # loose sub-token. As a loose token (split on `-`/`_`) it fired on
  # config/feature routes that merely contain the word but upload nothing:
  # `/settings/media-path` (a media-directory setting, e.g. koel),
  # `/social-media`, `/media-library`. A standalone `/media` collection
  # (`POST /media`) still tags.
  SEGMENT_ONLY_PATH_PARTS = Set{"media"}

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "file_upload"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      has_upload_param = endpoint.params.any? { |param| upload_param?(param) }
      is_upload_url = upload_url?(endpoint.url)
      is_upload_method = UPLOAD_METHODS.includes?(endpoint.method.upcase)
      has_multipart_header = endpoint.params.any? { |param| multipart_header?(param) }

      check = is_upload_method && (has_upload_param || is_upload_url || has_multipart_header)

      if check
        tag = Tag.new("file_upload", "File upload endpoint potentially vulnerable to unrestricted file upload, path traversal, or malicious file execution.", "FileUpload")
        endpoint.add_tag(tag)
      end
    end
  end

  private def upload_param?(param : Param) : Bool
    return false unless UPLOAD_PARAM_TYPES.includes?(param.param_type)

    # A param whose type *is* `file` is a file input regardless of its
    # name — analyzers emit the raw variable name there (`$_FILES['cv']`,
    # `$request->files->get('resume')`), which won't appear in WORDS.
    return true if param.param_type == "file"

    name = normalize_param_name(param.name)
    return true if WORDS.includes?(name) || name.ends_with?("_file") || name.ends_with?("_files")

    # Media words count as an upload only via multipart carriage. In a
    # JSON/body payload they are almost always a URL/reference string, so
    # `upload_url?`/`multipart_header?` must corroborate them instead.
    MEDIA_WORDS.includes?(name) && MEDIA_UPLOAD_PARAM_TYPES.includes?(param.param_type)
  end

  private def multipart_header?(param : Param) : Bool
    name = normalize_param_name(param.name)
    value = param.value.downcase
    (name == "content_type" && value.includes?("multipart/form-data")) ||
      (name == "content_disposition" && value.includes?("filename="))
  end

  private def upload_url?(url : String) : Bool
    parts = url.downcase.split(/[\/\-_\.]+/).reject(&.empty?)
    return true if parts.any? { |part| UPLOAD_PATH_PARTS.includes?(part) }
    segment_only_upload?(url)
  end

  # Whole-segment-only path words: matched against `/`-delimited segments
  # (after dropping the query/fragment) so they don't fire as a sub-token
  # of a compound like `media-path`.
  private def segment_only_upload?(url : String) : Bool
    path = url.split("?", 2)[0].split("#", 2)[0]
    path.downcase.split("/").any? { |seg| SEGMENT_ONLY_PATH_PARTS.includes?(seg) }
  end
end
