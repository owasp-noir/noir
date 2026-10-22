require "../../../models/detector"
require "../../../utils/serverless_layout"

module Detector::Javascript
  # A Cloudflare Pages Functions module: a file under a project's root
  # `functions/` directory exporting an `onRequest*` handler.
  class CloudflarePages < Detector
    detector_for "js_cloudflare_pages", path_sensitive: true

    EXTENSIONS = {".js", ".mjs", ".ts", ".tsx", ".jsx"}

    # `export [async] function onRequestGet(`, `export const onRequest =`,
    # `export { onRequestPost }`.
    HANDLER_EXPORT = /(?:^|[^\w$.])export\s+(?:(?:async\s+)?function\s*\*?\s*|(?:const|let|var)\s+)onRequest(?:Get|Post|Put|Patch|Delete|Head|Options)?\b|(?:^|[^\w$.])export\s*\{[^}]*\bonRequest(?:Get|Post|Put|Patch|Delete|Head|Options)?\b[^}]*\}/m

    def applicable?(filename : String) : Bool
      return false unless EXTENSIONS.any? { |ext| filename.ends_with?(ext) }
      filename.includes?("functions/") || filename.includes?("functions\\")
    end

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false if Noir::ServerlessLayout.non_handler_file?(filename)
      return false unless file_contents.includes?("onRequest")
      # Firebase's `onRequest` trigger lives under a `functions/` dir too.
      return false if file_contents.includes?("firebase-functions")
      return false unless content_matches?(file_contents, HANDLER_EXPORT)

      relative = base_relative_path(filename).gsub('\\', '/')
      !Noir::ServerlessLayout.routing_remainder(filename, relative, "functions").nil?
    end
  end
end
