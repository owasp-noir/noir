require "../../../models/detector"

module Detector::Typescript
  class TanstackRouter < Detector
    detector_for "ts_tanstack_router",
      extensions: %w[.ts .tsx .cts .mts .js .jsx .cjs .mjs],
      basenames: %w[package.json tsconfig.json]

    # Single precompiled alternation — one PCRE2 scan over the file.
    #
    # `createRouter(` and `createRoute(` used to be listed here as
    # standalone markers, and both are ordinary names other routers own:
    # `createRouter({ history, routes })` is *the* Vue Router 4 entry point,
    # Solid Router exports the same name, and tRPC v9's generated
    # `createRouter()` helper carries it too. Every Vue 3 project with a
    # TypeScript router module was therefore reported as TanStack Router and
    # paid for a TanStack analyzer pass that had nothing to extract.
    #
    # Nothing is lost by dropping them: a file that calls either factory has
    # to import it from `@tanstack/*router` in that same file, which the
    # import branches below match. Those branches no longer demand the
    # `import` keyword on the same line as the specifier either, so a
    # formatter-wrapped multi-line import (`import {\n  createRoute,\n} from
    # '@tanstack/react-router'`) is matched rather than relying on the bare
    # factory names to carry it.
    #
    # The package pattern covers every TanStack Router adapter
    # (`@tanstack/react-router`, `/solid-router`, `/svelte-router`, the bare
    # `/router`) without reaching `@tanstack/react-router-devtools`, which
    # the required closing quote excludes.
    #
    # `createFileRoute` / `createRootRoute` stay: they are TanStack's own
    # file-based routing API and have no other owner.
    SIGNAL = Regex.union(
      /from\s*['"]@tanstack\/(?:[a-z]+-)?router['"]/,
      /require\(\s*['"]@tanstack\/(?:[a-z]+-)?router['"]\s*\)/,
      /\bcreateFileRoute\s*\(/,
      /\bcreateLazyFileRoute\s*\(/,
      /\bcreateRootRoute(?:WithContext)?\s*[(<]/,
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".ts") || filename.ends_with?(".tsx")
      content_matches?(file_contents, SIGNAL)
    end
  end
end
