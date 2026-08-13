# NoirTechs catalog entry: java_struts2.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  STRUTS2 = {
    :java_struts2 => {
      :framework => "Apache Struts 2",
      :language  => "Java",
      :similar   => ["struts", "struts2", "apache-struts", "apache-struts2", "java-struts2", "java_struts2"],
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
