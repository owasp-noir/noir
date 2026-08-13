# NoirTechs catalog entry: go_restful.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Go
  GO_RESTFUL = {
    :go_restful => {
      :framework => "go-restful",
      :language  => "Go",
      :similar   => ["go-restful", "go_restful", "restful", "emicklei", "emicklei/go-restful"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
