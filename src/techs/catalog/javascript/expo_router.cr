# NoirTechs catalog entry: js_expo_router.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  EXPO_ROUTER = {
    :js_expo_router => {
      :framework => "Expo Router",
      :language  => "JavaScript",
      :similar   => ["expo-router", "expo_router", "js-expo-router", "js_expo_router"],
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
      :context => {:callee => true},
    },
  }
end
