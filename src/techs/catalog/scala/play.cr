# NoirTechs catalog entry: scala_play.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Scala
  PLAY = {
    :scala_play => {
      :framework => "Play Framework",
      :language  => "Scala",
      :similar   => ["play", "play-framework", "scala-play", "scala_play"],
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
      :context => {:callee => true, :guards => true},
    },
  }
end
