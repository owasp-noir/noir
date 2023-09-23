require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderMarkdownTable < OutputBuilder
  def print(endpoints : Array(Endpoint))
    puts "| Endpoint | Protocol | Params |"
    puts "| -------- | -------- | ------ |"

    endpoints.each do |endpoint|
      if !endpoint.params.nil? && @scope.includes?("param")
        params_text = ""
        endpoint.params.each do |param|
          params_text += "`#{param.name} (#{param.param_type})` "
        end
        puts "| #{endpoint.method} #{endpoint.url} | #{endpoint.protocol} | #{params_text} |"
      else
        puts "| #{endpoint.method} #{endpoint.url} | #{endpoint.protocol} | - |"
      end
    end
  end
end
