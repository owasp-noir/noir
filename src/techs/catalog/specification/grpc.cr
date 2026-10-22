# NoirTechs catalog entry: grpc.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  GRPC = {
    :grpc => {
      :format    => ["PROTOBUF"],
      :similar   => ["grpc", "protobuf", "proto", "grpc-gateway"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
