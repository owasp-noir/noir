# NoirTechs catalog entry: wsdl.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  WSDL = {
    :wsdl => {
      :format    => ["XML"],
      :similar   => ["wsdl", "soap"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
  }
end
