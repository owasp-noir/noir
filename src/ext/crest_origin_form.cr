require "crest"

# Crest builds every request from the full URL, so the request line reads
# `GET http://host:port/path HTTP/1.1` even on a direct connection. That
# absolute form is only for a plain-HTTP proxy; origin servers that don't
# accept it (Python's http.server, many embedded servers) answer 404 or 400,
# and `--status-codes` / `--probe` reported those instead of the real status.
#
# Send the origin form (`GET /path?query`) unless the request goes through a
# proxy in the clear. An HTTPS request through a proxy is tunnelled with
# CONNECT, and inside the tunnel the server expects the origin form too.
class Crest::Request
  private def new_http_request(method, url, headers, body) : HTTP::Request
    uri = URI.parse(url)
    return previous_def if @proxy && uri.scheme == "http"
    previous_def(method, uri.request_target, headers, body)
  end
end
