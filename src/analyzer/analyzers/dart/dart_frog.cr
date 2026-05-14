require "../../../models/analyzer"
require "../../../miniparsers/dart_callee_extractor"

module Analyzer::Dart
  # Dart Frog is a filesystem-routed framework. Routes live under
  # `routes/` and the URL is derived from the directory layout:
  #
  #   routes/index.dart                 → /
  #   routes/about.dart                 → /about
  #   routes/users/index.dart           → /users
  #   routes/users/[id].dart            → /users/{id}
  #   routes/users/[id]/posts.dart      → /users/{id}/posts
  #
  # Each route file exports an `onRequest(RequestContext, ...)` handler.
  # Method dispatch happens inside that handler — typically a switch on
  # `context.request.method` against `HttpMethod.<verb>` constants. We
  # surface the verbs we can see referenced in the file and fall back
  # to the standard set when the file looks like a catch-all (no
  # explicit `HttpMethod.*` references).
  #
  # `_middleware.dart` and other underscore-prefixed Dart files are
  # framework plumbing — not user-facing routes — and skipped.
  class DartFrog < Analyzer
    HTTP_METHOD_MAP = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "patch"   => "PATCH",
      "head"    => "HEAD",
      "options" => "OPTIONS",
    }

    FALLBACK_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?)
      result = [] of Endpoint
      mutex = Mutex.new

      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_filtered_files(channel, ".dart")

        parallel_analyze(channel) do |path|
          next unless path.ends_with?(".dart")

          idx = path.index("/routes/")
          next if idx.nil?

          relative = path[(idx + "/routes/".size)..-1]
          leaf = File.basename(relative)
          next if leaf.starts_with?("_") # `_middleware.dart` and other plumbing

          url = url_for(relative)

          content = begin
            read_file_content(path)
          rescue e
            logger.debug "Error reading #{path}: #{e.message}"
            next
          end

          methods = detect_methods(content)
          callees = include_callee ? callees_for_on_request(content, path) : [] of Noir::DartCalleeExtractor::Entry
          mutex.synchronize do
            methods.each do |verb|
              result << build_endpoint(url, verb, path, callees)
            end
          end
        end
      rescue e
        logger.debug e
      end

      result
    end

    private def build_endpoint(url : String,
                               verb : String,
                               path : String,
                               callees : Array(Noir::DartCalleeExtractor::Entry) = [] of Noir::DartCalleeExtractor::Entry) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.details = Details.new(PathInfo.new(path, 1))
      url.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      Noir::DartCalleeExtractor.attach_to(endpoint, callees)
      endpoint
    end

    private def callees_for_on_request(content : String, path : String) : Array(Noir::DartCalleeExtractor::Entry)
      content.scan(/\bonRequest\s*\(/) do |match|
        match_start = match.begin(0) || 0
        open_paren = Noir::DartCalleeExtractor.find_next_code_char(content, '(', match_start)
        next unless open_paren

        close_paren = Noir::DartCalleeExtractor.find_matching_delimiter(content, open_paren, '(', ')')
        next unless close_paren

        body_info = Noir::DartCalleeExtractor.extract_body_after(content, close_paren + 1)
        next unless body_info

        body, body_start, _ = body_info
        start_line = Noir::DartCalleeExtractor.line_number_for(content, body_start)
        return Noir::DartCalleeExtractor.callees_for_body(body, path, start_line)
      end

      [] of Noir::DartCalleeExtractor::Entry
    end

    # Filesystem path → URL pattern. Drops the `.dart` extension,
    # collapses `/index` into the parent, and translates `[id]`
    # to `{id}`.
    private def url_for(relative : String) : String
      stripped = relative.ends_with?(".dart") ? relative[0..-".dart".size - 1] : relative
      segments = stripped.split("/").reject(&.empty?).map { |seg| convert_segment(seg) }
      url = "/" + segments.join("/")
      url = url.sub(/\/index$/, "")
      url = "/" if url.empty?
      url
    end

    private def convert_segment(seg : String) : String
      if m = seg.match(/^\[(\w+)\]$/)
        return "{#{m[1]}}"
      end
      seg
    end

    private def detect_methods(content : String) : Array(String)
      verbs = [] of String
      HTTP_METHOD_MAP.each do |dart_name, verb|
        # Dart Frog exposes verbs as `HttpMethod.<lowercase>` constants.
        # Both `==` comparison and `case`/`switch` patterns reach here.
        if content.match(/HttpMethod\.#{dart_name}\b/)
          verbs << verb
        end
      end
      verbs.empty? ? FALLBACK_METHODS : verbs.uniq
    end
  end
end
