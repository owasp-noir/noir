# NoirTechs catalog entry: js_bun.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  BUN = {
    :js_bun => {
      :framework => "Bun.serve",
      :language  => "JavaScript",
      :similar   => ["bun", "js-bun", "js_bun", "bun.serve", "bun-serve"],
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
    },
  }
end
