require "./detectors/*"
require "../models/detector"

macro defind_detectors(detectors)
  {% for detector, index in detectors %}
    instance = {{detector}}.new(options)
    instance.set_name
    detector_list << instance
  {% end %}
end

def detect_techs(base_path : String, options : Hash(Symbol, String), logger : NoirLogger)
  techs = [] of String
  detector_list = [] of Detector
  defind_detectors([
    DetectorCrystalKemal, DetectorCrystalLucky, DetectorGoEcho, DetectorJavaJsp, DetectorJavaSpring, DetectorJsExpress,
    DetectorPhpPure, DetectorPythonDjango, DetectorPythonFlask, DetectorPythonFastAPI,
    DetectorRubyRails, DetectorRubySinatra, DetectorRubyHanami, DetectorOas2, DetectorOas3, DetectorRAML,
    DetectorGoGin, DetectorKotlinSpring, DetectorJavaArmeria, DetectorCSharpAspNetMvc,
    DetectorRustAxum, DetectorElixirPhoenix, DetectorGoFiber,
  ])

  channel = Channel(String).new
  spawn do
    Dir.glob("#{base_path}/**/*") do |file|
      channel.send(file)
    end
  end

  options[:concurrency].to_i.times do
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
        rescue e : File::NotFoundError
          logger.debug "File not found: #{file}"
        end
      end
    end
  end

  Fiber.yield
  techs.uniq
end
