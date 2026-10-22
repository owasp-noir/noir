# NoirTechs catalog entry: mitmproxy.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  MITMPROXY = {
    :mitmproxy => {
      :format    => ["TNETSTRING"],
      :similar   => ["mitmproxy", "mitm", "mitmdump", "flow", "flows"],
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
      },
    },
  }
end
