# NoirTechs catalog entry: python_http_server.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  HTTP_SERVER = {
    :python_http_server => {
      :framework => "http.server",
      :language  => "Python",
      :similar   => ["http.server", "python-http-server", "python_http_server", "BaseHTTPRequestHandler", "HTTPServer", "SimpleHTTPRequestHandler", "wsgiref.simple_server"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
