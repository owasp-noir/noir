# NoirTechs catalog entry: java_jsp.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  JSP = {
    :java_jsp => {
      :framework => "JSP",
      :language  => "Java",
      :similar   => ["jsp", "java-jsp", "java_jsp"],
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
        :static_path => true,
        :websocket   => false,
      },
      :context => {:guards => true},
    },
  }
end
