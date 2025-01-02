require "./detectors/**"
require "../models/detector"
require "../models/passive_scan"
require "../passive_scan/detect.cr"
require "yaml"

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
    Php::Php,
    Python::Django,
    Python::FastAPI,
    Python::Flask,
    Specification::RAML,
    Ruby::Hanami,
    Ruby::Rails,
    Ruby::Sinatra,
    Rust::Axum,
    Rust::Rocket,
    Rust::ActixWeb,
  ])

  if options["techs"].to_s.size > 0
    techs << options["techs"].to_s
  end

  channel = Channel(String).new
  spawn do
    Dir.glob("#{base_path}/**/*") do |file|
      channel.send(file)
    end
  end

  options["concurrency"].to_s.to_i.times do
    spawn do
      loop do
        begin
          file = channel.receive
          next if File.directory?(file)
          logger.debug "Detecting: #{file}"
          content = File.read(file, encoding: "utf-8", invalid: :skip)

          detector_list.each do |detector|
            if detector.detect(file, content)
              techs << detector.name
            end
          end

          results = NoirPassiveScan.detect(file, content, passive_scans, logger)
          mutex.synchronize do
            passive_result.concat(results)
          end
        rescue e : File::NotFoundError
          logger.debug "File not found: #{file}"
        end
      end
    end
  end

  Fiber.yield
  {techs.uniq, passive_result}
end
