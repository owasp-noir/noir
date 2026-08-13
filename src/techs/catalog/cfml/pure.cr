# NoirTechs catalog entry: cfml_pure.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Cfml
  PURE = {
    :cfml_pure => {
      :framework => "ColdFusion (CFML)",
      :language  => "CFML",
      :similar   => ["cfml", "coldfusion", "cfml-pure", "cfml_pure", "lucee", "boxlang"],
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
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
