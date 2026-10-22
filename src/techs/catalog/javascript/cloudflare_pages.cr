# NoirTechs catalog entry: js_cloudflare_pages.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  CLOUDFLARE_PAGES = {
    :js_cloudflare_pages => {
      :framework => "Cloudflare Pages Functions",
      :language  => "JavaScript",
      :similar   => ["cloudflare pages", "cloudflare-pages", "pages functions", "js-cloudflare-pages", "js_cloudflare_pages"],
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
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
