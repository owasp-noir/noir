require "./detectors/**"
require "../models/detector"
require "../models/passive_scan"
require "../techs/techs.cr" # Added to define NoirTechs
require "../passive_scan/detect.cr"
require "wait_group"
require "../utils/media_filter"
require "yaml"

macro define_detectors(detectors)
  {% for detector, index in detectors %}
    instance = Detector::{{ detector }}.new(options)
    instance.set_name
    detector_list << instance
  {% end %}
end

# Reference-typed atomic Boolean. Wrapping `Atomic(Int8)` in a
# class keeps the underlying byte addressable through an Array
# index (`Atomic` itself is a struct and would copy on `[]`).
class AtomicFlag
  def initialize
    @value = Atomic(Int8).new(0_i8)
  end

  def get : Bool
    @value.get != 0_i8
  end

  def set
    @value.set(1_i8)
  end
end

DETECTOR_IGNORED_DIR_NAMES = Set{
  # Source control / IDE / agent state
  ".git", ".idea", ".vscode", ".claude",
  # Language-specific dependency / build caches
  "node_modules", "vendor", "__pycache__", ".venv", "venv",
  ".pytest_cache", ".tox", ".gradle", ".bundle", ".dart_tool",
  ".cargo", ".terraform",
  # Zig build outputs / fetched-dependency cache. Vendored deps under
  # `.zig-cache` carry their own `@import("httpz")` etc. and would
  # otherwise make every Zig project look like it uses every framework.
  ".zig-cache", "zig-cache", ".zig-out", "zig-out",
  # Common build / dist / cache outputs
  "dist", "build", "target", "out", "tmp", ".cache",
  ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache",
  ".serverless", ".expo",
  # Test coverage / reports
  "coverage", ".coverage",
  # iOS / macOS noise
  "Pods", "__MACOSX",
}

DETECTOR_IGNORED_DIR_SUFFIXES = Set{
  # Xcode asset catalogs. They contain images plus many Contents.json
  # metadata files; none are source/spec files for route detection, and
  # large iOS apps can carry hundreds of them.
  ".xcassets",
}

ANDROID_SOURCE_SUBDIRS = Set{
  "aidl",
  "assets",
  "cpp",
  "java",
  "jni",
  "kotlin",
  "res",
}

MOBILE_DETECTOR_NAMES = Set{
  "android",
  "ios",
  "well_known_applinks",
}

# Strong server-routing constructs. A `.kt` / `.java` file that sits
# inside an Android app's source set is normally scoped to mobile
# detectors only (an incidental `import ...SpringApplication` must not
# flag the project as a server). But an Android app can legitimately
# *embed* an on-device HTTP server — e.g. plain-app runs a local Ktor
# web server whose routes live under `app/src/main/java/...`. When a
# file carries one of these markers it is a real server, so the
# Ktor / http4k / Spring detectors are allowed to run on it. Kept as a
# single precompiled constant — recompiling it per file would recreate
# the PCRE2 program on every read.
ANDROID_EMBEDDED_SERVER_MARKER = /io\.ktor\.server\.|embeddedServer|\brouting\s*\{|\bfun\s+Route\.|org\.http4k\.routing|@RestController|@RequestMapping|@(?:Get|Post|Put|Delete|Patch)Mapping|\bRouterFunction\b/

def detector_android_source_prefixes_for_manifest(manifest_path : String) : Array(String)
  prefixes = [] of String
  manifest_dir = File.dirname(manifest_path)
  manifest_dir_parts = manifest_dir.split(File::SEPARATOR)
  src_index = manifest_dir_parts.rindex("src")

  source_set_root = if src_index && src_index == manifest_dir_parts.size - 2
                      manifest_dir
                    end

  if source_set_root
    ANDROID_SOURCE_SUBDIRS.each do |subdir|
      prefixes << File.join(source_set_root, subdir) + File::SEPARATOR
    end
  else
    ANDROID_SOURCE_SUBDIRS.each do |subdir|
      prefixes << File.join(manifest_dir, subdir) + File::SEPARATOR
      prefixes << File.join(manifest_dir, "src", subdir) + File::SEPARATOR
      prefixes << File.join(manifest_dir, "src", "main", subdir) + File::SEPARATOR
    end
  end

  prefixes
end

def detector_add_android_source_prefixes_from_dir(dir : String, prefixes : Array(String))
  manifest_path = File.join(dir, "AndroidManifest.xml")
  return unless File.exists?(manifest_path)

  begin
    content = File.read(manifest_path, encoding: "utf-8", invalid: :skip)
    return unless content.includes?("<manifest")
  rescue File::NotFoundError | File::AccessDeniedError
    return
  end

  detector_android_source_prefixes_for_manifest(manifest_path).each do |prefix|
    prefixes << prefix unless prefixes.includes?(prefix)
  end
end

def detector_android_source_file?(path : String, prefixes : Array(String)) : Bool
  prefixes.any? { |prefix| path.starts_with?(prefix) }
end

def detector_mobile_detector?(name : String) : Bool
  MOBILE_DETECTOR_NAMES.includes?(name)
end

# Filenames that detectors match by exact basename (often with path
# constraints like "must sit at the project root"). These must not share
# an extension-only cache bucket — e.g. `vercel.json` is not "any .json".
DETECTOR_SPECIAL_BASENAMES = Set{
  "package.json", "tsconfig.json", "composer.json", "composer.lock",
  "vercel.json", "now.json", "netlify.toml", "wrangler.toml",
  "Gemfile", "Gemfile.lock", "Package.swift", "Cargo.toml", "go.mod",
  "mix.exs", "pubspec.yaml", "pubspec.lock", "shard.yml", "shard.lock",
  "build.sbt", "pom.xml", "AndroidManifest.xml", "config.toml",
  "rebar.config", "erlang.mk", "project.clj", "deps.edn", "stack.yaml",
  "package.yaml", "gleam.toml", "manifest.toml", "paket.dependencies",
  "Caddyfile", "Dockerfile", "Makefile", "Rakefile", "serverless.yml",
  "serverless.yaml", "app.yaml", "openapi.yaml", "openapi.json",
  "swagger.json", "swagger.yaml",
}

# Paths that embed directory segments real detectors gate on
# (`/grails-app/`, `/migrations/`, `/server/api/`, …). Used only to
# classify path-sensitive detectors — not as production file samples.
DETECTOR_PATH_SEGMENT_PROBES = [
  # Extension-free path under grails-app: only matches via the directory
  # gate (a bare `Foo.groovy` basename is true for other reasons).
  "proj/grails-app/conf/application",
  "proj/supabase/migrations/001.sql",
  "proj/migrations/001.sql",
  "proj/supabase/config.toml",
  "proj/server/api/hello.js",
  "proj/server/routes/hello.js",
  "proj/pages/api/hello.js",
  "proj/app/api/hello/route.ts",
  "proj/routes/+server.ts",
  "proj/routes/index.dart",
  "proj/directus/snapshots/snap.json",
  "proj/wp-content/plugins/x.php",
  "proj/metadata/databases/tables.yaml",
  "proj/Magento/module.xml",
]

# Whether `applicable?` depends on more than the basename (root
# placement, directory segments, multi-hop path layout). Those
# detectors must always see the real path in the hot loop.
def detector_path_sensitive?(detector : Detector) : Bool
  # Explicit declaration wins. The probe sweep below is a safety net,
  # not the contract: it is fail-open by construction, so a detector
  # whose directory gate happens to agree with its basename gate on
  # every probe would otherwise be memoized as basename-only and lose
  # the path check entirely.
  return true if detector.path_sensitive?

  sample_suffixes = [
    ".java", ".js", ".ts", ".tsx", ".rb", ".py", ".go", ".json", ".yml",
    ".yaml", ".xml", ".cs", ".kt", ".php", ".cr", ".rs", ".ex", ".swift",
    ".scala", ".dart", ".groovy", ".pl", ".clj", ".hs", ".lua", ".sql",
    ".toml", ".bru", ".http", ".sbt", ".gradle", ".aspx", ".fs",
  ]
  # Bare names: catch "must sit at project root" checks (Vercel,
  # Package.swift, …) where `name` is true but `a/b/c/name` is false.
  basenames = DETECTOR_SPECIAL_BASENAMES.to_a + sample_suffixes.map { |ext| "file#{ext}" }
  basenames.any? do |name|
    detector.applicable?("a/b/c/#{name}") != detector.applicable?(name)
  end || DETECTOR_PATH_SEGMENT_PROBES.any? do |probe|
    # Directory-segment gates: same basename, different path → different
    # answer (Supabase `/migrations/`, Grails `/grails-app/`, …).
    detector.applicable?(probe) != detector.applicable?(File.basename(probe))
  end
end

# Build a lookup that turns a path into the list of detector indices
# whose `applicable?` returns true — without re-walking every detector
# on every file. Most detectors only inspect extension / basename, so
# their answers are memoized by basename. Detectors that look at path
# segments or root placement are classified as path-sensitive and
# always evaluated against the real path.
def detector_build_applicable_lookup(detectors : Array(Detector)) : Proc(String, Array(Int32))
  path_sensitive = [] of Int32
  detectors.each_with_index do |detector, idx|
    path_sensitive << idx if detector_path_sensitive?(detector)
  end

  path_sensitive_set = Set(Int32).new(path_sensitive)
  # Key by basename, not bare extension: many detectors gate on
  # basename substrings (`*deploy*.yml`, `*sites*.yaml`) or exact
  # names (`package.json`). An extension-only key would probe
  # `file.yml` and drop every basename-qualified match.
  cache = {} of String => Array(Int32)

  ->(path : String) do
    base = File.basename(path)

    cached = cache[base]?
    unless cached
      idxs = [] of Int32
      detectors.each_with_index do |detector, idx|
        next if path_sensitive_set.includes?(idx)
        idxs << idx if detector.applicable?(base)
      end
      cache[base] = idxs
      cached = idxs
    end

    # Always dup: callers `reject!` android-scope / JSON-spec candidates
    # in place and must not corrupt the memoized array.
    result = cached.dup
    path_sensitive.each do |idx|
      result << idx if detectors[idx].applicable?(path)
    end
    result
  end
end

def detect_techs(base_paths : Array(String), options : Hash(String, YAML::Any), passive_scans : Array(PassiveScan), logger : NoirLogger)
  techs = [] of String
  passive_result = [] of PassiveScanResult
  detector_list = [] of Detector
  mutex = Mutex.new

  # Define detectors
  define_detectors([
    Cpp::Drogon,
    Cpp::Cli,
    Cpp::Crow,
    Cpp::Httplib,
    Cpp::Oatpp,
    Cfml::Pure,
    Cfml::Taffy,
    Cfml::Coldbox,
    Cfml::Wheels,
    Cfml::Fw1,
    Asp::Classic,
    Aspnet::WebForms,
    Clojure::Cli,
    Clojure::Compojure,
    Clojure::Pedestal,
    Clojure::Reitit,
    Clojure::Ring,
    CSharp::Cli,
    CSharp::AspNetMvc,
    CSharp::AspNetCoreMvc,
    CSharp::AspNetCoreMinimalApi,
    CSharp::Carter,
    CSharp::FastEndpoints,
    CSharp::HttpListener,
    CSharp::SignalR,
    Crystal::Cli,
    Crystal::Amber,
    Crystal::Grip,
    Crystal::Kemal,
    Crystal::Lucky,
    Crystal::Marten,
    Crystal::Http,
    Dart::Cli,
    Dart::Alfred,
    Dart::Angel3,
    Dart::GetServer,
    Dart::DartFrog,
    Dart::Http,
    Dart::Serverpod,
    Dart::Shelf,
    Elixir::Cli,
    Elixir::Bandit,
    Elixir::Phoenix,
    Elixir::PhoenixChannel,
    Elixir::Plug,
    Erlang::Cowboy,
    Erlang::Elli,
    Fsharp::Giraffe,
    Gleam::Wisp,
    Perl::Cli,
    Perl::Catalyst,
    Perl::Dancer2,
    Perl::Mojolicious,
    Go::Beego,
    Go::Cli,
    Go::Echo,
    Go::Fasthttp,
    Go::Fiber,
    Go::Gin,
    Go::Hertz,
    Go::Iris,
    Go::GoRestful,
    Go::Chi,
    Go::GoZero,
    Go::Goyave,
    Go::Gf,
    Go::Http,
    Go::Httprouter,
    Go::Huma,
    Go::Mux,
    Go::Pocketbase,
    Go::ConnectRpc,
    Groovy::Cli,
    Groovy::Grails,
    Haskell::Cli,
    Haskell::Scotty,
    Haskell::Servant,
    Haskell::Yesod,
    Specification::AsyncApi,
    Specification::Envoy,
    Specification::Grpc,
    Specification::Har,
    Java::Cli,
    Java::Armeria,
    Java::Dropwizard,
    Java::HttpServer,
    Java::Javalin,
    Java::JaxRs,
    Java::Jsp,
    Java::Micronaut,
    Java::Quarkus,
    Java::Spark,
    Java::Spring,
    Java::Struts2,
    Lua::Cli,
    Lua::Lapis,
    Lua::Lor,
    Mobile::Android,
    Mobile::Ios,
    Mobile::WellKnown,
    Java::Vertx,
    Java::Wicket,
    Javascript::Adonisjs,
    Javascript::Cli,
    Javascript::Apollo,
    Javascript::Astro,
    Javascript::Elysia,
    Javascript::Express,
    Javascript::Fastify,
    Javascript::Fresh,
    Javascript::GraphqlYoga,
    Javascript::Hapi,
    Javascript::Hono,
    Javascript::Http,
    Javascript::Koa,
    Javascript::Nestjs,
    Javascript::Nextjs,
    Javascript::Nitro,
    Javascript::Nuxtjs,
    Javascript::Remix,
    Javascript::SocketIO,
    Javascript::Restify,
    Javascript::Sveltekit,
    Kotlin::Cli,
    Kotlin::Http4k,
    Kotlin::Spring,
    Kotlin::Ktor,
    Specification::Bruno,
    Specification::Burp,
    Specification::Caddy,
    Specification::Caido,
    Specification::GraphqlSdl,
    Specification::HttpFile,
    Specification::ApacheHttpd,
    Specification::Apisix,
    Specification::Appwrite,
    Specification::AwsCdk,
    Specification::AwsCloudformation,
    Specification::AzureFunctions,
    Specification::CloudflareWrangler,
    Specification::Directus,
    Specification::Hasura,
    Specification::K8sGatewayApi,
    Specification::K8sIngress,
    Specification::Kong,
    Specification::Oas2,
    Specification::Oas3,
    Specification::Insomnia,
    Specification::IstioVirtualservice,
    Specification::Kamal,
    Specification::Mitmproxy,
    Specification::Netlify,
    Specification::Nginx,
    Specification::OData,
    Specification::OpenRpc,
    Specification::PayloadCms,
    Specification::Postman,
    Specification::RAML,
    Specification::ServerlessFramework,
    Specification::Strapi,
    Specification::Supabase,
    Specification::Terraform,
    Specification::Smithy,
    Specification::Traefik,
    Specification::TypeSpec,
    Specification::Vercel,
    Specification::WSDL,
    Specification::ZapSitesTree,
    Php::Php,
    Php::Cli,
    Php::CakePHP,
    Php::CodeIgniter,
    Php::Drupal,
    Php::Hyperf,
    Php::Laminas,
    Php::Laravel,
    Php::Lumen,
    Php::Magento,
    Php::Mautic,
    Php::Slim,
    Php::Symfony,
    Php::ThinkPHP,
    Php::Wordpress,
    Php::Yii,
    Python::Aiohttp,
    Python::Cli,
    Python::Django,
    Python::DjangoNinja,
    Python::FastAPI,
    Python::Bottle,
    Python::Falcon,
    Python::Flask,
    Python::Litestar,
    Python::Pyramid,
    Python::Quart,
    Python::Robyn,
    Python::Sanic,
    Python::Starlette,
    Python::Tornado,
    Python::HttpServer,
    R::Plumber,
    Ruby::Cli,
    Ruby::ActionCable,
    Ruby::Grape,
    Ruby::Hanami,
    Ruby::Rails,
    Ruby::Roda,
    Ruby::Sinatra,
    Ruby::Webrick,
    Rust::Cli,
    Rust::Axum,
    Rust::Rocket,
    Rust::ActixWeb,
    Rust::Loco,
    Rust::Rwf,
    Rust::Tide,
    Rust::Warp,
    Rust::Gotham,
    Rust::Salvo,
    Rust::Poem,
    Scala::Cli,
    Scala::Akka,
    Scala::Scalatra,
    Scala::Play,
    Scala::Http4s,
    Scala::ZioHttp,
    Scala::Tapir,
    Java::Play,
    Swift::Cli,
    Swift::Vapor,
    Swift::Kitura,
    Swift::Hummingbird,
    Typescript::Nestjs,
    Typescript::TanstackRouter,
    Typescript::TRPC,
    Zig::Cli,
    Zig::Jetzig,
    Zig::Zap,
    Zig::Http,
    Zig::Httpz,
    Zig::Tokamak,
  ])

  # Handle --only-techs: filter detector_list to only specified techs
  only_techs_value = options["only_techs"]?.to_s
  if only_techs_value.size > 0
    only_techs_list = only_techs_value.split(",").map do |tech|
      NoirTechs.similar_to_tech(tech.strip)
    end.reject(&.empty?)

    if only_techs_list.empty?
      logger.error "No valid technologies specified in --only-techs. No detectors will be run."
      detector_list.clear
    else
      logger.info "Filtering detectors to: #{only_techs_list.join(", ")}"
      detector_list.select! do |detector|
        only_techs_list.includes?(detector.name)
      end
      logger.debug "Using #{detector_list.size} detector(s)"
    end
  end

  # Handle -t/--techs: add techs directly (without detection validation)
  if options["techs"].to_s.size > 0
    techs_tmp = options["techs"].to_s.split(",")
    logger.success "Setting #{techs_tmp.size} techs from command line."
    techs_tmp.each do |tech|
      similar_tech = NoirTechs.similar_to_tech(tech)
      if similar_tech.empty?
        logger.error "#{tech} is not recognized in the predefined tech list."
      else
        logger.success "Added #{tech} to techs."
        techs << similar_tech
      end
    end
  end

  # Resolve the severity threshold and prune the rule set once,
  # before the reader/workers spawn. The previous shape did this
  # lookup and comparison inside the per-file hot loop, costing one
  # Hash lookup + downcase per (file × rule).
  min_severity = options["passive_scan_severity"]?.try(&.to_s) || "high"
  active_passive_scans = NoirPassiveScan.filter_rules_by_severity(passive_scans, min_severity)

  generic_json_spec_detector_names = Set{
    "apisix",
    "asyncapi",
    "aws_cloudformation",
    "caddy",
    "caido",
    "envoy",
    "har",
    "insomnia",
    "oas2",
    "oas3",
    "openrpc",
    "postman",
  }
  generic_json_spec_marker = /"(?:openapi|swagger|asyncapi|openrpc|_postman_id|__export_format|_type|routes|uri|uris|upstream_id|plugins|log|entries|host|method|path|raw|is_tls|port|apps|http|virtual_hosts|domains|AWSTemplateFormatVersion)"|schema\.(?:getpostman|postman)\.com|AWS::Serverless-2016-10-31/

  channel = Channel(Tuple(String, String, Array(Int32))).new(Analyzer::DEFAULT_CONTENT_CHANNEL_CAPACITY)
  locator = CodeLocator.instance
  wg = WaitGroup.new

  # Clear detector-populated locator keys before starting. These arrays
  # are side effects of idempotent? == false mobile/spec detectors, so
  # they should represent the current detection run only.
  locator.clear("file_map")
  locator.clear("android-manifest")
  locator.clear("android-assetlinks")
  locator.clear("ios-info-plist")
  locator.clear("ios-entitlements")
  locator.clear("ios-aasa")

  android_source_scope_active = detector_list.any? { |detector| detector_mobile_detector?(detector.name) }
  android_source_prefixes = [] of String
  # Built once before the reader starts. Replaces the per-file
  # O(detectors) `applicable?` walk with an extension/basename memo
  # plus a short path-sensitive tail (see detector_build_applicable_lookup).
  applicable_lookup = detector_build_applicable_lookup(detector_list)

  # A malformed `--exclude-path` glob makes `File.match?` raise
  # `File::BadPatternError`. In practice that means an unterminated `[`
  # character class: the pattern list is comma-separated (so a `{a,b}`
  # brace group can never arrive intact) and backslashes are folded to
  # `/` above, which rules out the escape-related raises.
  #
  # The raise fires inside the reader fiber below, mid-walk, and only
  # once traversal actually reaches the malformed part — so `[bad`
  # raises on the first file while `src/[bad` survives until the walk
  # descends into `src/`. Left unhandled the fiber died silently: the
  # walk stopped wherever it was, every remaining file went unscanned,
  # and noir reported "No technologies detected" with exit 0 — an empty
  # or partial scan indistinguishable from a genuinely empty codebase.
  # Capture it here and fail loudly after the WaitGroup instead.
  exclude_pattern_error : String? = nil

  # Thread for reading files and sending their contents to the channel
  wg.add(1)
  spawn do
    begin
      skipped_files = 0
      skipped_content_reads = 0
      total_files = 0
      skipped_ignored_dirs = 0

      # User-supplied --exclude-path patterns (comma-separated globs).
      # Patterns containing "/" are matched against the relative path;
      # patterns without "/" are matched against the basename.
      # Partition once up front so the per-file loop only walks the two
      # already-classified lists — no substring check per file.
      # Normalize Windows-style backslashes to '/' before classifying, so a
      # pattern like `src\legacy` is treated as a path pattern (and matches)
      # instead of an unmatchable basename.
      exclude_path_raw = options["exclude_path"]?.to_s
        .split(",").map(&.strip.gsub('\\', '/')).reject(&.empty?)
      path_patterns, basename_patterns = exclude_path_raw.partition(&.includes?('/'))
      exclude_path_active = !exclude_path_raw.empty?
      # macOS/Windows default filesystems are case-insensitive, so
      # `--exclude-path MyFile.go` should also exclude `myfile.go` there. Fold
      # case only on those platforms — folding on Linux would wrongly drop
      # case-distinct files that legitimately coexist.
      exclude_case_insensitive = {% if flag?(:darwin) || flag?(:windows) %} true {% else %} false {% end %}
      exclude_basename_patterns = exclude_case_insensitive ? basename_patterns.map(&.downcase) : basename_patterns
      exclude_path_patterns = exclude_case_insensitive ? path_patterns.map(&.downcase) : path_patterns
      skipped_exclude_path = 0

      base_paths.each do |base_path|
        # Pre-compute base path prefix for fast relative path calculation
        base_prefix = base_path.ends_with?("/") ? base_path : base_path + "/"

        # Iterative DFS. Avoids `Dir.glob("**/**")`, which enumerates every
        # file under ignored subtrees before any filter runs; on a Node
        # monorepo with a 100k-entry node_modules this was the dominant
        # cost of the detect phase.
        stack = [base_path]
        until stack.empty?
          dir = stack.pop
          # Crystal's vendor convention is `lib/` next to `shard.yml`
          # (same shape as Node's node_modules / Ruby's vendor/bundle).
          # The directory name `lib` is too generic to put in the global
          # ignored set — Rails / Python / many other ecosystems use it
          # for source. Resolve the ambiguity contextually: skip `lib/`
          # only when a sibling `shard.yml` is present.
          dir_has_shard = File.exists?(File.join(dir, "shard.yml"))
          if android_source_scope_active
            detector_add_android_source_prefixes_from_dir(dir, android_source_prefixes)
          end
          begin
            Dir.each_child(dir) do |entry|
              full_path = File.join(dir, entry)
              info = File.info?(full_path, follow_symlinks: false)
              next if info.nil?

              if info.directory?
                # Subtree prune happens here. Entry name (not full path)
                # so the base-as-node_modules case from #912 is safe.
                if DETECTOR_IGNORED_DIR_NAMES.includes?(entry) || DETECTOR_IGNORED_DIR_SUFFIXES.any? { |suffix| entry.ends_with?(suffix) }
                  skipped_ignored_dirs += 1
                  next
                end
                if entry == "lib" && dir_has_shard
                  skipped_ignored_dirs += 1
                  next
                end
                stack << full_path
                next
              end

              # `info` was obtained with follow_symlinks: false, so symlinks
              # land here as type=symlink and `info.file?` is false — they
              # are skipped entirely. This is a minor behavior change from
              # the previous `Dir.glob` implementation, which would have
              # yielded symlinked regular files for scanning. Skipping them
              # trades coverage of unusual monorepo layouts for a simpler
              # cycle guard; revisit if a real project needs the old
              # behavior. Non-regular files (FIFOs, sockets, devices) are
              # also dropped here — previously they would reach `File.read`
              # and either hang or error out.
              next unless info.file?

              total_files += 1

              if exclude_path_active
                entry_cmp = exclude_case_insensitive ? entry.downcase : entry
                if exclude_basename_patterns.any? { |pat| File.match?(pat, entry_cmp) }
                  skipped_exclude_path += 1
                  next
                end
                if !exclude_path_patterns.empty?
                  rel_path = full_path.starts_with?(base_prefix) ? full_path[base_prefix.size..] : full_path
                  {% if flag?(:windows) %} rel_path = rel_path.gsub('\\', '/') {% end %}
                  rel_cmp = exclude_case_insensitive ? rel_path.downcase : rel_path
                  # File.match? handles glob patterns (`tests/*`, `**/dir/**`);
                  # the equality / prefix checks add plain-directory exclusion
                  # so `--exclude-path src/legacy` drops everything under it,
                  # not just a file literally named `src/legacy`.
                  if exclude_path_patterns.any? do |pat|
                       dir_pat = pat.rstrip('/')
                       File.match?(pat, rel_cmp) || rel_cmp == dir_pat || rel_cmp.starts_with?("#{dir_pat}/")
                     end
                    skipped_exclude_path += 1
                    next
                  end
                end
              end

              if skip_reason = MediaFilter.skip_check(full_path, info: info, sniff_binary: false)
                logger.debug "Skipping #{full_path}: #{skip_reason}"
                skipped_files += 1
                next
              end

              candidate_detector_indices = applicable_lookup.call(full_path)

              # An Android source-set file is normally narrowed to the
              # mobile detectors only (see ANDROID_EMBEDDED_SERVER_MARKER /
              # the Android-source scope spec). The exception — a genuine
              # embedded on-device server — can only be told apart from an
              # incidental framework import by reading the file, so defer
              # the narrowing until after the content read below.
              android_source_file = detector_android_source_file?(full_path, android_source_prefixes)
              if android_source_file && candidate_detector_indices.all? { |idx| detector_mobile_detector?(detector_list[idx].name) }
                # No server detector is even applicable here, so the
                # marker check cannot change the outcome — keep the
                # content-free fast path.
                android_source_file = false
              end

              if candidate_detector_indices.empty? && active_passive_scans.empty? && !android_source_file
                # Keep the path visible to analyzers without paying to
                # read/cache content that neither detection nor passive
                # scan will inspect. Analyzer reads still fall back to
                # File.read when a file was not cached here.
                locator.push("file_map", full_path)
                skipped_content_reads += 1
                next
              end

              content = File.read(full_path, encoding: "utf-8", invalid: :skip)
              if content.to_slice.includes?(0_u8)
                logger.debug "Skipping #{full_path}: binary content (file is text-extension but bytes look binary)"
                skipped_files += 1
                next
              end

              # Apply the Android-source narrowing now that content is
              # available: drop the server-framework detectors unless the
              # file carries a real server-routing construct (an embedded
              # on-device server).
              if android_source_file && !content.matches?(ANDROID_EMBEDDED_SERVER_MARKER)
                candidate_detector_indices.reject! do |idx|
                  !detector_mobile_detector?(detector_list[idx].name)
                end
                if candidate_detector_indices.empty? && active_passive_scans.empty?
                  # Nothing left to detect and no passive scan to run.
                  # register_file already records the path in file_map and
                  # caches the (already-read) content for the analyzers.
                  locator.register_file(full_path, content)
                  next
                end
              end

              if full_path.ends_with?(".json") && !content.matches?(generic_json_spec_marker)
                candidate_detector_indices = candidate_detector_indices.reject do |idx|
                  generic_json_spec_detector_names.includes?(detector_list[idx].name)
                end
              end

              channel.send({full_path, content, candidate_detector_indices})
              # Register the path in file_map and (budget permitting)
              # cache the content so analyzers can skip the re-read.
              locator.register_file(full_path, content)
            end
          rescue File::NotFoundError | File::AccessDeniedError
            # Directory vanished or we can't read it — treat the subtree
            # as empty and move on.
          end
        end
      end

      if skipped_files > 0
        logger.info "Skipped #{skipped_files} media/large files out of #{total_files} total files"
      end
      if skipped_ignored_dirs > 0
        logger.debug "Pruned #{skipped_ignored_dirs} ignored directory tree(s)"
      end
      if skipped_exclude_path > 0
        logger.info "Skipped #{skipped_exclude_path} files matching --exclude-path patterns"
      end
      if skipped_content_reads > 0
        logger.debug "Avoided content reads for #{skipped_content_reads} file(s) with no applicable detectors"
      end

      stats = locator.content_cache_stats
      if stats[:budget] > 0
        cached_mb = (stats[:bytes] / (1024.0 * 1024.0)).round(1)
        budget_mb = (stats[:budget] / (1024.0 * 1024.0)).round(1)
        logger.debug "Content cache: #{stats[:files]} files / #{cached_mb} MB (budget #{budget_mb} MB, #{stats[:skipped]} skipped)"
      end
    rescue e : File::BadPatternError
      exclude_pattern_error = e.message || "invalid pattern"
    ensure
      channel.close
      wg.done
    end
  end

  # Threads for receiving and processing the contents from the channel
  concurrency = options["concurrency"].to_s.to_i

  # One reference-typed atomic flag per detector — set true once
  # `detect` matches on any file. Workers consult these flags
  # before invoking `detect()` so already-matched detectors are
  # skipped on the remaining files (techs are existence-only
  # signals). The wrapper class is necessary because `Atomic(T)`
  # is a struct: storing it directly in an `Array` would value-
  # copy on read, so `.set` would mutate a transient copy and
  # never persist.
  detected_flags = Array(AtomicFlag).new(detector_list.size) { AtomicFlag.new }

  concurrency.times do
    wg.add(1)
    spawn do
      begin
        loop do
          begin
            file_content = channel.receive?
            break if file_content.nil?
            file, content, candidate_detector_indices = file_content
            logger.debug "Detecting: #{file}"

            candidate_detector_indices.each do |idx|
              detector = detector_list[idx]
              # Skip detectors that have already matched, unless
              # the detector signals it has side effects in
              # `detect` (`idempotent? == false`) — see
              # `Detector#idempotent?` for the contract.
              next if detector.idempotent? && detected_flags[idx].get
              if detector.detect(file, content)
                detected_flags[idx].set
                newly_added = false
                mutex.synchronize do
                  unless techs.includes?(detector.name)
                    techs << detector.name
                    newly_added = true
                  end
                end
                if newly_added
                  logger.debug_sub "└── Detected: #{detector.name}"
                  logger.verbose_sub "└── Detected: #{detector.name} in #{file}"
                end
              end
            end

            # Severity is already filtered above; pass the pre-pruned
            # rule list through and let `detect` short-circuit when
            # it's empty (passive scan disabled or every rule pruned).
            if !active_passive_scans.empty?
              results = NoirPassiveScan.detect(file, content, active_passive_scans, logger)
              if results.size > 0
                mutex.synchronize do
                  passive_result.concat(results)
                end
              end
            end
          rescue File::NotFoundError
            logger.debug "File not found: #{file}"
          rescue e : Exception
            # Mirror `parallel_analyze`'s worker rescue. Without this a
            # single detector/passive-rule exception unwinds the whole
            # worker loop; once every worker has died the reader fiber
            # blocks forever on `channel.send` and the scan hangs with
            # no output instead of skipping one bad file.
            logger.debug "Error detecting #{file}: #{e.message}"
          end
        end
      ensure
        wg.done
      end
    end
  end

  wg.wait

  # The file walk aborted on a bad glob, so `techs` reflects only the
  # files read before the raise. Reporting that as a result would be a
  # silent lie; surface the pattern error and stop.
  if pattern_error = exclude_pattern_error
    raise Noir::InvalidExcludePathError.new(
      "--exclude-path contains an invalid glob pattern (#{pattern_error}): #{options["exclude_path"]?.to_s.inspect}. " \
      "Check the `[` character classes — each one must be closed with a `]`."
    )
  end

  logger.debug "Added #{locator.all("file_map").size} files to file_map"
  {techs.uniq, passive_result}
end
