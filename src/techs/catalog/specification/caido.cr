# NoirTechs catalog entry: caido.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  CAIDO = {
    :caido => {
      :format    => ["JSON"],
      :similar   => ["caido", "caido-export", "caido_export"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
  }
end
