# NoirTechs catalog: swift technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  SWIFT = {
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
    :swift_vapor => {
      :framework => "Vapor",
      :language  => "Swift",
      :similar   => ["vapor", "swift-vapor", "swift_vapor"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :swift_kitura => {
      :framework => "Kitura",
      :language  => "Swift",
      :similar   => ["kitura", "swift-kitura", "swift_kitura"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :swift_hummingbird => {
      :framework => "Hummingbird",
      :language  => "Swift",
      :similar   => ["hummingbird", "swift-hummingbird", "swift_hummingbird"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
