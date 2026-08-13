# NoirTechs catalog entry: crystal_lucky.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Crystal
  LUCKY = {
    :crystal_lucky => {
      :framework => "Lucky",
      :language  => "Crystal",
      :similar   => ["lucky", "crystal-lucky", "crystal_lucky"],
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
