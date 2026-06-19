require "../../../models/detector"

module Detector::Javascript
  class Http < Detector
    CORE_HTTP_IMPORT = Regex.union(
      /require\s*\(\s*['"](?:node:)?https?['"]\s*\)/,
      /from\s+['"](?:node:)?https?['"]/,
      /import\s+[A-Za-z_$]\w*\s*=\s*require\s*\(\s*['"](?:node:)?https?['"]\s*\)/,
    )

    CREATE_SERVER_SIGNAL = /\bcreateServer\b|\.\s*createServer\s*\(/
    METHOD_REF           = /\b[A-Za-z_$]\w*\s*\.\s*method\b/
    URL_REF              = /\b[A-Za-z_$]\w*\s*\.\s*url\b|new\s+URL\s*\(/
    PATH_LITERAL         = /['"`]\/[^'"`]*['"`]/

    def detect(filename : String, file_contents : String) : Bool
      return false unless source_file?(filename)
      return false unless file_contents.matches?(CORE_HTTP_IMPORT)
      return false unless file_contents.matches?(CREATE_SERVER_SIGNAL)

      # Adapter use such as `createServer(yoga)` imports node:http but has no
      # direct request branching. Keep js_http scoped to the bare stdlib router
      # shape requested in #2144.
      file_contents.matches?(METHOD_REF) &&
        file_contents.matches?(URL_REF) &&
        file_contents.matches?(PATH_LITERAL)
    end

    def applicable?(filename : String) : Bool
      source_file?(filename) || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_http"
    end

    private def source_file?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") ||
        filename.ends_with?(".cjs") || filename.ends_with?(".jsx") ||
        filename.ends_with?(".ts") || filename.ends_with?(".mts") ||
        filename.ends_with?(".tsx")
    end
  end
end
