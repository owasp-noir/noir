def detect(base_path : String)
  Dir.glob("#{base_path}/**/*") do |file|
    next if File.directory?(file)

    File.open(file, "r") do |f|
      f.each_line do |_|
        # TODO
      end
    end
  end
end
