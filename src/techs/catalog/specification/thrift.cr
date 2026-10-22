# NoirTechs catalog entry: thrift.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  THRIFT = {
    :thrift => {
      :format    => ["THRIFT"],
      :similar   => ["thrift", "apache-thrift", "thrift-idl"],
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
