# NoirTechs catalog entry: cloudflare_wrangler.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  CLOUDFLARE_WRANGLER = {
    :cloudflare_wrangler => {
      :format    => ["TOML", "JSON"],
      :similar   => ["cloudflare", "cloudflare workers", "wrangler", "wrangler.toml", "wrangler.json", "wrangler.jsonc"],
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
