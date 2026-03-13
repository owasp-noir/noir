require "../../../models/analyzer"
require "../../../utils/url_path"

module Analyzer::Crystal
  class Kemal < Analyzer
    NAMESPACE_PATTERN = /^(\s*)(?:(\w+)\.)?namespace\s+["'](.+?)["']/
    MOUNT_PATTERN     = /^\s*mount\s+["'](.+?)["']\s*,\s*(\w+)/
    ROUTER_PATTERN    = /^\s*(\w+)\s*=\s*Kemal::Router\.new/

    def analyze
      # Variables
      is_public = true
      public_folders = [] of String
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

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
                    analyze_file(path).each do |endpoint|
                      result << endpoint
                    end

                    # Extract public folder and serve_static info
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      file.each_line do |line|
                        if line.includes?("serve_static false") || line.includes?("serve_static(false)")
                          is_public = false
                        end

                        if line.includes?("public_folder")
                          begin
                            split = line.split("public_folder")

                            if split.size > 1
                              match_data = split[1].match(/[=\(]\s*['"]?(.*?)['"]?\s*[\),]/)
                              public_folder = if match_data && match_data[1]?
                                                match_data[1].strip
                                              else
                                                split[1].gsub("(", "").gsub(")", "").gsub(" ", "").gsub("\"", "").gsub("'", "")
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

      # Public Dir Analysis
      if is_public
        begin
          get_public_files(@base_path).each do |file|
            if file =~ /\/public\/(.*)/
              relative_path = $1
              @result << Endpoint.new("/#{relative_path}", "GET")
            end
          end

          public_folders.each do |folder|
            get_public_dir_files(@base_path, folder).each do |file|
              if folder.includes?("/")
                folder_path = folder.ends_with?("/") ? folder : "#{folder}/"
                if file.starts_with?(folder_path)
                  relative_path = file.sub(folder_path, "")
                  @result << Endpoint.new("/#{relative_path}", "GET")
                else
                  folder_name = folder.split("/").last
                  if file =~ /\/#{folder_name}\/(.*)/
                    relative_path = $1
                    @result << Endpoint.new("/#{relative_path}", "GET")
                  end
                end
              else
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

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = File.read_lines(path)

      # Pre-scan: build mount_map (variable_name => mount_path)
      mount_map = {} of String => String
      router_vars = Set(String).new

      lines.each do |line|
        if match = line.match(ROUTER_PATTERN)
          router_vars << match[1]
        end
        if match = line.match(MOUNT_PATTERN)
          mount_map[match[2]] = match[1]
        end
      end

      # Main scan with namespace stack
      namespace_stack = [] of NamedTuple(prefix: String, indent: Int32, router_var: String)
      last_endpoint : Endpoint? = nil

      lines.each_with_index do |line, index|
        # Check for namespace open
        if match = line.match(NAMESPACE_PATTERN)
          indent = match[1].size
          router_var = match[2]? || ""
          prefix = match[3]
          namespace_stack << {prefix: prefix, indent: indent, router_var: router_var}
          next
        end

        # Check for end that closes a namespace
        if !namespace_stack.empty?
          if end_match = line.match(/^(\s*)end\b/)
            end_indent = end_match[1].size
            if end_indent == namespace_stack.last[:indent]
              namespace_stack.pop
              next
            end
          end
        end

        # Parse endpoint
        endpoint = line_to_endpoint(line)
        if endpoint.method != ""
          # Build full path with namespace prefixes and mount path
          route_path = endpoint.url
          full_path = route_path

          if !namespace_stack.empty?
            # Combine all namespace prefixes
            ns_prefix = ""
            namespace_stack.each do |ns|
              ns_prefix = Noir::URLPath.join(ns_prefix, ns[:prefix])
            end
            full_path = Noir::URLPath.join(ns_prefix, route_path)

            # Determine router variable for mount lookup
            router_var = namespace_stack.first[:router_var]
            if !router_var.empty? && mount_map.has_key?(router_var)
              full_path = Noir::URLPath.join(mount_map[router_var], full_path)
            end
          end

          endpoint.url = full_path
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          endpoints << endpoint
          last_endpoint = endpoint
        end

        # Parse params
        param = line_to_param(line)
        if param.name != ""
          if le = last_endpoint
            if le.method != ""
              le.push_param(param)
            end
          end
        end
      end

      endpoints
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
