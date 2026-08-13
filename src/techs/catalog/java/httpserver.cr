# NoirTechs catalog entry: java_httpserver.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  HTTPSERVER = {
    :java_httpserver => {
      :framework => "JDK HttpServer",
      :language  => "Java",
      :similar   => ["jdk-httpserver", "java-httpserver", "java_httpserver", "com.sun.net.httpserver", "jdk.httpserver"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
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
