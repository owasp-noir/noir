require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderMarkdownTable < OutputBuilder
  def print(endpoints : Array(Endpoint))
    ob_puts "| Endpoint | Protocol | Params |"
    ob_puts "| -------- | -------- | ------ |"

    endpoints.each do |endpoint|
      if !endpoint.params.nil?
        params_text = ""
        endpoint.params.each do |param|
          params_text += "`#{param.name} (#{param.param_type})` "
        end
        ob_puts "| #{endpoint.method} #{endpoint.url} | #{endpoint.protocol} | #{params_text} |"
      else
        ob_puts "| #{endpoint.method} #{endpoint.url} | #{endpoint.protocol} | - |"
      end
    end
  end
end
