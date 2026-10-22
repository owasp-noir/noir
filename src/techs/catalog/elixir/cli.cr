# NoirTechs catalog entry: elixir_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Elixir
  CLI = {
    :elixir_cli => {
      :framework => "CLI (OptionParser / optimus)",
      :language  => "Elixir",
      :similar   => ["elixir-cli", "elixir_cli", "optionparser", "optimus"],
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
