# NoirTechs catalog entry: cs_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  CLI = {
    :cs_cli => {
      :framework => "CLI (System.CommandLine / CommandLineParser / CliFx / Spectre.Console / McMaster / Cocona)",
      :language  => "C#",
      :similar   => ["cs-cli", "cs_cli", "csharp-cli", "system.commandline", "commandlineparser", "clifx", "spectre.console", "mcmaster", "commandlineutils", "cocona"],
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
