# NoirTechs catalog entry: elixir_phoenix.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Elixir
  ELIXIR_PHOENIX = {
    :elixir_phoenix => {
      :framework => "Phoenix",
      :language  => "Elixir",
      :similar   => ["phoenix", "elixir-phoenix", "elixir_phoenix"],
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
