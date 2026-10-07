# NoirTechs catalog entry: js_firebase_functions.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  FIREBASE_FUNCTIONS = {
    :js_firebase_functions => {
      :framework => "Firebase Functions",
      :language  => "JavaScript",
      :similar   => ["firebase", "firebase-functions", "firebase_functions", "cloud functions", "js-firebase-functions"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
