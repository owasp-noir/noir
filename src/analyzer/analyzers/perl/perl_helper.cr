module Analyzer::Perl
  # Shared helpers for the Perl framework analyzers (Catalyst, Mojolicious,
  # Dancer2). Kept framework-agnostic so each analyzer can opt in without
  # duplicating string conventions.
  module Helper
    extend self

    def underscore(name : String) : String
      name.gsub(/([a-z0-9])([A-Z])/, "\\1_\\2").downcase
    end
  end
end
