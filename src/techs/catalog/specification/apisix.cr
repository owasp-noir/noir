# NoirTechs catalog entry: apisix.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  APISIX = {
    :apisix => {
      :format    => ["JSON", "YAML"],
      :similar   => ["apisix", "apache apisix", "apache-apisix", "apache_apisix"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => true,
          :cookie => false,
        },
      },
    },
  }
end
