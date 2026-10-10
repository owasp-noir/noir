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
        # The routes root is `app/` (or `src/app/`) beside the package.json,
        # not the first `app/` anywhere in the path: a project directory
        # itself named `app` would otherwise prefix every URL with `/app`.
        root = js_package_dir(path, owners) || next
        next unless owners[root]
        relative = Noir::PathScope.base_relative(Noir::PathScope.expand(path), root)
        routed = relative.lchop?("/app/") || relative.lchop?("/src/app/") || next

        segments = routed.sub(API_MODULE, "").split('/')
        segments.pop if segments.last == "index"
        analyze_route_handler_file(path, file_route_url(segments), result, mutex, include_callee)
      end

      result
    end
  end
end
