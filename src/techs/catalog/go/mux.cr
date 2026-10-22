# NoirTechs catalog entry: go_mux.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Go
  MUX = {
    :go_mux => {
      :framework => "Gorilla Mux",
      :language  => "Go",
      :similar   => ["mux", "go-mux", "go_mux", "gorilla-mux", "gorilla_mux"],
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
        :static_path => true,
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
