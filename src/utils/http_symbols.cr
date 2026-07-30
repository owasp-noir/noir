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

# Verbs an endpoint can carry that are not HTTP methods: the wildcard
# `ANY`, and the AsyncAPI / messaging verbs the optimizer allow-lists so
# event-driven endpoints aren't downgraded to `GET`.
SYNTHETIC_ENDPOINT_METHODS = ["ANY", "PUBLISH", "SUBSCRIBE", "SEND", "RECEIVE"]

# The synthetic verb CLI entry points carry (`cli://<binary>/<subcommand>`).
CLI_ENDPOINT_METHOD = "CLI"

# Every verb that can appear as `Endpoint#method`. Consumers that have to
# tell "this token names a method" from "this token is part of a URL"
# (the probe matchers) read this instead of keeping their own list.
ENDPOINT_METHODS = ALLOWED_HTTP_METHODS + SYNTHETIC_ENDPOINT_METHODS + [CLI_ENDPOINT_METHOD]

def get_allowed_methods
  ALLOWED_HTTP_METHODS
end

def endpoint_method_token?(token : String) : Bool
  ENDPOINT_METHODS.includes?(token.upcase)
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
