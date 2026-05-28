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

def detect_techs(base_paths : Array(String), options : Hash(String, YAML::Any), passive_scans : Array(PassiveScan), logger : NoirLogger)
  techs = [] of String
  passive_result = [] of PassiveScanResult
  detector_list = [] of Detector
  mutex = Mutex.new

  # Define detectors
  define_detectors([
    Cpp::Drogon,
    Cpp::Crow,
    Clojure::Compojure,
    Clojure::Pedestal,
    Clojure::Reitit,
    Clojure::Ring,
    CSharp::AspNetMvc,
    CSharp::AspNetCoreMvc,
    CSharp::AspNetCoreMinimalApi,
    CSharp::Carter,
    CSharp::FastEndpoints,
    Crystal::Amber,
    Crystal::Grip,
    Crystal::Kemal,
    Crystal::Lucky,
    Crystal::Marten,
    Dart::DartFrog,
    Dart::Serverpod,
    Dart::Shelf,
    Elixir::Bandit,
    Elixir::Phoenix,
    Elixir::Plug,
    Fsharp::Giraffe,
    Perl::Mojolicious,
    Go::Beego,
    Go::Echo,
    Go::Fasthttp,
    Go::Fiber,
    Go::Gin,
    Go::Hertz,
    Go::Iris,
    Go::Chi,
    Go::GoZero,
    Go::Goyave,
    Go::Gf,
    Go::Httprouter,
    Go::Huma,
    Go::Mux,
    Go::Pocketbase,
    Go::ConnectRpc,
    Groovy::Grails,
    Haskell::Scotty,
    Haskell::Servant,
    Haskell::Yesod,
    Specification::AsyncApi,
    Specification::Envoy,
    Specification::Grpc,
    Specification::Har,
    Java::Armeria,
    Java::Dropwizard,
    Java::Javalin,
    Java::JaxRs,
    Java::Jsp,
    Java::Micronaut,
    Java::Quarkus,
    Java::Spark,
    Java::Spring,
    Lua::Lapis,
    Java::Vertx,
    Javascript::Adonisjs,
    Javascript::Apollo,
    Javascript::Astro,
    Javascript::Elysia,
    Javascript::Express,
    Javascript::Fastify,
    Javascript::Fresh,
    Javascript::GraphqlYoga,
    Javascript::Hapi,
    Javascript::Hono,
    Javascript::Koa,
    Javascript::Nestjs,
    Javascript::Nextjs,
    Javascript::Nitro,
    Javascript::Nuxtjs,
    Javascript::Remix,
    Javascript::Restify,
    Javascript::Sveltekit,
    Kotlin::Http4k,
    Kotlin::Spring,
    Kotlin::Ktor,
    Specification::Bruno,
    Specification::Burp,
    Specification::Caddy,
    Specification::Caido,
    Specification::GraphqlSdl,
    Specification::ApacheHttpd,
    Specification::Apisix,
    Specification::AwsCdk,
    Specification::AwsCloudformation,
    Specification::AzureFunctions,
    Specification::CloudflareWrangler,
    Specification::K8sGatewayApi,
    Specification::K8sIngress,
    Specification::Kong,
    Specification::Oas2,
    Specification::Oas3,
    Specification::Insomnia,
    Specification::IstioVirtualservice,
    Specification::Mitmproxy,
    Specification::Netlify,
    Specification::Nginx,
    Specification::OData,
    Specification::Postman,
    Specification::RAML,
    Specification::ServerlessFramework,
    Specification::Smithy,
    Specification::Traefik,
    Specification::TypeSpec,
    Specification::Vercel,
    Specification::WSDL,
    Specification::ZapSitesTree,
    Php::Php,
    Php::CakePHP,
    Php::CodeIgniter,
    Php::Hyperf,
    Php::Laravel,
    Php::Lumen,
    Php::Slim,
    Php::Symfony,
    Php::ThinkPHP,
    Php::Yii,
    Python::Aiohttp,
    Python::Django,
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
    Ruby::Grape,
    Ruby::Hanami,
    Ruby::Rails,
    Ruby::Roda,
    Ruby::Sinatra,
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
    Scala::Akka,
    Scala::Scalatra,
    Scala::Play,
    Scala::Http4s,
    Scala::ZioHttp,
    Scala::Tapir,
    Java::Play,
    Swift::Vapor,
    Swift::Kitura,
    Swift::Hummingbird,
    Typescript::Nestjs,
    Typescript::TanstackRouter,
    Typescript::TRPC,
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

  channel = Channel(Tuple(String, String, Array(Int32))).new(Analyzer::DEFAULT_CONTENT_CHANNEL_CAPACITY)
  locator = CodeLocator.instance
  wg = WaitGroup.new

  # Clear file_map before starting
  locator.clear("file_map")

  # Thread for reading files and sending their contents to the channel
  wg.add(1)
  spawn do
    begin
      skipped_files = 0
      skipped_content_reads = 0
      total_files = 0
      skipped_ignored_dirs = 0

      # Directory names that are pruned at the walker level: once the
      # walker meets a subdirectory with one of these names, that whole
      # subtree is skipped without being enumerated.
      #
      # Critical invariant for issue #912: the base path itself is never
      # matched against this set — we *start* the walk at the base, so a
      # user pointing `-b` at e.g. `/projects/node_modules/my-app` will
      # still have their project scanned. Only descendants of the base
      # are subject to pruning.
      ignored_dir_names = Set{
        # Source control / IDE / agent state
        ".git", ".idea", ".vscode", ".claude",
        # Language-specific dependency / build caches
        "node_modules", "vendor", "__pycache__", ".venv", "venv",
        ".pytest_cache", ".tox", ".gradle", ".bundle", ".dart_tool",
        ".cargo", ".terraform",
        # Common build / dist / cache outputs
        "dist", "build", "target", "out", "tmp", ".cache",
        ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache",
        ".serverless", ".expo",
        # Test coverage / reports
        "coverage", ".coverage",
        # iOS / macOS noise
        "Pods", "__MACOSX",
      }

      # User-supplied --exclude-path patterns (comma-separated globs).
      # Patterns containing "/" are matched against the relative path;
      # patterns without "/" are matched against the basename.
      # Partition once up front so the per-file loop only walks the two
      # already-classified lists — no substring check per file.
      exclude_path_raw = options["exclude_path"]?.to_s
        .split(",").map(&.strip).reject(&.empty?)
      path_patterns, basename_patterns = exclude_path_raw.partition(&.includes?('/'))
      exclude_path_active = !exclude_path_raw.empty?
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
          begin
            Dir.each_child(dir) do |entry|
              full_path = File.join(dir, entry)
              info = File.info?(full_path, follow_symlinks: false)
              next if info.nil?

              if info.directory?
                # Subtree prune happens here. Entry name (not full path)
                # so the base-as-node_modules case from #912 is safe.
                if ignored_dir_names.includes?(entry)
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
                if basename_patterns.any? { |pat| File.match?(pat, entry) }
                  skipped_exclude_path += 1
                  next
                end
                if !path_patterns.empty?
                  rel_path = full_path.starts_with?(base_prefix) ? full_path[base_prefix.size..] : full_path
                  if path_patterns.any? { |pat| File.match?(pat, rel_path) }
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

              candidate_detector_indices = [] of Int32
              detector_list.each_with_index do |detector, idx|
                candidate_detector_indices << idx if detector.applicable?(full_path)
              end

              if candidate_detector_indices.empty? && active_passive_scans.empty?
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
          end
        end
      ensure
        wg.done
      end
    end
  end

  wg.wait
  logger.debug "Added #{locator.all("file_map").size} files to file_map"
  {techs.uniq, passive_result}
end
