# NoirTechs catalog entry: zap_sites_tree.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  ZAP_SITES_TREE = {
    # The analyzer walks the exported node tree and emits `url` + `method`,
    # plus the `data` string split into `form` params. The query string is
    # dropped with the rest of the URI (only `uri.path` is kept), and the
    # export carries no header or cookie record — hence body-only params.
    #
    # No bare `"zap"` alias: `zig_zap` already owns it, and a duplicate
    # would resolve by TECHS iteration order rather than by intent.
    :zap_sites_tree => {
      :format    => ["YAML"],
      :similar   => ["zap_sites_tree", "zap-sites-tree", "zap-sitemap", "zap_sitemap", "zaproxy", "owasp-zap"],
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
