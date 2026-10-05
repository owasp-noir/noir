module Noir
  # Request-body format named by a JAX-RS / Micronaut `@Consumes` (or
  # `consumes =`) argument's source text: "form", "json", or nil when it
  # names neither.
  module JvmMediaType
    def self.body_format(text : String) : String?
      if text.includes?("APPLICATION_FORM_URLENCODED") || text.includes?("application/x-www-form-urlencoded")
        "form"
      elsif text.includes?("APPLICATION_JSON") || text.includes?("application/json")
        "json"
      elsif text.includes?("MULTIPART_FORM_DATA") || text.includes?("multipart/form-data")
        "form"
      end
    end
  end
end
