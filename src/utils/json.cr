require "json"

def valid_json?(content : String) : Bool
  JSON.parse(content)
  true
rescue
  false
end

# Strict `JSON.parse`-or-nil. Replaces the `valid_json?(content)` +
# `JSON.parse(content)` idiom in detectors, which parsed the same
# content twice per file.
def json_any?(content : String) : JSON::Any?
  JSON.parse(content)
rescue
  nil
end
