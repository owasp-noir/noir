# The concrete verbs a wildcard route (`ANY`/`ALL`/`*`) fans out to.
#
# `QUERY` (RFC 10008) is deliberately absent: fanning every wildcard route
# out to a QUERY endpoint would add one endpoint per catch-all route in
# every framework — reported, probed, and exported — for a verb almost no
# deployed app intends to serve. A `QUERY` endpoint is emitted only where
# a route declares the verb explicitly.
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

# The real HTTP methods an endpoint can carry. `QUERY` (RFC 10008) is
# accepted core-wide, but a framework analyzer adds it to its own verb
# table only when the upstream framework actually routes the verb —
# adding it speculatively would report endpoints the framework itself
# answers with 405.
ALLOWED_HTTP_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD", "TRACE", "CONNECT", "QUERY"]

# The verbs the read-vs-write heuristics treat as reads: GET/HEAD/OPTIONS
# plus QUERY (safe + idempotent per RFC 10008). TRACE, though RFC-safe, is
# excluded — it echoes the request rather than reading a resource, and no
# consumer ever counted it as a read. One shared set so the admin/webhook
# taggers, the ai_context unsafe-method signal, and the probe path-filler
# cannot drift on which verbs are safe. Callers normalize case themselves.
SAFE_HTTP_METHODS = Set{"GET", "HEAD", "OPTIONS", "QUERY"}

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
