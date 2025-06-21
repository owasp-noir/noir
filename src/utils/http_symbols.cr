def get_symbol(method : String)
  symbol = {
    "GET"     => :get,
    "POST"    => :post,
    "PUT"     => :put,
    "DELETE"  => :delete,
    "PATCH"   => :patch,
    "OPTIONS" => :options,
    "HEAD"    => :head,
    "TRACE"   => :trace,
    "CONNECT" => :connect,
  }

  symbol[method]
end

def get_allowed_methods
  ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE", "CONNECT"]
end
