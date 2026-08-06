require "json"

# TOML emission shared by the `-f toml` builder and diff mode's `print_toml`.
#
# Both hand-roll TOML from the same `Endpoint#to_json` shape, and both had
# their own copy of these three methods. The copies had already drifted: only
# the `toml.cr` one quoted non-bare keys, so `diff.cr` would have emitted a key
# containing a dot as a dotted table path and corrupted the document. That is
# latent rather than live — every key in the endpoint JSON is bare-safe today —
# but it is exactly the kind of divergence a shared module prevents, and a
# change to one copy silently left the other behind.
module OutputBuilderTomlSerializer
  # Renders the scalar/array/inline-table body of one TOML table.
  private def generate_table_content(data : Hash(String, JSON::Any)) : String
    String.build do |io|
      data.each do |key, value|
        case value.raw
        when String, Int64, Float64, Bool
          io << "#{toml_key(key)} = #{toml_value(value)}\n"
        when Array
          io << "#{toml_key(key)} = ["
          io << value.as_a.map { |item| toml_value(item) }.join(", ")
          io << "]\n"
        when Hash
          # Nested inline table
          io << "#{toml_key(key)} = { "
          io << value.as_h.map { |k, v| "#{toml_key(k)} = #{toml_value(v)}" }.join(", ")
          io << " }\n"
        end
      end
    end
  end

  # TOML bare keys allow only [A-Za-z0-9_-]. A key with a dot, space, or
  # quote would otherwise be read as a dotted table path (config.file →
  # [config].file) and corrupt the document, so quote anything non-bare.
  private def toml_key(key : String) : String
    return key if key.matches?(/\A[A-Za-z0-9_-]+\z/)
    %("#{key.gsub("\\", "\\\\").gsub("\"", "\\\"")}")
  end

  private def toml_value(value : JSON::Any) : String
    case raw = value.raw
    when String
      # TOML basic strings can't contain raw newlines/control chars — escape
      # them so a multi-line snippet/description doesn't break the document.
      %("#{raw.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\b", "\\b").gsub("\t", "\\t").gsub("\n", "\\n").gsub("\f", "\\f").gsub("\r", "\\r")}")
    when Int64, Float64
      raw.to_s
    when Bool
      raw.to_s
    when Nil
      %("")
    when Array
      "[#{raw.map { |item| toml_value(item) }.join(", ")}]"
    when Hash
      "{ #{raw.map { |k, v| "#{toml_key(k)} = #{toml_value(v)}" }.join(", ")} }"
    else
      %("#{raw}")
    end
  end
end
