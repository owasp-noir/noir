def remove_start_slash(input_path : String) : String
  input_path.lstrip('/')
end

def get_relative_path(base_path : String, path : String) : String
  # First, determine the path relative to the base_path, without other normalization.
  unstripped_path = if base_path == "."
                      # When base_path is ".", the path is already relative.
                      # This avoids an issue where `.sub(".", "")` would remove the dot from file extensions.
                      path
                    else
                      # For other base paths, remove the base path prefix.
                      base = base_path.ends_with?("/") ? base_path : "#{base_path}/"
                      path
                        .sub(base, "")
                        .sub(base_path, "") # Fallback if base doesn't end with /
                    end

  # Then, normalize the resulting path.
  relative_path = unstripped_path
    .sub(/^\.\//, "") # Remove leading "./" only at the start
    .sub("//", "/")

  remove_start_slash(relative_path)
end

def join_path(*segments : String) : String
  path = segments
    .reject(&.empty?)
    .map(&.chomp("/").lstrip("/"))
    .join("/")

  path.starts_with?("/") ? path : "/#{path}"
end

def any_to_bool(any) : Bool
  case any.to_s.downcase
  when "false", "no"
    false
  when "true", "yes"
    true
  else
    false
  end
end

# Escapes glob metacharacters in a path string.
# This is necessary when the path contains characters like { } [ ] * ? \
# which would otherwise be interpreted as glob patterns.
# Example: "/path/{{cookiecutter}}/file" -> "/path/\\{\\{cookiecutter\\}\\}/file"
def escape_glob_path(path : String) : String
  path.gsub(/([{}\[\]*?\\])/) { |match| "\\#{match}" }
end

# Safely checks if a regex matches a string within a given timeout.
# This helps mitigate ReDoS (Regular Expression Denial of Service) attacks.
def regex_matches_with_timeout?(regex : Regex, input : String, timeout : Time::Span = 500.milliseconds) : Bool
  result_channel = Channel(Bool).new

  spawn do
    result_channel.send(regex.matches?(input))
  rescue
    result_channel.send(false)
  end

  select
  when matched = result_channel.receive
    matched
  when timeout(timeout)
    false
  end
end
