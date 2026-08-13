# NoirTechs catalog entry: oas2.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  OAS2 = {
    :oas2 => {
      :format    => ["JSON", "YAML"],
      :similar   => ["oas 2.0", "oas_2_0", "swagger 2.0", "swagger_2_0", "swagger"],
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
