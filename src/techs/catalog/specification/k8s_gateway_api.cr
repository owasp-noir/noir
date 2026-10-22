# NoirTechs catalog entry: k8s_gateway_api.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  K8S_GATEWAY_API = {
    :k8s_gateway_api => {
      :format    => ["YAML"],
      :similar   => ["kubernetes gateway api", "k8s gateway api", "httproute", "gateway.networking.k8s.io"],
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
