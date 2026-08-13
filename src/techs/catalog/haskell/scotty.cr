# NoirTechs catalog entry: haskell_scotty.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Haskell
  SCOTTY = {
    :haskell_scotty => {
      :framework => "Scotty",
      :language  => "Haskell",
      :similar   => ["scotty", "haskell-scotty", "haskell_scotty"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
