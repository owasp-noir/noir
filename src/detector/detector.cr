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
    DetectorCrystalKemal, DetectorGoEcho, DetectorJavaJsp, DetectorJavaSpring,
    DetectorJsExpress, DetectorPhpPure, DetectorPythonDjango, DetectorPythonFlask,
    DetectorRubyRails, DetectorRubySinatra, DetectorOas2, DetectorOas3, DetectorRAML,
    DetectorGoGin, DetectorKotlinSpring, DetectorJavaArmeria, DetectorCSharpAspNetMvc,
  ])
  Dir.glob("#{base_path}/**/*") do |file|
    spawn do
      begin
        next if File.directory?(file)
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
    Fiber.yield
  end

  techs.uniq
end
