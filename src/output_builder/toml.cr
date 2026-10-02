require "../models/output_builder"
require "../models/endpoint"
require "./toml_serializer"

@[Noir::OutputFormat(name: "toml", description: "TOML", order: 50, structured: true)]
class OutputBuilderToml < OutputBuilder
  include OutputBuilderTomlSerializer

  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult) = [] of PassiveScanResult)
    # Always emitted, empty included — see the note in `json.cr`. TOML is the
    # one format that cannot fully honor that: `generate_toml` renders arrays
    # as `[[table]]` blocks, and an empty array has no block to render, so a
    # clean scan stays silent here. That asymmetry belongs to the format.
    message = {
      "endpoints"       => endpoints,
      "passive_results" => passive_results,
      "errors"          => analyzer_failures,
    }.to_json
    json_obj = JSON.parse(message)
    toml_output = generate_toml(json_obj.as_h)
    ob_puts toml_output
  end

  private def generate_toml(data : Hash(String, JSON::Any)) : String
    String.build do |io|
      # First, output simple values
      data.each do |key, value|
        case value.raw
        when String, Int64, Float64, Bool
          io << "#{toml_key(key)} = #{toml_value(value)}\n"
        end
      end

      # Then, output arrays of tables
      data.each do |key, value|
        next unless items = value.as_a?
        items.each do |item|
          io << "\n[[#{toml_key(key)}]]\n" << generate_table_content(item.as_h) if item.raw.is_a?(Hash)
        end
      end

      # Finally, output nested tables (hashes that aren't in arrays)
      data.each do |key, value|
        io << "\n[#{toml_key(key)}]\n" << generate_table_content(value.as_h) if value.raw.is_a?(Hash)
      end
    end
  end
end
