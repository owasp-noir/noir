# NoirTechs catalog entry: elixir_phoenix_channel.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Elixir
  PHOENIX_CHANNEL = {
    :elixir_phoenix_channel => {
      :framework => "Phoenix Channels",
      :language  => "Elixir",
      :similar   => ["phoenix-channel", "phoenix_channel", "phoenix-channels", "elixir-phoenix-channel", "elixir_phoenix_channel"],
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
        :websocket   => true,
      },
    },
  }
end
