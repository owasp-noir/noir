# NoirTechs catalog entry: java_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  CLI = {
    :java_cli => {
      :framework => "CLI (picocli / args4j / JCommander / commons-cli / airline / JOpt Simple)",
      :language  => "Java",
      :similar   => ["java-cli", "java_cli", "picocli", "args4j", "jcommander", "commons-cli", "airline", "jopt-simple", "joptsimple"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
