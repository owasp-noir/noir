require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderOnlyTag < OutputBuilder
  def print(endpoints : Array(Endpoint))
    tags = [] of Tag
    endpoints.each do |endpoint|
      if !endpoint.tags.nil?
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

    tags.uniq.each do |tag|
      ob_puts tag.name.colorize(:light_green).toggle(@is_color)
    end
  end
end
