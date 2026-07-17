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
    unique = tags.uniq(&.name)
    if unique.empty?
      # Tags only exist when a tagger ran (-T/--use-taggers or AI context).
      @logger.info "No tags found. Run with -T/--use-taggers to populate tags."
      return
    end
    unique.each do |tag|
      ob_puts tag.name.colorize(:light_green).toggle(@is_color)
    end
  end
end
