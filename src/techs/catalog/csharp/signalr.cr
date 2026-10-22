# NoirTechs catalog entry: cs_signalr.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  SIGNALR = {
    :cs_signalr => {
      :framework => "ASP.NET Core SignalR",
      :language  => "C#",
      :similar   => ["signalr", "signal-r", "aspnet-signalr", "cs-signalr", "cs_signalr", "c# signalr", "c#-signalr", "c#_signalr"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => true,
      },
    },
  }
end
