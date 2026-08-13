# NoirTechs catalog entry: js_hapi.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  HAPI = {
    :js_hapi => {
      :framework => "Hapi",
      :language  => "JavaScript",
      :similar   => ["hapi", "js-hapi", "js_hapi", "@hapi/hapi"],
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
