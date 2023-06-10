require "./detectors/*"

def detect_techs(base_path : String)
  techs = [] of String
  Dir.glob("#{base_path}/**/*") do |file|
    spawn do
      next if File.directory?(file)

      content = File.read(file)
      if detect_ruby_rails(file, content)
        techs << "ruby_rails"
      end
      if detect_ruby_sinatra(file, content)
        techs << "ruby_sinatra"
      end
      if detect_go_echo(file, content)
        techs << "go_echo"
      end
      if detect_java_spring(file, content)
        techs << "java_spring"
      end
      if detect_python_django(file, content)
        techs << "python_django"
      end
      if detect_python_flask(file, content)
        techs << "python_flask"
      end
      if detect_php_pure(file, content)
        techs << "php_pure"
      end
      if detect_java_jsp(file, content)
        techs << "java_jsp"
      end
      if detect_js_express(file, content)
        techs << "js_express"
      end
    end
    Fiber.yield
  end

  techs.uniq
end
