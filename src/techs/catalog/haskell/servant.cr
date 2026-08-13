# NoirTechs catalog entry: haskell_servant.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Haskell
  SERVANT = {
    :haskell_servant => {
      :framework => "Servant",
      :language  => "Haskell",
      :similar   => ["servant", "haskell-servant", "haskell_servant"],
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
