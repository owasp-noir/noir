# NoirTechs catalog entry: swift_hummingbird.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Swift
  HUMMINGBIRD = {
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
      :context => {:callee => true, :guards => true},
    },
  }
end
