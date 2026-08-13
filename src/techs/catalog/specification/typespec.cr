# NoirTechs catalog entry: typespec.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  TYPESPEC = {
    :typespec => {
      :format    => ["TYPESPEC"],
      :similar   => ["typespec", "tsp", "cadl"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
  }
end
