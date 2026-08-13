# NoirTechs catalog entry: apache_httpd.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  APACHE_HTTPD = {
    :apache_httpd => {
      :format    => ["CONF"],
      :similar   => ["apache", "apache httpd", "httpd", "htaccess", "apache2"],
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
