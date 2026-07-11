module Analyzer::Java
  # Shared helpers for the JVM-Java framework analyzers. Kept
  # framework-agnostic so each analyzer can reuse the common
  # path/string conventions without duplicating them.
  module Helper
    extend self

    def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end
  end
end
