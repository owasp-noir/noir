# NoirTechs catalog entry: http_file.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  HTTP_FILE = {
    :http_file => {
      :format    => ["HTTP", "REST"],
      :similar   => ["http_file", "rest-client", "rest_client", "http-client", "http_client", ".http", ".rest"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
  }
end
