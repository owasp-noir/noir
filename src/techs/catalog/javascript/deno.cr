# NoirTechs catalog entry: js_deno.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  DENO = {
    :js_deno => {
      :framework => "Deno.serve",
      :language  => "JavaScript",
      :similar   => ["deno", "js-deno", "js_deno", "deno.serve", "deno-serve"],
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
    },
  }
end
