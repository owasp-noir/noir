# NoirTechs catalog entry: java_spring_data_rest.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  SPRING_DATA_REST = {
    :java_spring_data_rest => {
      :framework => "Spring Data REST",
      :language  => "Java",
      :similar   => ["spring-data-rest", "spring data rest", "java-spring-data-rest", "java_spring_data_rest"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
