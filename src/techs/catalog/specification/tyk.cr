# NoirTechs catalog entry: tyk.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  TYK = {
    :tyk => {
      :format    => ["JSON", "YAML"],
      :similar   => ["tyk", "tyk gateway", "tyk api definition", "tyk operator"],
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
