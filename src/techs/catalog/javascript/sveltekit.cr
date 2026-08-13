# NoirTechs catalog entry: js_sveltekit.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  SVELTEKIT = {
    :js_sveltekit => {
      :framework => "SvelteKit",
      :language  => "JavaScript",
      :similar   => ["sveltekit", "svelte-kit", "js-sveltekit", "js_sveltekit"],
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
