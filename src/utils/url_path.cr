module Noir
  module URLPath
    # Join two URL path segments without introducing double slashes.
    #
    # This method is designed for joining route prefixes and paths in web frameworks.
    # It handles the common cases of trailing/leading slashes to produce clean URLs.
    #
    # Behavior:
    # - If parent is empty, returns child as-is
    # - If child is empty or "/", returns parent as-is (no trailing slash added)
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
      # When child is "/", preserve trailing slash for Express strict routing
      return parent.ends_with?("/") ? parent : "#{parent}/" if child == "/"

      if parent.ends_with?("/") && child.starts_with?("/")
        "#{parent[0..-2]}#{child}"
      elsif !parent.ends_with?("/") && !child.starts_with?("/")
        "#{parent}/#{child}"
      else
        "#{parent}#{child}"
      end
    end
  end
end
