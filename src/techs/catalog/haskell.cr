# NoirTechs catalog: haskell technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  HASKELL = {
    :haskell_cli => {
      :framework => "CLI (optparse-applicative / cmdargs / GetOpt / turtle)",
      :language  => "Haskell",
      :similar   => ["haskell-cli", "haskell_cli", "optparse-applicative", "cmdargs", "turtle"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
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
