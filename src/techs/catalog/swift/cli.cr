# NoirTechs catalog entry: swift_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Swift
  CLI = {
    :swift_cli => {
      :framework => "CLI (swift-argument-parser / SwiftCLI)",
      :language  => "Swift",
      :similar   => ["swift-cli", "swift_cli", "argumentparser", "swift-argument-parser", "swiftcli"],
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
