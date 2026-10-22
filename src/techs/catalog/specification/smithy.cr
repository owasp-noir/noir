# NoirTechs catalog entry: smithy.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  SMITHY = {
    :smithy => {
      :format    => ["SMITHY"],
      :similar   => ["smithy", "smithy-idl"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
  }
end
