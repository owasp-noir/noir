# NoirTechs catalog entry: crystal_kemal.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Crystal
  KEMAL = {
    :crystal_kemal => {
      :framework => "Kemal",
      :language  => "Crystal",
      :similar   => ["kemal", "crystal-kemal", "crystal_kemal"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
