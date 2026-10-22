# NoirTechs catalog entry: crystal_http.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Crystal
  HTTP = {
    :crystal_http => {
      :framework => "HTTP::Server",
      :language  => "Crystal",
      :similar   => ["http", "http_server", "crystal-http", "crystal_http", "http/server", "std/http"],
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
    },
  }
end
