# NoirTechs catalog entry: k8s_ingress.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  K8S_INGRESS = {
    :k8s_ingress => {
      :format    => ["YAML"],
      :similar   => ["kubernetes ingress", "k8s ingress", "kubernetes.io/ingress", "networking.k8s.io/v1"],
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
