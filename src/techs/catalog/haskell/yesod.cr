# NoirTechs catalog entry: haskell_yesod.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Haskell
  YESOD = {
    :haskell_yesod => {
      :framework => "Yesod",
      :language  => "Haskell",
      :similar   => ["yesod", "haskell-yesod", "haskell_yesod"],
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
      :context => {:callee => true},
    },
  }
end
