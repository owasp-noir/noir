# NoirTechs catalog entry: crystal_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Crystal
  CLI = {
    :crystal_cli => {
      :framework => "CLI (OptionParser / clim / admiral / commander.cr)",
      :language  => "Crystal",
      :similar   => ["crystal-cli", "crystal_cli", "optionparser", "clim", "admiral"],
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
