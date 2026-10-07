# NoirTechs catalog entry: js_solidstart.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  SOLIDSTART = {
    :js_solidstart => {
      :framework => "SolidStart",
      :language  => "JavaScript",
      :similar   => ["solidstart", "solid-start", "js-solidstart", "js_solidstart", "@solidjs/start"],
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
