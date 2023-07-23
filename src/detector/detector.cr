require "./detectors/*"

macro define_detectors(detectors)
  {% for detector, index in detectors %}
    if detect_{{detector}}(file, content)
      techs << "{{detector}}"
    end
  {% end %}
end

def detect_techs(base_path : String)
  techs = [] of String
  Dir.glob("#{base_path}/**/*") do |file|
    spawn do
      next if File.directory?(file)
      content = File.read(file)

      define_detectors([
        ruby_rails, ruby_sinatra, go_echo, java_spring,
        python_django, python_flask, php_pure, java_jsp, js_express,
      ])
    end
    Fiber.yield
  end

  techs.uniq
end
