# NoirTechs catalog entry: elixir_absinthe.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Elixir
  ABSINTHE = {
    :elixir_absinthe => {
      :framework => "Absinthe",
      :language  => "Elixir",
      :similar   => ["absinthe", "elixir-absinthe", "elixir_absinthe"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => true,
      },
    },
  }
end
