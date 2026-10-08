# NoirTechs catalog entry: c_civetweb.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::C
  CIVETWEB = {
    :c_civetweb => {
      :framework => "CivetWeb",
      :language  => "C",
      :similar   => ["civetweb", "civet", "c-civetweb", "c_civetweb", "civetserver"],
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
        :websocket   => true,
      },
      :context => {:callee => true},
    },
  }
end
