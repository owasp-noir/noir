# NoirTechs catalog entry: crystal_grip.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Crystal
  GRIP = {
    :crystal_grip => {
      :framework => "Grip",
      :language  => "Crystal",
      :similar   => ["grip", "crystal-grip", "crystal_grip"],
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
        :static_path => false,
        :websocket   => true,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
