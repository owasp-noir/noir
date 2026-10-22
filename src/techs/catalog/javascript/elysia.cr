# NoirTechs catalog entry: js_elysia.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  ELYSIA = {
    :js_elysia => {
      :framework => "Elysia",
      :language  => "JavaScript",
      :similar   => ["elysia", "js-elysia", "js_elysia", "bun-elysia"],
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
