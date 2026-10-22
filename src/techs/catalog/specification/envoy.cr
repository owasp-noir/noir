# NoirTechs catalog entry: envoy.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  ENVOY = {
    :envoy => {
      :format    => ["JSON", "YAML"],
      :similar   => ["envoy", "envoy-proxy", "envoy_proxy", "istio-envoy"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
