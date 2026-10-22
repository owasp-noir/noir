# NoirTechs catalog entry: spring_cloud_gateway.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  SPRING_CLOUD_GATEWAY = {
    :spring_cloud_gateway => {
      :format    => ["YAML", "PROPERTIES"],
      :similar   => ["spring cloud gateway", "spring-cloud-gateway", "scg"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
