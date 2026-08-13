# NoirTechs catalog entry: js_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  CLI = {
    :js_cli => {
      :framework => "CLI (parseArgs / commander / yargs / cac / meow / minimist / citty / arg / command-line-args / getopts)",
      :language  => "JavaScript",
      :similar   => ["js-cli", "js_cli", "commander", "yargs", "cac", "meow", "minimist", "oclif", "clipanion", "sade", "citty", "arg", "command-line-args", "getopts"],
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
