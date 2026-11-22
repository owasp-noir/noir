require "../url_path"
require "../../models/endpoint"

module Noir::URLPath
  def self.params(path : String, *patterns : Regex, unique : Bool = false, doubled_braces : Bool = false) : Array(Param)
    path = unescape_braces(path) if doubled_braces
    result = [] of Param
    each_name(path, *patterns) do |name|
      result << Param.new(name, "", "path") unless unique && result.any? { |param| param.name == name }
    end
    result
  end

  def self.rewrite_params(path : String, pattern : Regex, *, unique : Bool = false)
    rewritten, names = rewrite_names(path, pattern)
    names.uniq! if unique
    {rewritten, names.map { |name| Param.new(name, "", "path") }}
  end

  def self.add_params(endpoint, path : String, *patterns : Regex)
    each_name(path, *patterns) { |name| endpoint.push_param(Param.new(name, "", "path")) }
  end
end
