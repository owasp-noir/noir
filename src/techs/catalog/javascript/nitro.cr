# NoirTechs catalog entry: js_nitro.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  NITRO = {
    :js_nitro => {
      :framework => "Nitro",
      :language  => "JavaScript",
      :similar   => ["nitro", "nitrojs", "nitropack", "js-nitro", "js_nitro"],
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
