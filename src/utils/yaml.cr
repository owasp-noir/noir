require "yaml"

def valid_yaml?(content : String) : Bool
  YAML.parse(content)
  true
rescue
  false
end
