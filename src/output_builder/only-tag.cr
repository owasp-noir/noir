require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderOnlyTag < OutputBuilder
  def print(endpoints : Array(Endpoint))
    tags = [] of Tag
    endpoints.each do |endpoint|
      unless endpoint.tags.nil?
        endpoint.tags.each do |tag|
          tags << tag
        end
      end

      if endpoint.params.size > 0
        endpoint.params.each do |param|
          if param.tags.size > 0
            param.tags.each do |tag|
              tags << tag
            end
          end
        end
      end
    end

    # Dedup by tag name. `Tag.==` is field-wise (name + description +
    # tagger), so two tags with the same `name` but different `tagger`
    # or `description` would otherwise both be printed even though the
    # output line only shows the name.
    tags.uniq(&.name).each do |tag|
      ob_puts tag.name.colorize(:light_green).toggle(@is_color)
    end
  end
end
