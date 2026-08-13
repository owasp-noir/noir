# NoirTechs catalog entry: hasura.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  HASURA = {
    :hasura => {
      :format    => ["YAML"],
      :similar   => ["hasura", "hasura-metadata", "hasura_metadata", "hasura graphql engine"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
