require "./detectors/**"
require "../models/detector"
require "../models/passive_scan"
require "../passive_scan/detect.cr"
require "yaml"
require "wait_group"

macro defind_detectors(detectors)
  {% for detector, index in detectors %}
    instance = Detector::{{detector}}.new(options)
    instance.set_name
    detector_list << instance
  {% end %}
end

def detect_techs(base_path : String, options : Hash(String, YAML::Any), passive_scans : Array(PassiveScan), logger : NoirLogger)
  techs = [] of String
  passive_result = [] of PassiveScanResult
  detector_list = [] of Detector
  mutex = Mutex.new

  # Define detectors
  defind_detectors([
    CSharp::AspNetMvc,
    Crystal::Kemal,
    Crystal::Lucky,
    Elixir::Phoenix,
    Go::Beego,
    Go::Echo,
    Go::Fiber,
    Go::Gin,
    Specification::Har,
    Java::Armeria,
    Java::Jsp,
    Java::Spring,
    Javascript::Express,
    Javascript::Restify,
    Kotlin::Spring,
    Specification::Oas2,
    Specification::Oas3,
    Specification::RAML,
    Specification::ZapSitesTree,
    Php::Php,
    Python::Django,
    Python::FastAPI,
    Python::Flask,
    Ruby::Hanami,
    Ruby::Rails,
    Ruby::Sinatra,
    Rust::Axum,
    Rust::Rocket,
    Rust::ActixWeb,
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

  # Thread for reading files and sending their contents to the channel
  wg.add(1)
  spawn do
    begin
      Dir.glob("#{base_path}/**/*") do |file|
        next if File.directory?(file)
        content = File.read(file, encoding: "utf-8", invalid: :skip)
        channel.send({file, content})
        locator.push "file_map", file
      end
    ensure
      channel.close
      wg.done
    end
  end

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
              end
            end

            results = NoirPassiveScan.detect(file, content, passive_scans, logger)
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
