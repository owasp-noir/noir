# NoirTechs catalog entry: ruby_webrick.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Ruby
  WEBRICK = {
    :ruby_webrick => {
      :framework => "WEBrick",
      :language  => "Ruby",
      :similar   => ["webrick", "ruby-webrick", "ruby_webrick", "WEBrick::HTTPServer", "mount_proc", "AbstractServlet"],
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
      :context => {:callee => true, :guards => true},
    },
  }
end
