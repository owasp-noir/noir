# NoirTechs catalog entry: js_vercel_functions.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  VERCEL_FUNCTIONS = {
    :js_vercel_functions => {
      :framework => "Vercel Functions",
      :language  => "JavaScript",
      :similar   => ["vercel functions", "vercel-functions", "js-vercel-functions", "js_vercel_functions"],
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
