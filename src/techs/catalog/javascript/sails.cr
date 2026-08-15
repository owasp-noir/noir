# NoirTechs catalog entry: js_sails.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  SAILS = {
    :js_sails => {
      :framework => "Sails.js",
      :language  => "JavaScript",
      :similar   => ["sails", "sailsjs", "js-sails"],
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
      :context => {:callee => false, :guards => false},
    },
  }
end
