require "crest"

def send_with_proxy(endpoints : Array(Endpoint), proxy : String)
  proxy_url = URI.parse(proxy)
  endpoints.each do |endpoint|
    begin
      Crest::Request.execute(
        method: get_symbol(endpoint.method),
        url: endpoint.url,
        p_addr: proxy_url.host,
        p_port: proxy_url.port,
        tls: OpenSSL::SSL::Context::Client.insecure,
        user_agent: "Noir/#{Noir::VERSION}"
      )
    rescue
    end
  end
end

def get_symbol(method : String)
  symbol = {
    "GET"    => :get,
    "POST"   => :post,
    "PUT"    => :put,
    "DELETE" => :delete,
  }

  symbol[method]
end
