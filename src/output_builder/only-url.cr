require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderOnlyUrl < OutputBuilder
  def print(endpoints : Array(Endpoint))
    printed_urls = Set(String).new

    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)
      plain_url = baked[:url]
      r_url = plain_url.colorize(:light_yellow).toggle(@is_color)

      unless printed_urls.includes?(plain_url)
        ob_puts "#{r_url}"
        printed_urls.add(plain_url)
      end
    end
  end
end
