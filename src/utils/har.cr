require "har"
require "./json"

module Noir::HarDocument
  extend self

  # The size fields the HAR shard types as `Int32?`.
  SIZE_KEYS = {"bodySize", "headersSize", "size", "compression", "hitCount"}

  # `HAR.from_string`, tolerating a size the shard cannot hold.
  #
  # One capture of a response over 2 GiB (`"bodySize": 3000000000`), or a
  # number beyond Int64, rejected the whole archive and every request in it.
  # Sizes are informational and HAR already spells "unknown" as -1, so on
  # that failure any size outside Int32 is read as -1 and the parse retried.
  def parse(content : String) : HAR::Log
    HAR.from_string(content)
  rescue ex : JSON::ParseException
    tree = parse_json_lenient(content)
    raise ex unless clamp_sizes(tree)
    HAR.from_string(tree.to_json)
  end

  private def clamp_sizes(node : JSON::Any) : Bool
    changed = false
    if hash = node.as_h?
      hash.each_key.to_a.each do |key|
        value = hash[key]
        if SIZE_KEYS.includes?(key) && !value.raw.nil? && !value.as_i64?.try { |size| Int32::MIN <= size <= Int32::MAX }
          hash[key] = JSON::Any.new(-1_i64)
          changed = true
        elsif clamp_sizes(value)
          changed = true
        end
      end
    elsif array = node.as_a?
      array.each { |item| changed = true if clamp_sizes(item) }
    end
    changed
  end
end
