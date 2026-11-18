require "../../models/tagger"
require "../../models/endpoint"

@[Noir::TaggerFor(key: "file_upload", name: "FileUpload Tagger", desc: "Identifies file upload endpoints", order: 90)]
class FileUploadTagger < Tagger
  # Param names that denote an uploaded file however the value is carried.
  WORDS = Set{"file", "upload", "multipart"}

  # Names that denote an uploaded file except as a JSON field. In a JSON
  # body `files`/`attachment` are references to stored files (a URL list, a
  # message attachment object), since JSON cannot carry a multipart file.
  # ponytail: Rails reports permitted params as json whenever the controller
  # renders json, though they may arrive as multipart form data, so a Rails
  # endpoint keeps these (and a bare json `file`) on json too. Drop that once
  # the Rails analyzer types has_one_attached/has_many_attached-backed
  # permits as `file`.
  FORM_FILE_WORDS = Set{"files", "attachment", "attachments", "document", "documents"}

  # Metadata about a file part. On its own it is an upload only as a form
  # field beside the part, and not on a download route, where it names the
  # file to send back.
  FILE_METADATA_WORDS = Set{"filename", "content_type", "content_disposition"}

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
    "image", "images", "picture", "pictures",
  }

  # `file`/`files` is a generic REST noun, so on its own it only marks the
  # collection itself (`POST /files`), not an item or action under it
  # (`PATCH /files/:id`, `POST /files/purge`) that renames or prunes.
  COLLECTION_PATH_PARTS = Set{"file", "files"}

  # A read-side word in the path says the route sends a file out. A URL word
  # alone must not tag it, though a real file param still does.
  DOWNLOAD_PATH_PARTS = Set{"download", "downloads", "export", "exports", "zip"}

  # `media` is matched only as a whole `/media` path segment, never as a
  # loose sub-token. As a loose token (split on `-`/`_`) it fired on
  # config/feature routes that merely contain the word but upload nothing:
  # `/settings/media-path` (a media-directory setting, e.g. koel),
  # `/social-media`, `/media-library`. A standalone `/media` collection
  # (`POST /media`) still tags.
  SEGMENT_ONLY_PATH_PARTS = Set{"media"}

  private def check_endpoint(endpoint : Endpoint)
    rails = endpoint.details.technology == "ruby_rails" || endpoint.details.technologies.includes?("ruby_rails")
    has_upload_param = endpoint.params.any? { |param| upload_param?(param, endpoint.url, rails) }
    is_upload_url = upload_url?(endpoint.url, endpoint.method)
    is_upload_method = UPLOAD_METHODS.includes?(endpoint.method.upcase)
    has_multipart_header = endpoint.params.any? { |param| multipart_header?(param) }

    check = is_upload_method && (has_upload_param || is_upload_url || has_multipart_header)

    if check
      tag = Tag.new("file_upload", "File upload endpoint potentially vulnerable to unrestricted file upload, path traversal, or malicious file execution.", "FileUpload")
      endpoint.add_tag(tag)
    end
  end

  private def upload_param?(param : Param, url : String, rails : Bool) : Bool
    return false unless UPLOAD_PARAM_TYPES.includes?(param.param_type)

    # A param whose type *is* `file` is a file input regardless of its
    # name — analyzers emit the raw variable name there (`$_FILES['cv']`,
    # `$request->files->get('resume')`), which won't appear in WORDS.
    return true if param.param_type == "file"

    name = normalize_param_name(param.name)
    return true if WORDS.includes?(name)
    if FORM_FILE_WORDS.includes?(name) || name.ends_with?("_file") || name.ends_with?("_files")
      return rails || param.param_type != "json"
    end
    return false unless MEDIA_UPLOAD_PARAM_TYPES.includes?(param.param_type)
    return !download_url?(url) if FILE_METADATA_WORDS.includes?(name)

    # Media words count as an upload only as multipart form data. In a
    # JSON/body payload they are almost always a URL/reference string, so
    # `upload_url?`/`multipart_header?` must corroborate them instead.
    MEDIA_WORDS.includes?(name)
  end

  private def multipart_header?(param : Param) : Bool
    name = normalize_param_name(param.name)
    value = param.value.downcase
    (name == "content_type" && value.includes?("multipart/form-data")) ||
      (name == "content_disposition" && value.includes?("filename="))
  end

  # An explicit upload word always counts. The weaker `file`/`files` and
  # `media` nouns are vetoed by a read-side word (`/files/export`).
  private def upload_url?(url : String, method : String) : Bool
    return true if url_parts(url).any? { |part| UPLOAD_PATH_PARTS.includes?(part) }
    return false if download_url?(url)
    collection_upload?(url, method) || segment_only_upload?(url)
  end

  private def download_url?(url : String) : Bool
    url_parts(url).any? { |part| DOWNLOAD_PATH_PARTS.includes?(part) }
  end

  # `file`/`files` counts as the last segment (`/user-files`, `/files.json`
  # included), or, for PUT, the segment before a path parameter
  # (`PUT /files/:name`, a raw-body upload by name).
  private def collection_upload?(url : String, method : String) : Bool
    segments = url.split("?", 2)[0].split("#", 2)[0].downcase.split("/").reject(&.empty?)
    last = segments.last?
    return false if last.nil?
    collection = ->(seg : String) { seg.split(/[-_.]/).any? { |t| COLLECTION_PATH_PARTS.includes?(t) } }
    return true if collection.call(last)
    method.upcase == "PUT" && segments.size >= 2 && path_param?(last) && collection.call(segments[-2])
  end

  private def path_param?(segment : String) : Bool
    segment.starts_with?(":") || segment.starts_with?("{") || segment.starts_with?("<")
  end

  # Whole-segment-only path words: matched against `/`-delimited segments
  # (after dropping the query/fragment) so they don't fire as a sub-token
  # of a compound like `media-path`.
  private def segment_only_upload?(url : String) : Bool
    path = url.split("?", 2)[0].split("#", 2)[0]
    path.downcase.split("/").any? { |seg| SEGMENT_ONLY_PATH_PARTS.includes?(seg) }
  end
end
