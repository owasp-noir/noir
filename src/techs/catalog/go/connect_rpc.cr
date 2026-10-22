# NoirTechs catalog entry: go_connect_rpc.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Go
  CONNECT_RPC = {
    :go_connect_rpc => {
      :framework => "Connect-RPC",
      :language  => "Go",
      :similar   => ["connect", "connect-rpc", "connect_rpc", "connectrpc", "go-connect", "go_connect_rpc"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
