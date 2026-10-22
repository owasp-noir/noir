# NoirTechs catalog entry: openrpc.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  OPENRPC = {
    :openrpc => {
      :format    => ["JSON"],
      :similar   => ["openrpc", "open-rpc", "open_rpc", "jsonrpc", "json-rpc", "json_rpc"],
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
      },
    },
  }
end
