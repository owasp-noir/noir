module Analyzer::Python
  # Shared path helpers for the Python framework analyzers. Kept
  # framework-agnostic so each analyzer can opt in without duplicating
  # the slash-collapse / leading-slash conventions.
  module Helper
    extend self

    # Collapse repeated slashes and ensure a single leading slash.
    def normalize_path(path : ::String) : ::String
      normalized = path.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized
    end

    def join_paths(prefix : ::String, path : ::String) : ::String
      return normalize_path(path) if prefix.empty?
      return normalize_path(prefix) if path.empty?

      normalize_path("#{prefix}/#{path}")
    end
  end
end
