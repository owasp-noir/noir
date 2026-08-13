# NoirTechs catalog entry: js_nestjs.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  NESTJS = {
    :js_nestjs => {
      :framework => "NestJS",
      :language  => "JavaScript",
      :similar   => ["nestjs", "nest", "js-nestjs", "js_nestjs"],
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
        :static_path => true,
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
