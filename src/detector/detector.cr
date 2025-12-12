require "./detectors/**"
require "../models/detector"
require "../models/passive_scan"
require "../techs/techs.cr" # Added to define NoirTechs
require "../passive_scan/detect.cr"
require "../utils/wait_group"
require "../utils/media_filter"
require "yaml"

macro defind_detectors(detectors)
  {% for detector, index in detectors %}
    instance = Detector::{{detector}}.new(options)
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
  defind_detectors([
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
    Go::Chi,
    Go::GoZero,
    Go::Mux,
    Specification::Har,
    Java::Armeria,
    Java::Jsp,
    Java::Spring,
    Java::Vertx,
    Javascript::Express,
    Javascript::Fastify,
    Javascript::Koa,
    Javascript::Nestjs,
    Javascript::Restify,
    Kotlin::Spring,
    Kotlin::Ktor,
    Specification::Oas2,
    Specification::Oas3,
    Specification::Postman,
    Specification::RAML,
    Specification::ZapSitesTree,
    Php::Php,
    Php::Laravel,
    Php::Symfony,
    Python::Django,
    Python::FastAPI,
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
  ])

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

  channel = Channel(Tuple(String, String)).new
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

      # Common heavy/irrelevant directories to skip early
      ignored_dir_patterns = [
        "/node_modules/", "/.git/", "/dist/", "/build/", "/target/", 
        "/__pycache__/", "/.venv/", "/venv/", "/.idea/", "/.vscode/", 
        "/tmp/", "/.next/", "/out/", "/vendor/"
      ]

      base_paths.each do |base_path|
        Dir.glob("#{base_path}/**/**") do |file|
          next if File.directory?(file)
          total_files += 1

          # Skip files in ignored directories early
          if ignored_dir_patterns.any? { |pat| file.includes?(pat) }
            skipped_ignored_dirs += 1
            next
          end

          # Check if file should be skipped due to media type or size
          if MediaFilter.should_skip_file?(file)
            reason = MediaFilter.skip_reason(file)
            logger.debug "Skipping #{file}: #{reason}"
            skipped_files += 1
            next
          end

          content = File.read(file, encoding: "utf-8", invalid: :skip)
          channel.send({file, content})
          locator.push "file_map", file
        end
      end

      if skipped_files > 0
        logger.info "Skipped #{skipped_files} media/large files out of #{total_files} total files"
      end
      if skipped_ignored_dirs > 0
        logger.debug "Skipped #{skipped_ignored_dirs} files in ignored directories"
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
                mutex.synchronize do
                  techs << detector.name
                end
                logger.debug_sub "└── Detected: #{detector.name}"
                logger.verbose_sub "└── Detected: #{detector.name} in #{file}"
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
          rescue e : File::NotFoundError
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
