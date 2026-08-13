# NoirTechs catalog entry: go_huma.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Go
  HUMA = {
    :go_huma => {
      :framework => "Huma",
      :language  => "Go",
      :similar   => ["huma", "go-huma", "go_huma", "danielgtaylor-huma"],
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
      :context => {:callee => true},
    },
  }
end
