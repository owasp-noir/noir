# NoirTechs catalog: elixir technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  ELIXIR = {
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
    :elixir_bandit => {
      # Bandit hosts the same `Plug.Router` modules the Plug analyzer already
      # understands, so both detectors fire on a Bandit project. Bandit is the
      # more specific signal — it names the HTTP server actually serving the
      # routes — so keeping both would extract every endpoint twice under two
      # technology tags. Phoenix is unaffected: it owns the Phoenix.Router DSL.
      :supersedes => ["elixir_plug"],
      :framework  => "Bandit",
      :language   => "Elixir",
      :similar    => ["bandit", "elixir-bandit", "elixir_bandit"],
      :supported  => {
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
