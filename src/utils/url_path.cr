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
  end
end
