require "../../../models/analyzer"
require "./common"
require "../../../minilexers/csharp_lexer"

module Analyzer::CSharp
  # Surfaces ASP.NET Core SignalR real-time attack surface as `ws://`
  # endpoints. A SignalR `Hub` subclass exposes public methods the client
  # invokes over a long-lived connection; `MapHub<T>("/path")` mounts the
  # hub at a route. Each callable hub method becomes one endpoint
  # `ws://<hub-route>/<method>` (bare `ws://<hub-route>` when a hub has no
  # callable methods), method "SEND", protocol "ws" — so the existing
  # WebsocketTagger tags them. Method parameters (minus DI/service types)
  # become params (param_type "json").
  #
  # Line-scan analyzer (C# house style; there is no C# engine). Hub classes
  # and their `MapHub<T>` mounts routinely live in different files
  # (`ChatHub.cs` vs `Program.cs`), so routes and hubs are collected across
  # every `.cs` file first, then joined.
  class SignalR < Analyzer
    include Common

    # `app.MapHub<ChatHub>("/chatHub")` / `endpoints.MapHub<ChatHub>("/hub")`.
    MAP_HUB = /\bMapHub\s*<\s*([\w.]+)\s*>\s*\(\s*@?"([^"]+)"/

    # A hub class: the base list's first entry (C# requires the base class
    # first) is `Hub`, `Hub<T>` or `DynamicHub`, optionally namespace-
    # qualified. Custom base hubs (`: ChatHubBase`) are still caught when the
    # class is named in a `MapHub<T>` mount (see `hub_class?`).
    HUB_CLASS = /\bclass\s+(\w+)(?:\s*<[^>]*>)?\s*:\s*(?:[\w.]+\.)?(?:Hub(?:\s*<[^>]*>)?|DynamicHub)\b/

    # Any `class Name ...` opener — used to bound a hub body and to detect a
    # custom-base hub whose name was mounted via MapHub<T>.
    CLASS_OPEN = /\bclass\s+(\w+)(?:\s*<[^>]*>)?\s*(?::[^{]*)?/

    # A public instance method — a SignalR client-callable event. `override`
    # is excluded (lifecycle hooks `OnConnectedAsync`/`OnDisconnectedAsync`),
    # as are constructors and `Dispose`. Requires an opening paren so
    # properties/fields are skipped.
    PUBLIC_METHOD = /^\s*public\s+((?:(?:static|async|virtual|override|sealed|new|unsafe)\s+)*)(?:[\w<>\[\],.?]+\s+)+(\w+)\s*\(/

    # Lifecycle / infrastructure methods that are never client-invocable
    # events even when declared `public`.
    NON_EVENT_METHODS = Set{
      "OnConnectedAsync", "OnDisconnectedAsync", "OnConnected",
      "OnDisconnected", "OnReconnected", "Dispose", "DisposeAsync",
    }

    private record HubInfo,
      name : String,
      methods : Array(HubMethod),
      path : String,
      line : Int32

    private record HubMethod,
      name : String,
      params : Array(Param),
      line : Int32

    def analyze
      routes = {} of String => String # HubType => "/route"
      hubs = {} of String => HubInfo  # HubType => info
      map_hub_types = Set(String).new # types named in MapHub<T>

      files = get_files_by_extension(".cs").reject do |path|
        File.directory?(path) || Common.csharp_test_path?(path) || !File.exists?(path)
      end

      # Pass 1 — routes + mounted types across every file. A hub class and
      # its `MapHub<T>` mount routinely live in separate files, so the full
      # mounted-type set must be known before pass 2 decides whether a
      # custom-base class is a hub. `read_file_content` is cache-backed, so
      # the second read in pass 2 is cheap.
      files.each do |path|
        begin
          content = read_file_content(path)
          next unless content.includes?("MapHub")
          content.scan(MAP_HUB) do |m|
            hub_type = m[1].split('.').last
            map_hub_types << hub_type
            routes[hub_type] = m[2]
          end
        rescue e
          logger.debug "Error scanning SignalR routes in #{path}: #{e}"
          next
        end
      end

      # Pass 2 — hub classes and their callable methods.
      files.each do |path|
        begin
          content = read_file_content(path)
          next unless content.includes?("Hub")
          collect_hubs(content, path, hubs, map_hub_types)
        rescue e
          logger.debug "Error analyzing SignalR hub in #{path}: #{e}"
          next
        end
      end

      emit(hubs, routes)
      @result
    end

    private def collect_hubs(content : String, path : String,
                             hubs : Hash(String, HubInfo), map_hub_types : Set(String))
      lines = content.lines
      masked = Noir::CSharpLexer.new(content).masked_lines

      lines.each_with_index do |line, index|
        masked_line = masked[index]? || line
        # Match on the masked line so a `class X : Hub` inside a string/comment
        # is ignored, but only when the raw line agrees (regex reads raw).
        next unless masked_line.includes?("class")
        # Abstract base hubs are never mounted or client-callable; their
        # methods (if any) surface through the concrete subclass that IS
        # mounted, so skip the abstract declaration itself.
        next if masked_line.matches?(/\babstract\s+class\b/)

        name = hub_class?(line, masked_line, map_hub_types)
        next unless name
        next if hubs.has_key?(name)

        methods = extract_hub_methods(lines, masked, index)
        hubs[name] = HubInfo.new(name, methods, path, index + 1)
      end
    end

    # True when the `class` opener on this line declares a SignalR hub: its
    # base type is `Hub`/`Hub<T>`/`DynamicHub`, or its name was mounted via
    # `MapHub<T>`. Returns the class name or nil.
    private def hub_class?(line : String, masked_line : String, map_hub_types : Set(String)) : String?
      if m = line.match(HUB_CLASS)
        return m[1]
      end
      if m = line.match(CLASS_OPEN)
        name = m[1]
        return name if map_hub_types.includes?(name)
      end
      nil
    end

    # Collects the public, non-lifecycle methods declared directly in the
    # hub class body starting at `class_line`. The body is bounded by brace
    # depth over the masked lines so nested types/blocks don't leak sibling
    # methods.
    private def extract_hub_methods(lines : Array(String), masked : Array(String), class_line : Int32) : Array(HubMethod)
      methods = [] of HubMethod
      seen = Set(String).new

      # Advance to the class body's opening brace.
      i = class_line
      brace = 0
      started = false
      while i < lines.size
        m = masked[i]? || ""
        brace += m.count('{') - m.count('}')
        started ||= m.includes?("{")
        break if started && brace <= 0 && i > class_line
        i += 1
      end
      body_end = i

      (class_line...Math.min(body_end + 1, lines.size)).each do |idx|
        next if idx == class_line
        line = lines[idx]
        next unless (masked[idx]? || line).includes?("public")

        m = line.match(PUBLIC_METHOD)
        next unless m
        modifiers = m[1]
        next if modifiers.includes?("override") || modifiers.includes?("static")
        method_name = m[2]
        next if NON_EVENT_METHODS.includes?(method_name)
        next if seen.includes?(method_name)
        seen << method_name

        signature, _ = build_signature(lines, masked, idx)
        methods << HubMethod.new(method_name, extract_method_params(signature), idx + 1)
      end

      methods
    end

    # Extracts client-supplied parameters from a hub method signature,
    # dropping DI/service and framework types (`IHubContext`, `HubCaller
    # Context`, `CancellationToken`, …). Each becomes a "json" param.
    private def extract_method_params(signature : String) : Array(Param)
      params = [] of Param
      param_list = extract_balanced_param_list(signature)
      return params unless param_list

      split_csharp_parameters(param_list).each do |raw|
        decl = raw.strip
        next if decl.empty?
        # Drop attributes (`[FromServices] IFoo x`), default values and
        # `params`/`ref`/`out`/`in` modifiers, then read `<type> <name>`.
        decl = decl.gsub(/\[[^\]]*\]/, " ").strip
        decl = decl.split('=').first.strip
        tokens = decl.split(/\s+/)
        next if tokens.size < 2
        name = tokens.last
        type = tokens[-2]
        # `params`/modifier keywords can shift token positions; the name is
        # always the final identifier, so validate it looks like one.
        next unless name.matches?(/\A@?\w+\z/)
        name = name.lstrip('@')
        next if Common.csharp_service_type?(type)
        params << Param.new(name, "", "json")
      end

      params
    end

    private def emit(hubs : Hash(String, HubInfo), routes : Hash(String, String))
      hubs.each do |name, hub|
        route = routes[name]? || "/#{name}"
        surface = route.lstrip('/')
        surface = name if surface.empty?

        if hub.methods.empty?
          @result << build_endpoint("ws://#{surface}", [] of Param, hub.path, hub.line)
          next
        end

        hub.methods.each do |method|
          @result << build_endpoint("ws://#{surface}/#{method.name}", method.params, hub.path, method.line)
        end
      end
    end

    private def build_endpoint(url : String, params : Array(Param), path : String, line : Int32) : Endpoint
      ep = Endpoint.new(url, "SEND", params, Details.new(PathInfo.new(path, line)))
      ep.protocol = "ws"
      ep
    end
  end
end
