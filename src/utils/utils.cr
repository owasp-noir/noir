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
                      # Remove the base path prefix, anchored to the START only.
                      # `String#sub` replaces the first match anywhere, so an
                      # unanchored double-sub corrupted paths where base_path
                      # recurred inside a dir/file name.
                      base = base_path.ends_with?("/") ? base_path : "#{base_path}/"
                      if path.starts_with?(base)
                        path[base.size..]
                      elsif path.starts_with?(base_path)
                        path[base_path.size..]
                      else
                        path
                      end
                    end

  # Then, normalize the resulting path.
  relative_path = unstripped_path
    .sub(/^\.\//, "") # Remove leading "./" only at the start
    .sub("//", "/")

  remove_start_slash(relative_path)
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

# Matches `regex` against `input`, treating a backtracking blow-up as "no
# match" rather than an exception.
#
# The bound is PCRE2's own match limit, which is the only mechanism that can
# actually interrupt a running match. When a pattern backtracks past it,
# `Regex#matches?` raises `Regex::Error`; that is the ReDoS ceiling, and it
# applies whether or not anything here wraps the call.
#
# This used to spawn a fiber and race it against `select ... when timeout`.
# That could not work: `Regex#matches?` is a single `pcre2_match` FFI call
# with no yield point, and noir has no `preview_mt` build, so the timeout
# branch could never be reached while the match was running. Measured
# directly — with `timeout` set to 10ms, the wrapper returned after 17ms,
# having run the match to completion. It bounded nothing, and cost a fiber
# spawn plus a channel per line scanned on the one hot path that used it.
def regex_matches_bounded?(regex : Regex, input : String) : Bool
  regex.matches?(input)
rescue Regex::Error
  # Match limit exhausted (or another PCRE2 runtime error). The line is not
  # a hit, and one pathological line must not end the scan.
  false
end
