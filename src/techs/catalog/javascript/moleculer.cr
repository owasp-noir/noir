# NoirTechs catalog entry: js_moleculer.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  MOLECULER = {
    :js_moleculer => {
      :framework => "Moleculer",
      :language  => "JavaScript",
      :similar   => ["moleculer", "moleculer-web", "js-moleculer"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
