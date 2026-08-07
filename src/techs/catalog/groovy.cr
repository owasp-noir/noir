# NoirTechs catalog: groovy technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  GROOVY = {
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
    :groovy_grails => {
      :framework => "Grails",
      :language  => "Groovy",
      :similar   => ["grails", "groovy_grails", "groovy-grails"],
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
    },
  }
end
