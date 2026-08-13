# NoirTechs catalog entry: cfml_wheels.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Cfml
  WHEELS = {
    :cfml_wheels => {
      :framework => "Wheels",
      :language  => "CFML",
      :similar   => ["wheels", "cfwheels", "cfml-wheels", "cfml_wheels"],
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
