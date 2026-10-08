require "../../../models/detector"
require "../../../utils/serverless_layout"

module Detector::Javascript
  # A Vercel Function: a Node.js module under a project's root `api/`
  # directory exporting a handler, in a Vercel project (`vercel.json` /
  # `now.json`, an `@vercel/node` / `@vercel/functions` dependency) or
  # importing those packages itself. The root anchoring and the Vercel
  # signal keep Next.js `pages/api/` and Nuxt `server/api/` out.
  class VercelFunctions < Detector
    detector_for "js_vercel_functions", path_sensitive: true

    EXTENSIONS = {".js", ".mjs", ".ts", ".tsx"}

    VERCEL_IMPORT  = /(?:\bfrom\s*|\brequire\s*\(\s*|\bimport\s*\(\s*)['"]@vercel\/(?:node|functions)['"]/
    HANDLER_EXPORT = /(?:^|[^\w$.])export\s+default\b|(?:^|[^\w$.])module\s*\.\s*exports\s*=(?!=)|(?:^|[^\w$.])export\s+(?:(?:async\s+)?function\s+|(?:const|let|var)\s+)(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b/m

    def applicable?(filename : String) : Bool
      return false unless EXTENSIONS.any? { |ext| filename.ends_with?(ext) }
      filename.includes?("api/") || filename.includes?("api\\")
    end

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false if Noir::ServerlessLayout.non_handler_file?(filename)

      relative = base_relative_path(filename).gsub('\\', '/')
      root, segments = Noir::ServerlessLayout.routing_remainder(filename, relative, "api") || return false
      return false if Noir::ServerlessLayout.private_segment?(segments)
      return false unless content_matches?(file_contents, HANDLER_EXPORT)

      content_matches?(file_contents, VERCEL_IMPORT) || Noir::ServerlessLayout.vercel_project?(root)
    end
  end
end
