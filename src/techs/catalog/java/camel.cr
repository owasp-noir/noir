# NoirTechs catalog entry: java_camel.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  CAMEL = {
    :java_camel => {
      :framework => "Apache Camel",
      :language  => "Java",
      :similar   => ["camel", "apache-camel", "apache_camel", "java-camel", "java_camel"],
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
    },
  }
end
