# NoirTechs catalog entry: js_react_router.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  REACT_ROUTER = {
    :js_react_router => {
      :framework => "React Router",
      :language  => "JavaScript",
      :similar   => ["react-router", "react_router", "js-react-router", "js_react_router", "@react-router/dev"],
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
