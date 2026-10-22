# NoirTechs catalog entry: js_netlify_functions.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  NETLIFY_FUNCTIONS = {
    :js_netlify_functions => {
      :framework => "Netlify Functions",
      :language  => "JavaScript",
      :similar   => ["netlify functions", "netlify-functions", "js-netlify-functions", "js_netlify_functions"],
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
