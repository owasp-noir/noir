require "./absolute/rails.cr"

def detect_tech(base_path : String)
  techs = [] of String
  techs = techs + detect_absolute(base_path)
  techs = techs + detect_ralative(base_path)

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
    next if File.directory?(file)

    content = File.read
    if detect_rails(file, content)
      techs << "rails"
    end
  end

  techs
end
