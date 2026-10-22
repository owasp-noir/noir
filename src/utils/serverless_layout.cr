require "./text_file"

module Noir
  # File-system layout rules shared by the file-routed serverless platforms
  # (Cloudflare Pages `functions/`, Vercel `api/`, Netlify
  # `netlify/functions/`). Detectors and analyzers both need to know which
  # directory a route is relative to, so the rule lives here rather than in
  # either layer.
  module ServerlessLayout
    extend self

    # Files that mark a directory as a deployable project root.
    PROJECT_MARKERS = {
      "package.json", "vercel.json", "now.json", "netlify.toml",
      "wrangler.toml", "wrangler.json", "wrangler.jsonc",
    }

    # Locate the routing directory for `path`: the first `dir_name` segment
    # of its scan-base-relative form (`relative`, rooted with `/`) that sits
    # at the scan root or directly inside a project root. Returns the
    # absolute project root plus the path segments below the routing dir.
    #
    # Anchoring on a project root is what keeps `src/pages/api/x.ts` (Next.js)
    # or `server/api/x.ts` (Nuxt) from being read as a Vercel `api/` dir, and
    # `netlify/functions/x.ts` from being read as Cloudflare `functions/`.
    def routing_remainder(path : String, relative : String, dir_name : String) : Tuple(String, Array(String))?
      segments = relative.split('/').reject(&.empty?)
      return if segments.size < 2

      (segments.size - 1).times do |i|
        next unless segments[i] == dir_name
        root = ancestor(path, segments.size - i)
        next unless i == 0 || project_root?(root)
        return {root, segments[(i + 1)..]}
      end
      nil
    end

    def project_root?(dir : String) : Bool
      PROJECT_MARKERS.any? { |marker| File.exists?(File.join(dir, marker)) }
    end

    # `File.dirname` applied `levels` times.
    def ancestor(path : String, levels : Int32) : String
      dir = path
      levels.times { dir = File.dirname(dir) }
      dir
    end

    VERCEL_CONFIGS         = {"vercel.json", "now.json"}
    VERCEL_PACKAGE_MARKERS = {"\"@vercel/node\"", "\"@vercel/functions\""}
    # A module importing the Vercel runtime types marks itself as a function.
    VERCEL_IMPORT         = /(?:\bfrom\s*|\brequire\s*\(\s*|\bimport\s*\(\s*)['"]@vercel\/(?:node|functions)['"]/
    NETLIFY_FUNCTION_DIRS = {"functions", "edge-functions"}

    # Whether `root` is a Vercel project: it carries a `vercel.json` /
    # `now.json`, or its package.json depends on the Vercel runtime types.
    def vercel_project?(root : String) : Bool
      return true if VERCEL_CONFIGS.any? { |config| File.exists?(File.join(root, config)) }
      package = File.join(root, "package.json")
      return false unless File.exists?(package)
      content = Noir::TextFile.read(package) rescue ""
      VERCEL_PACKAGE_MARKERS.any? { |marker| content.includes?(marker) }
    end

    # Netlify's default function directories: `netlify/functions/` and
    # `netlify/edge-functions/` under the site's base directory. Returns
    # `{kind, segments_below_it}` where kind is `functions` or
    # `edge-functions`.
    def netlify_default_remainder(relative : String) : Tuple(String, Array(String))?
      segments = relative.split('/').reject(&.empty?)
      (segments.size - 2).times do |i|
        next unless segments[i] == "netlify" && NETLIFY_FUNCTION_DIRS.includes?(segments[i + 1])
        return {segments[i + 1], segments[(i + 2)..]}
      end
      nil
    end

    # A Netlify function's name from its path below the functions directory:
    # `hello.mts`, `hello/hello.mts` and `hello/index.mts` are all `hello`.
    # Anything deeper, or a sibling module in a function's own directory, is
    # a helper and not a function.
    def netlify_function_name(segments : Array(String)) : String?
      case segments.size
      when 1
        stem(segments[0])
      when 2
        dir = segments[0]
        leaf = stem(segments[1])
        dir if leaf == dir || leaf == "index"
      end
    end

    # File name without its last extension.
    def stem(file : String) : String
      File.basename(file, File.extname(file))
    end

    # Colocated tests (`x.test.ts`, `x.spec.js`) and type declarations are
    # not deployed handlers.
    def non_handler_file?(path : String) : Bool
      path.ends_with?(".d.ts") || path.ends_with?(".d.mts") || path.ends_with?(".d.cts") ||
        path.matches?(/\.(?:test|spec)\.[cm]?[jt]sx?\z/)
    end

    # Hidden (`.x`) and private (`_x`) entries, which Vercel does not deploy.
    def private_segment?(segments : Array(String)) : Bool
      segments.any? { |seg| seg.starts_with?('.') || seg.starts_with?('_') }
    end
  end
end
