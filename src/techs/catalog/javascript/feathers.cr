# NoirTechs catalog entry: js_feathers.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  FEATHERS = {
    :js_feathers => {
      :framework => "Feathers",
      :language  => "JavaScript",
      :similar   => ["feathers", "feathersjs", "feathers.js", "js-feathers", "js_feathers", "@feathersjs/feathers"],
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
      :context => {:callee => true},
    },
  }
end
