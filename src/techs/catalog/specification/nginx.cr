# NoirTechs catalog entry: nginx.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  NGINX = {
    :nginx => {
      :format    => ["CONF"],
      :similar   => ["nginx", "nginx.conf", "sites-enabled", "conf.d"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
