require "../../../models/analyzer"

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
          mutex.synchronize do
            methods.each do |verb|
              result << build_endpoint(url, verb, path)
            end
          end
        end
      rescue e
        logger.debug e
      end

      result
    end

    private def build_endpoint(url : String, verb : String, path : String) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.details = Details.new(PathInfo.new(path, 1))
      url.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      endpoint
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
