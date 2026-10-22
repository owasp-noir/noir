# NoirTechs catalog entry: crystal_amber.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Crystal
  AMBER = {
    :crystal_amber => {
      :framework => "Amber",
      :language  => "Crystal",
      :similar   => ["amber", "crystal-amber", "crystal_amber"],
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
        :websocket   => true,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
