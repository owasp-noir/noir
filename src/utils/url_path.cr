module Noir
  module URLPath
    # Join two URL path segments without introducing double slashes.
    def self.join(parent : String, child : String) : String
      return child if parent.empty?
      return parent if child.empty?
      return parent if child == "/"

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
