# NoirTechs catalog entry: cs_wcf.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  WCF = {
    :cs_wcf => {
      :framework => "WCF (WebGet/WebInvoke)",
      :language  => "C#",
      :similar   => ["wcf", "corewcf", "cs-wcf", "cs_wcf", "c# wcf", "c#-wcf", "c#_wcf", "wcf-rest", "wcf_rest"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
