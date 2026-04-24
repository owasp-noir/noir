require "../../models/analyzer"
require "../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class GoEngine < Analyzer
    # --- Tree-sitter group/route pre-pass --------------------------------
    #
    # Does a cross-file fixpoint over every `.go` file in each package
    # directory, extracting group declarations (`x := r.Group("/x")` and
    # friends). Returns:
    #   * `package_groups` — per-directory `{group_name => resolved_prefix}`
    #   * `file_contents` — cached source strings keyed by path, so the
    #     per-file second pass doesn't read files twice
    #
    # `group_method` is the method name used for grouping — `"Group"` for
    # Gin/Echo/Fiber/Hertz (default), `"Party"` for Iris, `"Subrouter"`
    # for Mux.
    #
    # The fixpoint handles the `routes.go` calling `v1.GET(...)` under a
    # `v1 := r.Group("/v1")` declared in `main.go` case — iterate until
    # no new entries land. In-file declarations win over external ones.
    def collect_package_groups_ts(group_method : String = "Group") : Tuple(Hash(String, Hash(String, String)), Hash(String, String))
      package_groups = Hash(String, Hash(String, String)).new
      files_by_dir = Hash(String, Array(String)).new
      file_contents = Hash(String, String).new

      get_files_by_extension(".go").each do |path|
        next if File.directory?(path)
        dir = File.dirname(path)
        files_by_dir[dir] ||= [] of String
        files_by_dir[dir] << path
      end

      files_by_dir.each do |_dir, paths|
        paths.each do |path|
          begin
            file_contents[path] = File.read(path, encoding: "utf-8", invalid: :skip)
          rescue File::NotFoundError
            # skip
          end
        end
      end

      files_by_dir.each do |dir, paths|
        groups = Hash(String, String).new
        loop do
          prev_size = groups.size
          paths.each do |path|
            content = file_contents[path]?
            next if content.nil?
            found = Noir::TreeSitterGoRouteExtractor.extract_groups(content, groups, group_method)
            found.each { |k, v| groups[k] ||= v }
          end
          break if groups.size == prev_size
        end
        package_groups[dir] = groups unless groups.empty?
      end

      {package_groups, file_contents}
    end

    # Returns the cross-file group map for the given directory, or an
    # empty map when the directory has no registered groups.
    def ts_groups_for_directory(package_groups : Hash(String, Hash(String, String)), dir : String) : Hash(String, String)
      package_groups[dir]? || Hash(String, String).new
    end

    # --- Adapter helpers (shared across Go framework adapters) ----------

    def add_param_to_endpoint(param : Param, endpoint : Endpoint)
      if param.name.size > 0 && endpoint.method != "" && endpoint.url != ""
        endpoint.params << param
      end
    end

    def add_static_path_if_valid(static_path : Hash(String, String), public_dirs : Array(Hash(String, String)))
      if static_path["static_path"].size > 0 && static_path["file_path"].size > 0
        public_dirs << static_path
      end
    end

    def resolve_public_dirs_with_glob(public_dirs : Array(Hash(String, String)))
      public_dirs.each do |p_dir|
        next if p_dir["file_path"].size == 0
        raw_full_path = (base_path + "/" + p_dir["file_path"]).gsub_repeatedly("//", "/")
        normalized_full_path = Path[raw_full_path].normalize.to_s

        if base_path.starts_with?("./") && !normalized_full_path.starts_with?("./") && !normalized_full_path.starts_with?("/")
          full_path = "./#{normalized_full_path}"
        else
          full_path = normalized_full_path
        end

        next unless File.directory?(full_path)
        Dir.glob("#{escape_glob_path(full_path)}/**/*") do |path|
          next if File.directory?(path)
          if File.exists?(path)
            static_url = p_dir["static_path"]
            if static_url.ends_with?("/")
              static_url = static_url[0..-2]
            end

            details = Details.new(PathInfo.new(path))
            result << Endpoint.new("#{static_url}#{path.gsub(full_path, "")}", "GET", details)
          end
        end
      end
    end

    def resolve_public_dirs(public_dirs : Array(Hash(String, String)))
      public_dirs.each do |p_dir|
        # Join path manually first to handle concatenation
        raw_full_path = (base_path + "/" + p_dir["file_path"]).gsub_repeatedly("//", "/")

        # Normalize the path to resolve . and ..
        normalized_full_path = Path[raw_full_path].normalize.to_s

        # Re-add ./ prefix if it was present in base_path and lost during normalization
        # This ensures compatibility with CodeLocator which stores relative paths if base_path was relative
        if base_path.starts_with?("./") && !normalized_full_path.starts_with?("./") && !normalized_full_path.starts_with?("/")
          full_path = "./#{normalized_full_path}"
        else
          full_path = normalized_full_path
        end

        get_files_by_prefix(full_path).each do |path|
          # Ensure strict prefix match (directory boundary or exact match)
          # get_files_by_prefix matches any file starting with prefix, so "public" matches "public2"
          # We prevent this by ensuring the next character is a separator or it's an exact match
          next unless path == full_path || path.starts_with?(full_path.ends_with?("/") ? full_path : "#{full_path}/")

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
  end
end
