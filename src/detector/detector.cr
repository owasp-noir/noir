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

def detect_techs(base_paths : Array(String), options : Hash(String, YAML::Any), passive_scans : Array(PassiveScan), logger : NoirLogger)
  techs = [] of String
  passive_result = [] of PassiveScanResult
  detector_list = [] of Detector
  mutex = Mutex.new

  # Define detectors
  define_detectors([
    CSharp::AspNetMvc,
    CSharp::AspNetCoreMvc,
    Crystal::Amber,
    Crystal::Grip,
    Crystal::Kemal,
    Crystal::Lucky,
    Crystal::Marten,
    Elixir::Phoenix,
    Elixir::Plug,
    Go::Beego,
    Go::Echo,
    Go::Fasthttp,
    Go::Fiber,
    Go::Gin,
    Go::Hertz,
    Go::Chi,
    Go::GoZero,
    Go::Goyave,
    Go::Gf,
    Go::Httprouter,
    Go::Mux,
    Specification::Grpc,
    Specification::Har,
    Java::Armeria,
    Java::Jsp,
    Java::Spring,
    Java::Vertx,
    Javascript::Express,
    Javascript::Fastify,
    Javascript::Hono,
    Javascript::Koa,
    Javascript::Nestjs,
    Javascript::Nextjs,
    Javascript::Nitro,
    Javascript::Nuxtjs,
    Javascript::Restify,
    Kotlin::Spring,
    Kotlin::Ktor,
    Specification::Oas2,
    Specification::Oas3,
    Specification::Postman,
    Specification::RAML,
    Specification::ZapSitesTree,
    Php::Php,
    Php::CakePHP,
    Php::Laravel,
    Php::Symfony,
    Php::Yii,
    Python::Aiohttp,
    Python::Django,
    Python::FastAPI,
    Python::Bottle,
    Python::Flask,
    Python::Sanic,
    Python::Tornado,
    Ruby::Hanami,
    Ruby::Rails,
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
    Java::Play,
    Swift::Vapor,
    Swift::Kitura,
    Swift::Hummingbird,
    Typescript::Nestjs,
    Typescript::TanstackRouter,
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

  channel = Channel(Tuple(String, String)).new(Analyzer::DEFAULT_CONTENT_CHANNEL_CAPACITY)
  locator = CodeLocator.instance
  wg = WaitGroup.new

  # Clear file_map before starting
  locator.clear("file_map")

  # Thread for reading files and sending their contents to the channel
  wg.add(1)
  spawn do
    begin
      skipped_files = 0
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
        "node_modules", ".git", "dist", "build", "target",
        "__pycache__", ".venv", "venv", ".idea", ".vscode",
        "tmp", ".next", "out", "vendor",
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

              if skip_reason = MediaFilter.skip_check(full_path, info: info)
                logger.debug "Skipping #{full_path}: #{skip_reason}"
                skipped_files += 1
                next
              end

              content = File.read(full_path, encoding: "utf-8", invalid: :skip)
              channel.send({full_path, content})
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

  # Log how many files were added to the file_map
  logger.debug "Added #{locator.all("file_map").size} files to file_map"

  # Threads for receiving and processing the contents from the channel
  concurrency = options["concurrency"].to_s.to_i

  concurrency.times do
    wg.add(1)
    spawn do
      begin
        loop do
          begin
            file_content = channel.receive?
            break if file_content.nil?
            file, content = file_content
            logger.debug "Detecting: #{file}"

            detector_list.each do |detector|
              if detector.detect(file, content)
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

            # Get the minimum severity threshold from options
            min_severity = options["passive_scan_severity"]?.try(&.to_s) || "high"
            results = NoirPassiveScan.detect_with_severity(file, content, passive_scans, logger, min_severity)
            if results.size > 0
              mutex.synchronize do
                passive_result.concat(results)
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
  {techs.uniq, passive_result}
end
