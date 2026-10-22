# NoirTechs catalog entry: elixir_bandit.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Elixir
  BANDIT = {
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
  }
end
