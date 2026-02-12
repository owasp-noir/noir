require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
  class Common < Analyzer
    def analyze_group(line : String, lexer : GolangLexer, groups : Array(Hash(String, String)))
      if line.includes?(".Group(")
        map = lexer.tokenize(line)
        before = Token.new(:unknown, "", 0)
        group_name = ""
        group_path = ""
        map.each do |token|
          if token.type == :assign
            group_name = before.value.to_s.gsub(":", "").gsub(/\s/, "")
          end

          if token.type == :string
            group_path = token.value.to_s
            groups.each do |group|
              group.each do |key, value|
                if before.value.to_s.includes? key
                  group_path = value + group_path
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
    end

    def get_route_path(line : String, groups : Array(Hash(String, String))) : String
      lexer = GolangLexer.new
      map = lexer.tokenize(line)
      before = Token.new(:unknown, "", 0)
      map.each do |token|
        if token.type == :string
          final_path = token.value.to_s
          # Route path must start with "/" to be a valid HTTP endpoint
          next unless final_path.starts_with?("/")
          groups.each do |group|
            group.each do |key, value|
              if before.value.to_s.includes? key
                final_path = value + final_path
              end
            end
          end

          return final_path
        end

        before = token
      end

      ""
    end

    def get_static_path(line : String) : Hash(String, String)
      first = line.strip.split("(")
      if first.size > 1
        second = first[1].split(",")
        if second.size > 1
          static_path = second[0].gsub("\"", "")
          file_path = second[1].gsub("\"", "").gsub(" ", "").gsub(")", "").gsub_repeatedly("//", "/")
          rtn = {
            "static_path" => static_path,
            "file_path"   => file_path,
          }

          return rtn
        end
      end

      {
        "static_path" => "",
        "file_path"   => "",
      }
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
