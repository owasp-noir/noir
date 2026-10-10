require "./nextjs"

module Analyzer::Javascript
  # Expo Router API routes: `+api` modules under `app/` (or `src/app/`)
  # export Web `Request` handlers named for their verb, exactly like a
  # Next.js app-router `route.ts`, so this rides the Next.js handler reader.
  #
  #   app/api/users+api.ts            → /api/users
  #   app/api/users/[id]+api.ts       → /api/users/{id}
  #   app/(tabs)/api/index+api.ts     → /api
  #
  # Every other module under `app/` is a client screen and adds nothing.
  class ExpoRouter < Nextjs
    analyzer_for "js_expo_router"

    API_MODULE = /\+api\.[jt]sx?$/

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      include_callee = callees_needed?
      owners = js_package_owners(["\"expo-router\""])
      return result unless owners.values.includes?(true)

      parallel_file_scan(EXTENSIONS) do |path|
        next unless path.matches?(API_MODULE)
        scoped = base_relative_path(path)
        idx = scoped.index("/app/") || next
        next unless owned_by_js_package?(path, owners)

        segments = scoped[(idx + "/app/".size)..].sub(API_MODULE, "").split('/')
        segments.pop if segments.last == "index"
        analyze_route_handler_file(path, file_route_url(segments), result, mutex, include_callee)
      end

      result
    end
  end
end
