# NoirTechs catalog entry: java_wicket.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  WICKET = {
    :java_wicket => {
      :framework => "Apache Wicket",
      :language  => "Java",
      :similar   => ["wicket", "apache-wicket", "apache wicket", "java-wicket", "java_wicket"],
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
        :static_path => true,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
