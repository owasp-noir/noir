WILDCARD_HTTP_METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "TRACE"]
SYNTHETIC_ANY_METHODS = ["ANY", "ALL", "*"]

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
    "QUERY"   => :query,
  }

  symbol[method]
end

ALLOWED_HTTP_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE", "CONNECT", "QUERY"]

def get_allowed_methods
  ALLOWED_HTTP_METHODS
end

def synthetic_any_method?(method : String) : Bool
  SYNTHETIC_ANY_METHODS.includes?(method.upcase)
end

def expand_synthetic_http_methods(method : String) : Array(String)
  normalized = method.upcase
  return WILDCARD_HTTP_METHODS if synthetic_any_method?(normalized)

  [normalized]
end

def requestable_http_methods(method : String) : Array(String)
  expand_synthetic_http_methods(method).select { |candidate| ALLOWED_HTTP_METHODS.includes?(candidate) }
end
