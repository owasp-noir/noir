require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
  class Goyave < Analyzer
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      groups = [] of Hash(String, String)
      channel = Channel(String).new

      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  if File.exists?(path) && File.extname(path) == ".go"
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    last_endpoint = Endpoint.new("", "")

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))
                      lexer = GolangLexer.new

                      # Subrouter and Group
                      if line.includes?(".Subrouter(") || line.includes?(".Group(")
                        map = lexer.tokenize(line)
                        before = Token.new(:unknown, "", 0)
                        group_name = ""
                        group_path = ""

                        map.each do |token|
                          if token.type == :assign
                            group_name = before.value.to_s.gsub(":", "").gsub(/\s/, "")
                          end

                          if token.type == :string
                            # Subrouter("/path")
                            group_path = token.value.to_s
                            groups.each do |group|
                              group.each do |key, value|
                                if before.value.to_s.includes? key
                                  group_path = value + group_path
                                end
                              end
                            end
                          elsif token.type == :code && token.value.includes?(".Group")
                            # Group()
                            receiver = token.value.split(".Group")[0].strip
                            groups.each do |group|
                              group.each do |key, value|
                                if receiver.includes? key
                                  group_path = value
                                end
                              end
                            end
                          end

                          before = token
                        end

                        if group_name.size > 0 && group_path.size > 0
                          groups << {
                            group_name => group_path,
                          }
                        end
                      end

                      # HTTP Methods
                      if match = line.match(/\.(Get|Post|Put|Delete|Patch|Options|Route)\s*\(/i)
                        method = match[1].upcase
                        if method == "ROUTE"
                          method = "ANY"
                        end

                        get_route_path(line, groups).tap do |route_path|
                          if route_path.size == 0 && index + 1 < lines.size
                            next_line = lines[index + 1]
                            route_path = get_route_path(next_line, groups)
                          end

                          if route_path.size > 0
                            clean_path = route_path.gsub(/\{([a-zA-Z0-9_]+):[^}]+\}/, "{\\1}")

                            new_endpoint = Endpoint.new("#{clean_path}", method, details)
                            result << new_endpoint
                            last_endpoint = new_endpoint

                            route_path.scan(/\{([a-zA-Z0-9_]+)(?::([^}]+))?\}/) do |match_data|
                              param_name = match_data[1]
                              param_pattern = match_data[2]?
                              last_endpoint.params << Param.new(param_name, param_pattern || "", "path")
                            end
                          end
                        end
                      end

                      # Static
                      if line.includes?(".Static(")
                        get_static_path(line).tap do |static_path|
                          if static_path["static_path"].size > 0
                            public_dirs << static_path
                          end
                        end
                      end
                    end
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      public_dirs.each do |p_dir|
        if p_dir["file_path"].size > 0
          full_path = (base_path + "/" + p_dir["file_path"]).gsub_repeatedly("//", "/")
          Dir.glob("#{escape_glob_path(full_path)}/**/*") do |path|
            next if File.directory?(path)
            if File.exists?(path)
              if p_dir["static_path"].ends_with?("/")
                p_dir["static_path"] = p_dir["static_path"][0..-2]
              end

              details = Details.new(PathInfo.new(path))
              result << Endpoint.new("#{p_dir["static_path"]}#{path.gsub(full_path, "")}", "GET", details)
            end
          end
        end
      end

      result
    end

    def get_static_path(line : String) : Hash(String, String)
      lexer = GolangLexer.new
      map = lexer.tokenize(line)

      static_path = ""

      map.each do |token|
        if token.type == :string
          val = token.value.to_s
          if val.starts_with?("/")
            static_path = val
          end
        end
      end

      if static_path != ""
        file_path = static_path
        if file_path.starts_with?("/")
          file_path = file_path[1..-1]
        end

        return {
          "static_path" => static_path,
          "file_path"   => file_path,
        }
      end

      {
        "static_path" => "",
        "file_path"   => "",
      }
    end

    def get_route_path(line : String, groups : Array(Hash(String, String))) : String
      lexer = GolangLexer.new
      map = lexer.tokenize(line)
      before = Token.new(:unknown, "", 0)
      map.each do |token|
        if token.type == :string
          final_path = token.value.to_s

          if final_path.starts_with?("/") || final_path == ""
            groups.each do |group|
              group.each do |key, value|
                if before.value.to_s.includes? key
                  final_path = value + final_path
                end
              end
            end
            return final_path
          end
        end

        before = token
      end

      ""
    end
  end
end
