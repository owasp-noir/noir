# NoirTechs catalog entry: cfml_fw1.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Cfml
  FW1 = {
    :cfml_fw1 => {
      :framework => "FW/1",
      :language  => "CFML",
      :similar   => ["fw1", "fw/1", "framework-one", "framework.one", "cfml-fw1", "cfml_fw1"],
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
