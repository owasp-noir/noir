require "../../models/tagger"
require "../../models/endpoint"

class FileUploadTagger < Tagger
  WORDS = ["file", "upload", "attachment", "document", "image", "multipart", "content-type", "filename", "content-disposition"]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "file_upload"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      tmp_params = [] of String

      endpoint.params.each do |param|
        tmp_params.push param.name.to_s.downcase
      end

      # Check URL path for upload indicators
      url_lower = endpoint.url.downcase
      is_upload_url = url_lower.includes?("upload") || url_lower.includes?("attach") || url_lower.includes?("import")

      words_set = Set.new(WORDS)
      tmp_params_set = Set.new(tmp_params)
      intersection = words_set & tmp_params_set

      # Check that at least one parameter matches and method is POST/PUT or URL indicates upload
      is_upload_method = endpoint.method == "POST" || endpoint.method == "PUT"
      check = (intersection.size.to_i >= 1 && is_upload_method) || (is_upload_url && is_upload_method)

      if check
        tag = Tag.new("file_upload", "File upload endpoint potentially vulnerable to unrestricted file upload, path traversal, or malicious file execution.", "FileUpload")
        endpoint.add_tag(tag)
      end
    end
  end
end
