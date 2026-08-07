# NoirTechs catalog: csharp technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  CSHARP = {
    :cs_cli => {
      :framework => "CLI (System.CommandLine / CommandLineParser / CliFx / Spectre.Console / McMaster / Cocona)",
      :language  => "C#",
      :similar   => ["cs-cli", "cs_cli", "csharp-cli", "system.commandline", "commandlineparser", "clifx", "spectre.console", "mcmaster", "commandlineutils", "cocona"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :cs_aspnet_mvc => {
      :framework => "ASP.NET MVC",
      :language  => "C#",
      :similar   => ["asp.net mvc", "cs-aspnet-mvc", "cs_aspnet_mvc", "c# asp.net mvc", "c#-asp.net-mvc", "c#_aspnet_mvc"],
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
    },
    :cs_aspnet_core_mvc => {
      :framework => "ASP.NET Core MVC",
      :language  => "C#",
      :similar   => ["asp.net core mvc", "asp.net core", "aspnetcore", "cs-aspnet-core-mvc", "cs_aspnet_core_mvc", "c# asp.net core mvc", "c#-asp.net-core-mvc", "c#_aspnet_core_mvc"],
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
    },
    :cs_aspnet_core_minimal_api => {
      :framework => "ASP.NET Core Minimal API",
      :language  => "C#",
      :similar   => ["asp.net core minimal api", "asp.net core minimal apis", "minimal api", "minimal apis", "cs-aspnet-core-minimal-api", "cs_aspnet_core_minimal_api", "c# asp.net core minimal api", "c#-aspnet-core-minimal-api", "c#_aspnet_core_minimal_api"],
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
    },
    :cs_carter => {
      :framework => "Carter",
      :language  => "C#",
      :similar   => ["carter", "cs-carter", "cs_carter", "c# carter", "c#-carter", "c#_carter"],
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
    },
    :cs_fastendpoints => {
      :framework => "FastEndpoints",
      :language  => "C#",
      :similar   => ["fastendpoints", "fast-endpoints", "cs-fastendpoints", "cs_fastendpoints", "c# fastendpoints", "c#-fastendpoints", "c#_fastendpoints"],
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
    },
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
    },
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
