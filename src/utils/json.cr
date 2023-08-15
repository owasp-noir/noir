require "json"

def valid_json?(content : String) : Bool
  JSON.parse(content)
  true
rescue
  false
end
