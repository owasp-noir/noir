# NoirTechs catalog entry: js_http.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  HTTP = {
    :js_http => {
      :framework => "Node.js http/https",
      :language  => "JavaScript",
      :similar   => ["js-http", "js_http", "node-http", "node-https", "nodejs-http", "nodejs-https", "node:http", "node:https"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
