require "json"

# Strict `JSON.parse`-or-nil.
def json_any?(content : String) : JSON::Any?
  JSON.parse(content)
rescue
  nil
end
