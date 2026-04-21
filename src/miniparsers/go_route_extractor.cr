require "../minilexers/golang"

module Noir
  # Pure parsing helpers for Go route-like source lines.
  #
  # No file I/O and no dependency on the Analyzer base — the engine
  # (`Analyzer::Go::GoEngine`) wraps these for analyzer instances.
  # Per-framework analyzers may still override their own `get_route_path`
  # / `get_static_path` to customize extraction; this module is the
  # default implementation they delegate to.
  module GoRouteExtractor
    extend self

    # Scan one line for a `.Group(...)` definition and append the
    # resolved `{name => path}` entry to `groups` if found.
    def scan_group(line : String, lexer : GolangLexer, groups : Array(Hash(String, String))) : Nil
      return unless line.includes?(".Group(")

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
        # Skip if a group with this name is already registered
        unless groups.any?(&.has_key?(group_name))
          groups << {
            group_name => group_path,
          }
        end
      end
    end

    # Parse one line, return the route path with group prefix applied.
    # Returns "" if no route string is found.
    def extract_route_path(line : String, groups : Array(Hash(String, String))) : String
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

    # Parse one line for a `Static(route, dir)`-style call and return
    # `{"static_path" => …, "file_path" => …}`. Both entries are ""
    # when the line does not match.
    def extract_static_path(line : String) : Hash(String, String)
      first = line.strip.split("(")
      if first.size > 1
        second = first[1].split(",")
        if second.size > 1
          static_path = second[0].gsub("\"", "")
          file_path = second[1].gsub("\"", "").gsub(" ", "").gsub(")", "").gsub_repeatedly("//", "/")
          return {
            "static_path" => static_path,
            "file_path"   => file_path,
          }
        end
      end

      {
        "static_path" => "",
        "file_path"   => "",
      }
    end
  end
end
