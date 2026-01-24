def remove_start_slash(input_path : String) : String
  input_path.lstrip('/')
end

def get_relative_path(base_path : String, path : String) : String
  # Handle special case where base_path is "." (current directory)
  # Without this, .sub(".", "") would remove the first "." found anywhere in the path
  # (e.g., removing the "." from ".php" extension)
  if base_path == "."
    return path
      .sub(/^\.\//, "") # Remove leading "./" only at the start
      .sub("//", "/")
      .lstrip('/')
  end

  # Ensure base_path ends with slash for consistent substitution
  base = base_path.ends_with?("/") ? base_path : "#{base_path}/"

  # Remove base path and normalize
  relative_path = path
    .sub(base, "")
    .sub(base_path, "")  # Fallback if base doesn't end with /
    .sub(/^\.\//, "")    # Remove leading "./" only at the start
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
