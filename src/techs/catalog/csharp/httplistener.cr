# NoirTechs catalog entry: cs_httplistener.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  HTTPLISTENER = {
    :cs_httplistener => {
      :framework => "System.Net.HttpListener",
      :language  => "C#",
      :similar   => ["httplistener", "http-listener", "system.net.httplistener", "system-net-httplistener", "cs-httplistener", "cs_httplistener", "c# httplistener", "c#-httplistener", "c#_httplistener"],
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
      :context => {:callee => true},
    },
  }
end
