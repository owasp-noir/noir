module Noir
  module URLPath
    # Join two URL path segments without introducing double slashes.
    #
    # This method is designed for joining route prefixes and paths in web frameworks.
    # It handles the common cases of trailing/leading slashes to produce clean URLs.
    #
    # Behavior:
    # - If parent is empty, returns child as-is
    # - If child is empty, returns parent as-is
    # - If both have slashes at the join point, one is removed
    # - If neither has a slash at the join point, one is added
    #
    # Examples:
    #   URLPath.join("/api", "/users")  # => "/api/users"
    #   URLPath.join("/api/", "/users") # => "/api/users"
    #   URLPath.join("/api", "users")   # => "/api/users"
    #   URLPath.join("", "/users")      # => "/users"
    #   URLPath.join("/api", "")        # => "/api"
    #   URLPath.join("/api", "/")       # => "/api/"
    #
    # Note: This does not normalize multiple consecutive slashes within paths.
    # For example, URLPath.join("/api//v1", "users") produces "/api//v1/users".
    def self.join(parent : String, child : String) : String
      return child if parent.empty?
      return parent if child.empty?

      if parent.ends_with?("/") && child.starts_with?("/")
        "#{parent[0..-2]}#{child}"
      elsif !parent.ends_with?("/") && !child.starts_with?("/")
        "#{parent}/#{child}"
      else
        "#{parent}#{child}"
      end
    end

    # Join two URL path segments, collapsing *every* slash at the seam to
    # exactly one.
    #
    # Seven route extractors had this open-coded, byte for byte: the JVM DSL
    # ones (http4k, JAX-RS, Micronaut, the shared lambda-DSL extractor),
    # AdonisJS, Elysia, and the Scala Play analyzer.
    #
    # It is deliberately NOT `join`, and the two are not interchangeable —
    # `join` removes at most one slash and keeps a trailing one:
    #
    #   join("/api//", "/users")  # => "/api//users"
    #   join_trimmed(...)         # => "/api/users"
    #
    #   join("/api/", "")         # => "/api/"
    #   join_trimmed("/api/", "") # => "/api"
    #
    # Use this where a framework's prefix stack can contribute repeated or
    # trailing slashes that must not survive into the emitted URL; use `join`
    # where the segments are already normalised and a trailing slash is
    # meaningful.
    def self.join_trimmed(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end

    # Spring's mapping-composition rule, shared by the Java and Kotlin
    # tree-sitter route extractors (which carried byte-identical copies):
    # a bare method mapping (`@GetMapping` with no path arg) on a class
    # mapped to `/api/article` resolves to `/api/article` — the empty
    # segment is absorbed, not turned into `/api/article/`. An explicit
    # `@GetMapping("/")` still carries its own `/` segment and falls
    # through to the seam join. Only an all-slash class prefix
    # (`@RequestMapping("/")`) keeps the root `/`.
    #
    # Not `join_trimmed`: that keeps an empty-prefix suffix untouched but
    # trims a trailing slash when the *suffix* is empty without the
    # root-`/` restore this rule needs.
    def self.join_absorbing(prefix : String, path : String) : String
      return path if prefix.empty?
      if path.empty?
        trimmed = prefix.rstrip('/')
        return trimmed.empty? ? "/" : trimmed
      end
      "#{prefix.rstrip('/')}/#{path.lstrip('/')}"
    end

    # `join_absorbing` plus the guarantee that the result is a rooted URL
    # path: never empty, always leading-`/`.
    #
    # This is the rule Spring's servlet container applies when it composes
    # `server.servlet.context-path` with a controller's resolved mapping.
    # Both sides can legitimately be empty — the Java and Kotlin route
    # extractors default an unmapped class or a bare `@GetMapping` to `""`
    # (see `paths = [""] if paths.empty?`) — and the container serves that
    # as `/`, not as the empty string.
    #
    # Spring used to reach `File.join` for this, via a top-level
    # `join_paths` that unqualified calls fell through to. `File.join`
    # gets the empty cases right but three others wrong, which is what
    # this method exists to fix:
    #
    #   ("", "")          File.join "/"        join_rooted "/"
    #   ("/", "")         File.join "/"        join_rooted "/"
    #   ("", "users")     File.join "users"    join_rooted "/users"
    #   ("/api", "")      File.join "/api/"    join_rooted "/api"
    #   ("/api//", "/u")  File.join "/api//u"  join_rooted "/api/u"
    #
    # `join_trimmed` and `join_absorbing` are NOT substitutes: both return
    # `""` for `("", "")`, which would emit an endpoint with an empty URL.
    # `File.join` is also platform-dependent (`Path` uses the native
    # separator), so on Windows it composed `"/api\users"`.
    def self.join_rooted(prefix : String, path : String) : String
      joined = join_absorbing(prefix, path)
      return "/" if joined.empty?
      joined.starts_with?('/') ? joined : "/#{joined}"
    end
  end
end
