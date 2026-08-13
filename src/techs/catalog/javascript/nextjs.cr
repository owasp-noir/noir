# NoirTechs catalog entry: js_nextjs.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  NEXTJS = {
    :js_nextjs => {
      :framework => "Next.js",
      :language  => "JavaScript",
      :similar   => ["nextjs", "next.js", "next", "js-nextjs", "js_nextjs"],
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
