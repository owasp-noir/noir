# NoirTechs catalog entry: asyncapi.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  ASYNCAPI = {
    :asyncapi => {
      :format    => ["JSON", "YAML"],
      :similar   => ["asyncapi", "async-api", "async_api"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
