# NoirTechs catalog entry: cfml_taffy.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Cfml
  TAFFY = {
    :cfml_taffy => {
      :framework => "Taffy",
      :language  => "CFML",
      :similar   => ["taffy", "cfml-taffy", "cfml_taffy", "coldfusion-taffy"],
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
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
