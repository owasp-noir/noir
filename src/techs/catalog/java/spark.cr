# NoirTechs catalog entry: java_spark.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  SPARK = {
    :java_spark => {
      :framework => "Spark Java",
      :language  => "Java",
      :similar   => ["spark", "spark-java", "java-spark", "java_spark"],
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
