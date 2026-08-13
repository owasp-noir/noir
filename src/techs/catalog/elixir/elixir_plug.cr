# NoirTechs catalog entry: elixir_plug.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Elixir
  ELIXIR_PLUG = {
    :elixir_plug => {
      :framework => "Plug",
      :language  => "Elixir",
      :similar   => ["plug", "elixir-plug", "elixir_plug"],
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
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
