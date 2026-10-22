# NoirTechs catalog entry: yarp.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  YARP = {
    :yarp => {
      :format    => ["JSON", "C#"],
      :similar   => ["yarp", "yarp.reverseproxy", "yet another reverse proxy"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => false,
          :header => true,
          :cookie => false,
        },
      },
    },
  }
end
