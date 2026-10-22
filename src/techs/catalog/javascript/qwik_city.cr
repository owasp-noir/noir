# NoirTechs catalog entry: js_qwik_city.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  QWIK_CITY = {
    :js_qwik_city => {
      :framework => "Qwik City",
      :language  => "JavaScript",
      :similar   => ["qwik-city", "qwikcity", "qwik_city", "js-qwik-city", "js_qwik_city", "@builder.io/qwik-city"],
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
