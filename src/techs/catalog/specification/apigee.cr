# NoirTechs catalog entry: apigee.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  APIGEE = {
    :apigee => {
      :format    => ["XML"],
      :similar   => ["apigee", "apigee edge", "apigee x", "apiproxy"],
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
