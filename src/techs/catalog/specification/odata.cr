# NoirTechs catalog entry: odata.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  ODATA = {
    :odata => {
      :format    => ["XML"],
      :similar   => ["odata", "edmx", "csdl"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
