# NoirTechs catalog entry: cfml_coldbox.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Cfml
  COLDBOX = {
    :cfml_coldbox => {
      :framework => "ColdBox",
      :language  => "CFML",
      :similar   => ["coldbox", "cfml-coldbox", "cfml_coldbox", "contentbox"],
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
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
