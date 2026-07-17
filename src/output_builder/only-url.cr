require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderOnlyUrl < OutputBuilder
  def print(endpoints : Array(Endpoint))
    printed_urls = Set(String).new
    # When --status-codes / --exclude-codes ran, noir already paid for the
    # HTTP probes; render the code next to the URL instead of discarding it
    # (the result was silently dropped under only-url before).
    show_status = any_to_bool(@options["status_codes"]?) || !@options["exclude_codes"]?.to_s.empty?

    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)
      plain_url = baked[:url]
      next if printed_urls.includes?(plain_url)
      printed_urls.add(plain_url)

      r_url = plain_url.colorize(:light_yellow).toggle(@is_color)
      if show_status
        code = endpoint.details.status_code || "error"
        ob_puts "#{r_url} [#{code}]"
      else
        ob_puts "#{r_url}"
      end
    end
  end
end
