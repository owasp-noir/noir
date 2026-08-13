# NoirTechs catalog entry: oas3.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  OAS3 = {
    :oas3 => {
      :format    => ["JSON", "YAML"],
      :similar   => ["oas 3.0", "oas_3_0"],
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
