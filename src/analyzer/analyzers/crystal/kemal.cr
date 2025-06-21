require "../../../models/analyzer"

module Analyzer::Crystal
  class Kemal < Analyzer
    def analyze
      # Variables
      is_public = true
      public_folders = [] of String
      channel = Channel(String).new

      # Source Analysis
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
                  if File.exists?(path) && File.extname(path) == ".cr" && !path.includes?("lib")
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      last_endpoint = Endpoint.new("", "")
                      file.each_line.with_index do |line, index|
                        endpoint = line_to_endpoint(line)
                        if endpoint.method != ""
                          details = Details.new(PathInfo.new(path, index + 1))
                          endpoint.details = details
                          result << endpoint
                          last_endpoint = endpoint
                        end

                        param = line_to_param(line)
                        if param.name != ""
                          if last_endpoint.method != ""
                            last_endpoint.push_param(param)
                          end
                        end

                        if line.includes?("serve_static false") || line.includes?("serve_static(false)")
                          is_public = false
                        end

                        if line.includes?("public_folder")
                          begin
                            splited = line.split("public_folder")
                            public_folder = ""

                            if splited.size > 1
                              # Extract path more carefully handling quotes and spaces
                              match_data = splited[1].match(/[=\(]\s*['"]?(.*?)['"]?\s*[\),]/)
                              if match_data && match_data[1]?
                                public_folder = match_data[1].strip
                              else
                                # Fallback to the previous approach
                                public_folder = splited[1].gsub("(", "").gsub(")", "").gsub(" ", "").gsub("\"", "").gsub("'", "")
                              end

                              if public_folder != ""
                                public_folders << public_folder
                              end
                            end
                          rescue
                          end
                        end
                      end
                    end
                  end
                rescue e : File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      # Public Dir Analysis
      if is_public
        begin
          # Process public folder files
          get_public_files(@base_path).each do |file|
            # Extract the path after "/public/" regardless of depth
            if file =~ /\/public\/(.*)/
              relative_path = $1
              @result << Endpoint.new("/#{relative_path}", "GET")
            end
          end

          # Process other public folders
          public_folders.each do |folder|
            get_public_dir_files(@base_path, folder).each do |file|
              # Extract relative path from the custom folder
              if folder.includes?("/")
                # For absolute paths or paths with directories
                folder_path = folder.ends_with?("/") ? folder : "#{folder}/"
                if file.starts_with?(folder_path)
                  relative_path = file.sub(folder_path, "")
                  @result << Endpoint.new("/#{relative_path}", "GET")
                else
                  # Try to find the folder component in the path
                  folder_name = folder.split("/").last
                  if file =~ /\/#{folder_name}\/(.*)/
                    relative_path = $1
                    @result << Endpoint.new("/#{relative_path}", "GET")
                  end
                end
              else
                # For simple folder names (no slashes)
                if file =~ /\/#{folder}\/(.*)/
                  relative_path = $1
                  @result << Endpoint.new("/#{relative_path}", "GET")
                end
              end
            end
          end
        rescue e
          logger.debug e
        end
      end

      result
    end

    def line_to_param(content : String) : Param
      if content.includes? "env.params.query["
        param = content.split("env.params.query[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "query")
      end

      if content.includes? "env.params.json["
        param = content.split("env.params.json[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "json")
      end

      if content.includes? "env.params.body["
        param = content.split("env.params.body[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "form")
      end

      if content.includes? "env.request.headers["
        param = content.split("env.request.headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "header")
      end

      if content.includes? "env.request.cookies["
        param = content.split("env.request.cookies[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "cookie")
      end

      if content.includes? "cookies.get_raw("
        param = content.split("cookies.get_raw(")[1].split(")")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "cookie")
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(content : String) : Endpoint
      content.scan(/get\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "GET")
        end
      end

      content.scan(/post\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "POST")
        end
      end

      content.scan(/put\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "PUT")
        end
      end

      content.scan(/delete\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "DELETE")
        end
      end

      content.scan(/patch\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "PATCH")
        end
      end

      content.scan(/head\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "HEAD")
        end
      end

      content.scan(/options\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new("#{match[1]}", "OPTIONS")
        end
      end

      content.scan(/ws\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          endpoint = Endpoint.new("#{match[1]}", "GET")
          endpoint.protocol = "ws"
          return endpoint
        end
      end

      Endpoint.new("", "")
    end
  end
end
