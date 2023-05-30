def analyzer_example(options : Hash(Symbol, String))
  result = [] of Endpoint
  base_path = options[:base]
  url = options[:url]

  # Source Analysis
  Dir.glob("#{base_path}/**/*") do |path|
    next if File.directory?(path)
    if File.exists?(path)
      File.open(path, "r") do |file|
        file.each_line do |_|
        end
      end
    end
  end

  result
end
