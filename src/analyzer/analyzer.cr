require "./analyzers/**"
require "./analyzers/file_analyzers/*"

macro define_analyzers(analyzers)
  {% for analyzer in analyzers %}
    analyzers[{{ analyzer[0].id.stringify }}] = ->(options : Hash(String, YAML::Any)) do
      instance = Analyzer::{{ analyzer[1].id }}.new(options)
      instance.analyze
    end
  {% end %}
end

def initialize_analyzers(logger : NoirLogger)
  # Initializing analyzers
  analyzers = {} of String => Proc(Hash(String, YAML::Any), Array(Endpoint))

  # Mapping analyzers to their respective functions
  define_analyzers([
    {"cpp_drogon", Cpp::Drogon},
    {"cpp_cli", Cpp::Cli},
    {"cpp_crow", Cpp::Crow},
    {"cpp_httplib", Cpp::Httplib},
    {"cpp_oatpp", Cpp::Oatpp},
    {"clojure_cli", Clojure::Cli},
    {"clojure_compojure", Clojure::Compojure},
    {"clojure_pedestal", Clojure::Pedestal},
    {"clojure_reitit", Clojure::Reitit},
    {"clojure_ring", Clojure::Ring},
    {"cs_cli", CSharp::Cli},
    {"cs_aspnet_mvc", CSharp::AspNetMvc},
    {"cs_aspnet_core_mvc", CSharp::AspNetCoreMvc},
    {"cs_aspnet_core_minimal_api", CSharp::MinimalApis},
    {"cs_carter", CSharp::Carter},
    {"cs_fastendpoints", CSharp::FastEndpoints},
    {"cs_httplistener", CSharp::HttpListener},
    {"crystal_cli", Crystal::Cli},
    {"crystal_amber", Crystal::Amber},
    {"crystal_grip", Crystal::Grip},
    {"crystal_kemal", Crystal::Kemal},
    {"crystal_lucky", Crystal::Lucky},
    {"crystal_marten", Crystal::Marten},
    {"crystal_http", Crystal::Http},
    {"dart_cli", Dart::Cli},
    {"dart_alfred", Dart::Alfred},
    {"dart_angel3", Dart::Angel3},
    {"dart_get_server", Dart::GetServer},
    {"dart_frog", Dart::DartFrog},
    {"dart_http", Dart::Http},
    {"dart_serverpod", Dart::Serverpod},
    {"dart_shelf", Dart::Shelf},
    {"elixir_cli", Elixir::Cli},
    {"elixir_bandit", Elixir::Bandit},
    {"elixir_phoenix", Elixir::Phoenix},
    {"elixir_plug", Elixir::Plug},
    {"fs_giraffe", Fsharp::Giraffe},
    {"perl_cli", Perl::Cli},
    {"perl_catalyst", Perl::Catalyst},
    {"perl_dancer2", Perl::Dancer2},
    {"perl_mojolicious", Perl::Mojolicious},
    {"go_beego", Go::Beego},
    {"go_cli", Go::Cli},
    {"go_echo", Go::Echo},
    {"go_fasthttp", Go::Fasthttp},
    {"go_fiber", Go::Fiber},
    {"go_gin", Go::Gin},
    {"go_hertz", Go::Hertz},
    {"go_iris", Go::Iris},
    {"go_restful", Go::GoRestful},
    {"go_chi", Go::Chi},
    {"go_gozero", Go::GoZero},
    {"go_goyave", Go::Goyave},
    {"go_gf", Go::Gf},
    {"go_http", Go::Http},
    {"go_httprouter", Go::Httprouter},
    {"go_huma", Go::Huma},
    {"go_mux", Go::Mux},
    {"go_pocketbase", Go::Pocketbase},
    {"go_connect_rpc", Go::ConnectRpc},
    {"groovy_cli", Groovy::Cli},
    {"groovy_grails", Groovy::Grails},
    {"haskell_cli", Haskell::Cli},
    {"haskell_scotty", Haskell::Scotty},
    {"haskell_servant", Haskell::Servant},
    {"haskell_yesod", Haskell::Yesod},
    {"asyncapi", Specification::AsyncApi},
    {"envoy", Specification::Envoy},
    {"bruno", Specification::Bruno},
    {"burp", Specification::Burp},
    {"caddy", Specification::Caddy},
    {"caido", Specification::Caido},
    {"grpc", Specification::Grpc},
    {"har", Specification::Har},
    {"java_cli", Java::Cli},
    {"java_armeria", Java::Armeria},
    {"java_dropwizard", Java::Dropwizard},
    {"java_httpserver", Java::HttpServer},
    {"java_javalin", Java::Javalin},
    {"java_jaxrs", Java::JaxRs},
    {"java_jsp", Java::Jsp},
    {"java_micronaut", Java::Micronaut},
    {"java_quarkus", Java::Quarkus},
    {"java_spark", Java::Spark},
    {"java_spring", Java::Spring},
    {"java_struts2", Java::Struts2},
    {"lua_cli", Lua::Cli},
    {"lua_lapis", Lua::Lapis},
    {"lua_lor", Lua::Lor},
    {"android", Mobile::Android},
    {"ios", Mobile::Ios},
    {"well_known_applinks", Mobile::WellKnown},
    {"java_vertx", Java::Vertx},
    {"java_wicket", Java::Wicket},
    {"js_adonisjs", Javascript::Adonisjs},
    {"js_cli", Javascript::Cli},
    {"js_apollo", Javascript::Apollo},
    {"js_astro", Javascript::Astro},
    {"js_elysia", Javascript::Elysia},
    {"js_express", Javascript::Express},
    {"js_fastify", Javascript::Fastify},
    {"js_fresh", Javascript::Fresh},
    {"js_graphql_yoga", Javascript::GraphqlYoga},
    {"js_hapi", Javascript::Hapi},
    {"js_hono", Javascript::Hono},
    {"js_http", Javascript::Http},
    {"js_koa", Javascript::Koa},
    {"js_nestjs", Javascript::Nestjs},
    {"js_nextjs", Javascript::Nextjs},
    {"js_nitro", Javascript::Nitro},
    {"js_nuxtjs", Javascript::Nuxtjs},
    {"js_remix", Javascript::Remix},
    {"js_restify", Javascript::Restify},
    {"js_sveltekit", Javascript::Sveltekit},
    {"kotlin_cli", Kotlin::Cli},
    {"kotlin_http4k", Kotlin::Http4k},
    {"kotlin_spring", Kotlin::Spring},
    {"kotlin_ktor", Kotlin::Ktor},
    {"graphql_sdl", Specification::GraphqlSdl},
    {"apache_httpd", Specification::ApacheHttpd},
    {"apisix", Specification::Apisix},
    {"aws_cdk", Specification::AwsCdk},
    {"aws_cloudformation", Specification::AwsCloudformation},
    {"azure_functions", Specification::AzureFunctions},
    {"cloudflare_wrangler", Specification::CloudflareWrangler},
    {"k8s_gateway_api", Specification::K8sGatewayApi},
    {"k8s_ingress", Specification::K8sIngress},
    {"kong", Specification::Kong},
    {"oas2", Specification::Oas2},
    {"oas3", Specification::Oas3},
    {"insomnia", Specification::Insomnia},
    {"istio_virtualservice", Specification::IstioVirtualservice},
    {"kamal", Specification::Kamal},
    {"mitmproxy", Specification::Mitmproxy},
    {"netlify", Specification::Netlify},
    {"nginx", Specification::Nginx},
    {"odata", Specification::OData},
    {"postman", Specification::Postman},
    {"raml", Specification::RAML},
    {"serverless_framework", Specification::ServerlessFramework},
    {"smithy", Specification::Smithy},
    {"traefik", Specification::Traefik},
    {"typespec", Specification::TypeSpec},
    {"vercel", Specification::Vercel},
    {"wsdl", Specification::WSDL},
    {"zap_sites_tree", Specification::ZapSitesTree},
    {"php_cli", Php::Cli},
    {"php_pure", Php::Php},
    {"php_cakephp", Php::CakePHP},
    {"php_codeigniter", Php::CodeIgniter},
    {"php_hyperf", Php::Hyperf},
    {"php_laminas", Php::Laminas},
    {"php_laravel", Php::Laravel},
    {"php_lumen", Php::Lumen},
    {"php_mautic", Php::Mautic},
    {"php_slim", Php::Slim},
    {"php_symfony", Php::Symfony},
    {"php_thinkphp", Php::ThinkPHP},
    {"php_yii", Php::Yii},
    {"python_aiohttp", Python::Aiohttp},
    {"python_cli", Python::Cli},
    {"python_django", Python::Django},
    {"python_fastapi", Python::FastAPI},
    {"python_bottle", Python::Bottle},
    {"python_falcon", Python::Falcon},
    {"python_flask", Python::Flask},
    {"python_litestar", Python::Litestar},
    {"python_pyramid", Python::Pyramid},
    {"python_quart", Python::Quart},
    {"python_robyn", Python::Robyn},
    {"python_sanic", Python::Sanic},
    {"python_starlette", Python::Starlette},
    {"python_tornado", Python::Tornado},
    {"python_http_server", Python::HttpServer},
    {"ruby_cli", Ruby::Cli},
    {"ruby_grape", Ruby::Grape},
    {"ruby_hanami", Ruby::Hanami},
    {"ruby_rails", Ruby::Rails},
    {"ruby_roda", Ruby::Roda},
    {"ruby_sinatra", Ruby::Sinatra},
    {"ruby_webrick", Ruby::Webrick},
    {"rust_cli", Rust::Cli},
    {"rust_axum", Rust::Axum},
    {"rust_rocket", Rust::Rocket},
    {"rust_actix_web", Rust::ActixWeb},
    {"rust_loco", Rust::Loco},
    {"rust_rwf", Rust::Rwf},
    {"rust_tide", Rust::Tide},
    {"rust_warp", Rust::Warp},
    {"rust_gotham", Rust::Gotham},
    {"rust_salvo", Rust::Salvo},
    {"rust_poem", Rust::Poem},
    {"scala_cli", Scala::Cli},
    {"scala_akka", Scala::Akka},
    {"scala_scalatra", Scala::Scalatra},
    {"scala_play", Scala::Play},
    {"scala_http4s", Scala::Http4s},
    {"scala_zio_http", Scala::ZioHttp},
    {"scala_tapir", Scala::Tapir},
    {"java_play", Java::Play},
    {"swift_cli", Swift::Cli},
    {"swift_vapor", Swift::Vapor},
    {"swift_kitura", Swift::Kitura},
    {"swift_hummingbird", Swift::Hummingbird},
    {"ts_nestjs", Typescript::Nestjs},
    {"ts_tanstack_router", Typescript::TanstackRouter},
    {"ts_trpc", Typescript::TRPC},
    {"zig_cli", Zig::Cli},
    {"zig_jetzig", Zig::Jetzig},
    {"zig_zap", Zig::Zap},
    {"zig_http", Zig::Http},
    {"zig_httpz", Zig::Httpz},
    {"zig_tokamak", Zig::Tokamak},
    {"ai", AI::Unified},
  ])

  logger.debug "#{analyzers.size} Analyzers initialized"
  analyzers.each do |key, _|
    logger.debug_sub "#{key} initialized"
  end
  analyzers
end

def filter_redundant_generic_techs(techs : Array(String)) : Array(String)
  filtered = techs.dup

  php_frameworks = Set{
    "php_laravel",
    "php_lumen",
    "php_symfony",
    "php_cakephp",
    "php_codeigniter",
    "php_hyperf",
    "php_laminas",
    "php_mautic",
    "php_slim",
    "php_thinkphp",
    "php_yii",
  }

  if filtered.includes?("php_pure") && filtered.any? { |tech| php_frameworks.includes?(tech) }
    filtered.reject!("php_pure")
  end

  # Lumen and Laravel share enough surface (Illuminate namespaces, the `routes/`
  # convention) that the Laravel detector also fires on Lumen projects. When
  # Lumen is the actual framework, the Laravel signal is just noise.
  if filtered.includes?("php_lumen") && filtered.includes?("php_laravel")
    filtered.reject!("php_laravel")
  end

  # Bandit hosts the same `Plug.Router` modules the Plug analyzer
  # already understands, so both detectors fire on a Bandit project.
  # When both are present, the Bandit signal is the more specific one
  # (it tells you which HTTP server is actually serving the routes);
  # keep it and drop the redundant Plug entry so endpoints aren't
  # extracted twice with two different technology tags. The Phoenix
  # analyzer is unaffected — it owns the Phoenix.Router DSL.
  if filtered.includes?("elixir_bandit") && filtered.includes?("elixir_plug")
    filtered.reject!("elixir_plug")
  end

  # Jetzig and Tokamak are both built on top of http.zig (httpz), so a
  # project that vendors either framework's source also carries the
  # `@import("httpz")` / `.httpz` dependency markers the httpz detector
  # keys on. When the more specific framework is present it owns the
  # routing DSL; keep it and drop the redundant httpz entry so the httpz
  # analyzer doesn't also scan the framework's internals.
  if filtered.includes?("zig_httpz") && (filtered.includes?("zig_jetzig") || filtered.includes?("zig_tokamak"))
    filtered.reject!("zig_httpz")
  end

  filtered
end

def analysis_endpoints(options : Hash(String, YAML::Any), techs, logger : NoirLogger)
  result = [] of Endpoint
  file_analyzer = FileAnalyzer.new options
  logger.info "Initializing analyzers"

  analyzer = initialize_analyzers logger

  logger.verbose "Loaded #{analyzer.size} analyzers"

  logger.info "Analysis Started"
  logger.sub "➔ Code Analyzer: #{techs.size} in use"

  if (!options["ai_provider"].to_s.empty?) && ((!options["ai_model"].to_s.empty?) || LLM::ACPClient.acp_provider?(options["ai_provider"].to_s))
    provider = options["ai_provider"].to_s
    raw_model = options["ai_model"].to_s
    model = if LLM::ACPClient.acp_provider?(provider)
              LLM::ACPClient.default_model(provider, raw_model)
            else
              raw_model
            end
    logger.sub "➔ AI Analyzer: Server=#{provider}, Model=#{model}"
    techs << "ai"
  end

  # Run tech analyzers concurrently to avoid long stalls from a single analyzer
  selected_techs = filter_redundant_generic_techs(techs).select { |t| analyzer.has_key?(t) }
  mutex = Mutex.new

  # Pre-build extension index synchronously to avoid concurrent mutation in multiple threads/fibers
  CodeLocator.instance.build_extension_index

  WaitGroup.wait do |wg|
    selected_techs.each do |tech|
      wg.spawn do
        begin
          logger.debug "Analyzer[#{tech}] start"
          endpoints = analyzer[tech].call(options)
          # Set technology on each endpoint using map to handle struct copy
          endpoints_with_tech = endpoints.map do |ep|
            details = ep.details
            details.technology = tech
            ep.details = details
            ep
          end
          mutex.synchronize { result.concat(endpoints_with_tech) }
          logger.debug "Analyzer[#{tech}] done (#{endpoints.size})"
        rescue e
          logger.warning "Analyzer[#{tech}] failed: #{e.message}"
        end
      end
    end
  end

  unless options["url"].to_s.empty?
    logger.sub "➔ File-based Analyzer: #{file_analyzer.hooks_count} hook#{'s' unless file_analyzer.hooks_count == 1} in use"
    result = result + file_analyzer.analyze
  end

  logger.info "Found #{result.size} endpoints"
  result
end

def join_paths(*paths : String) : String
  File.join(paths)
end
