require "./absolute/*"
require "./relative/*"

def detect_tech(base_path : String)
  techs = [] of String
  techs = techs + detect_absolute(base_path)
  techs = techs + detect_relative(base_path)

  techs.uniq
end

def detect_absolute(base_path : String)
  techs = [] of String
  if detect_absolute_rails(base_path)
    techs << "rails"
  end

  techs
end

def detect_relative(base_path : String)
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
    end
    Fiber.yield
  end

  techs
end
