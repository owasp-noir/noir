# NoirTechs catalog entry: haskell_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Haskell
  CLI = {
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
  }
end
