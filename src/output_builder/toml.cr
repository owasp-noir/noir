require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderToml < OutputBuilder
  def print(endpoints : Array(Endpoint))
    message = {"endpoints" => endpoints, "passive_results" => [] of PassiveScanResult}.to_json
    json_obj = JSON.parse(message)
    toml_output = generate_toml(json_obj.as_h)
    ob_puts toml_output
  end

  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    message = {"endpoints" => endpoints, "passive_results" => passive_results}.to_json
    json_obj = JSON.parse(message)
    toml_output = generate_toml(json_obj.as_h)
    ob_puts toml_output
  end

  private def generate_toml(data : Hash(String, JSON::Any), prefix : String = "") : String
    result = String.build do |io|
      # First, output simple values
      data.each do |key, value|
        case value.raw
        when String, Int64, Float64, Bool
          full_key = prefix.empty? ? key : "#{prefix}.#{key}"
          io << "#{full_key} = #{toml_value(value)}\n"
        end
      end

      # Then, output arrays of tables
      data.each do |key, value|
        if value.raw.is_a?(Array)
          full_key = prefix.empty? ? key : "#{prefix}.#{key}"
          value.as_a.each do |item|
            if item.raw.is_a?(Hash)
              io << "\n[[#{full_key}]]\n"
              io << generate_table_content(item.as_h)
            end
          end
        end
      end

      # Finally, output nested tables (hashes that aren't in arrays)
      data.each do |key, value|
        if value.raw.is_a?(Hash)
          full_key = prefix.empty? ? key : "#{prefix}.#{key}"
          io << "\n[#{full_key}]\n"
          io << generate_table_content(value.as_h)
        end
      end
    end
    result
  end

  private def generate_table_content(data : Hash(String, JSON::Any)) : String
    result = String.build do |io|
      data.each do |key, value|
        case value.raw
        when String, Int64, Float64, Bool
          io << "#{key} = #{toml_value(value)}\n"
        when Array
          io << "#{key} = ["
          items = value.as_a.map { |item| toml_value(item) }
          io << items.join(", ")
          io << "]\n"
        when Hash
          # Nested inline table
          io << "#{key} = { "
          pairs = value.as_h.map { |k, v| "#{k} = #{toml_value(v)}" }
          io << pairs.join(", ")
          io << " }\n"
        end
      end
    end
    result
  end

  private def toml_value(value : JSON::Any) : String
    case raw = value.raw
    when String
      %("#{raw.gsub("\\", "\\\\").gsub("\"", "\\\"")}")
    when Int64, Float64
      raw.to_s
    when Bool
      raw.to_s
    when Nil
      %("")
    when Array
      items = raw.map { |item| toml_value(item) }
      "[#{items.join(", ")}]"
    when Hash
      pairs = raw.map { |k, v| "#{k} = #{toml_value(v)}" }
      "{ #{pairs.join(", ")} }"
    else
      %("#{raw}")
    end
  end
end
