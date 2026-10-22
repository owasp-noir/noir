# NoirTechs catalog entry: groovy_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Groovy
  CLI = {
    :groovy_cli => {
      :framework => "CLI (CliBuilder / picocli / commons-cli / JCommander)",
      :language  => "Groovy",
      :similar   => ["groovy-cli", "groovy_cli", "clibuilder", "picocli", "commons-cli", "jcommander"],
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
