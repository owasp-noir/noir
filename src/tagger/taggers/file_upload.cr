require "../../models/tagger"
require "../../models/endpoint"

class FileUploadTagger < Tagger
  WORDS = Set{
    "file", "files", "upload", "attachment", "attachments", "document", "documents",
    "image", "images", "photo", "photos", "avatar", "media", "multipart",
    "content_type", "filename", "content_disposition",
  }

  UPLOAD_PARAM_TYPES = Set{"file", "form", "body", "json"}
  UPLOAD_METHODS     = Set{"POST", "PUT", "PATCH"}
  UPLOAD_PATH_PARTS  = Set{"upload", "uploads", "attach", "attachment", "attachments", "import", "imports", "avatar", "photo", "photos", "media"}

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
    name = normalize_param_name(param.name)
    return false unless UPLOAD_PARAM_TYPES.includes?(param.param_type)

    WORDS.includes?(name) || name.ends_with?("_file") || name.ends_with?("_files")
  end

  private def multipart_header?(param : Param) : Bool
    name = normalize_param_name(param.name)
    value = param.value.downcase
    (name == "content_type" && value.includes?("multipart/form-data")) ||
      (name == "content_disposition" && value.includes?("filename="))
  end

  private def upload_url?(url : String) : Bool
    parts = url.downcase.split(/[\/\-_\.]+/).reject(&.empty?)
    parts.any? { |part| UPLOAD_PATH_PARTS.includes?(part) }
  end

  private def normalize_param_name(name : String) : String
    name.downcase.tr("-", "_")
  end
end
