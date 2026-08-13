# NoirTechs catalog entry: go_gf.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Go
  GF = {
    :go_gf => {
      :framework => "GoFrame",
      :language  => "Go",
      :similar   => ["gf", "goframe", "go-gf", "go_gf", "gogf/gf"],
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
