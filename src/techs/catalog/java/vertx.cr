# NoirTechs catalog entry: java_vertx.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  VERTX = {
    :java_vertx => {
      :framework => "Vert.x",
      :language  => "Java",
      :similar   => ["vertx", "vert.x", "java-vertx", "java_vertx"],
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
      :context => {:callee => true, :guards => true},
    },
  }
end
