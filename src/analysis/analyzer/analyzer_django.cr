def analyzer_django(options : Hash(Symbol, String))
  result = [] of Endpoint
  base_path = options[:base]
  url = options[:url]
  _ = url

  # Source Analysis
  Dir.glob("#{base_path}/**/*") do |path|
    spawn do
      next if File.directory?(path)
      if File.exists?(path) && File.extname(path) == ".py"
        File.open(path, "r") do |file|
          file.each_line do |line|
            # TODO
          end
        end
      end
    end
  end
  Fiber.yield

  result
end
