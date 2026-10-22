require "../models/output_builder"
require "../models/endpoint"

@[Noir::OutputFormat(name: "only-tag", description: "Only tags", order: 210)]
class OutputBuilderOnlyTag < OutputBuilder
  def print(endpoints : Array(Endpoint))
    # Dedup by tag name, not `Tag.==` (field-wise): the line only shows the
    # name. Tags only exist when a tagger ran (-T/--use-taggers or AI context).
    tag_names = [] of String
    endpoints.each do |endpoint|
      endpoint.tags.each { |tag| tag_names << tag.name }
      endpoint.params.each do |param|
        param.tags.each { |tag| tag_names << tag.name }
      end
    end

    print_unique(tag_names, "No tags found. Run with -T/--use-taggers to populate tags.")
  end
end
