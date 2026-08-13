# NoirTechs catalog entry: js_adonisjs.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  ADONISJS = {
    :js_adonisjs => {
      :framework => "AdonisJS",
      :language  => "JavaScript",
      :similar   => ["adonisjs", "adonis", "js-adonisjs", "js_adonisjs"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
