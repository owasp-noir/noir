# NoirTechs catalog entry: go_httprouter.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Go
  HTTPROUTER = {
    :go_httprouter => {
      :framework => "httprouter",
      :language  => "Go",
      :similar   => ["httprouter", "go-httprouter", "go_httprouter", "julienschmidt-httprouter"],
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
