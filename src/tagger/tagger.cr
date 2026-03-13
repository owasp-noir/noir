require "./taggers/*"
require "./framework_taggers/**"
require "../models/tagger"
require "../models/framework_tagger"
require "wait_group"

module NoirTaggers
  HasTaggers = {
    hunt: {
      name:   "HuntParam Tagger",
      desc:   "Identifies common parameters vulnerable to certain vulnerability classes",
      runner: HuntParamTagger,
    },
    oauth: {
      name:   "OAuth Tagger",
      desc:   "Identifies OAuth endpoints",
      runner: OAuthTagger,
    },
    cors: {
      name:   "CORS Tagger",
      desc:   "Identifies CORS endpoints",
      runner: CorsTagger,
    },
    soap: {
      name:   "SOAP Tagger",
      desc:   "Identifies SOAP endpoints",
      runner: SoapTagger,
    },
    websocket: {
      name:   "Websocket Tagger",
      desc:   "Identifies Websocket endpoints",
      runner: WebsocketTagger,
    },
    graphql: {
      name:   "GraphQL Tagger",
      desc:   "Identifies GraphQL endpoints",
      runner: GraphqlTagger,
    },
    jwt: {
      name:   "JWT Tagger",
      desc:   "Identifies JWT authentication endpoints",
      runner: JwtTagger,
    },
    file_upload: {
      name:   "FileUpload Tagger",
      desc:   "Identifies file upload endpoints",
      runner: FileUploadTagger,
    },
  }

  HasFrameworkTaggers = {
    django_auth: {
      name:   "Django Auth Tagger",
      desc:   "Identifies Django authentication patterns (decorators, mixins, DRF permissions)",
      runner: DjangoAuthTagger,
    },
    spring_auth: {
      name:   "Spring Auth Tagger",
      desc:   "Identifies Spring Security patterns (annotations, security config)",
      runner: SpringAuthTagger,
    },
    express_auth: {
      name:   "Express Auth Tagger",
      desc:   "Identifies Express.js authentication patterns (Passport, JWT, auth middleware)",
      runner: ExpressAuthTagger,
    },
    go_auth: {
      name:   "Go Auth Tagger",
      desc:   "Identifies Go authentication patterns (middleware, JWT, session)",
      runner: GoAuthTagger,
    },
    rust_auth: {
      name:   "Rust Auth Tagger",
      desc:   "Identifies Rust authentication patterns (guards, extractors, middleware)",
      runner: RustAuthTagger,
    },
    flask_auth: {
      name:   "Flask Auth Tagger",
      desc:   "Identifies Flask authentication patterns (flask-login, flask-jwt, flask-httpauth)",
      runner: FlaskAuthTagger,
    },
    fastapi_auth: {
      name:   "FastAPI Auth Tagger",
      desc:   "Identifies FastAPI authentication patterns (Depends, Security, OAuth2)",
      runner: FastAPIAuthTagger,
    },
    python_misc_auth: {
      name:   "Python Misc Auth Tagger",
      desc:   "Identifies Sanic/Tornado authentication patterns",
      runner: PythonMiscAuthTagger,
    },
    ruby_auth: {
      name:   "Ruby Auth Tagger",
      desc:   "Identifies Ruby authentication patterns (Devise, Pundit, CanCanCan, Warden)",
      runner: RubyAuthTagger,
    },
    php_auth: {
      name:   "PHP Auth Tagger",
      desc:   "Identifies PHP authentication patterns (Laravel, Symfony, CakePHP)",
      runner: PhpAuthTagger,
    },
    nestjs_auth: {
      name:   "NestJS Auth Tagger",
      desc:   "Identifies NestJS authentication patterns (Guards, decorators)",
      runner: NestjsAuthTagger,
    },
    js_misc_auth: {
      name:   "JS Misc Auth Tagger",
      desc:   "Identifies Fastify/Koa/Restify authentication patterns",
      runner: JsMiscAuthTagger,
    },
    aspnet_auth: {
      name:   "ASP.NET Auth Tagger",
      desc:   "Identifies ASP.NET authentication patterns ([Authorize], policies)",
      runner: AspnetAuthTagger,
    },
    elixir_auth: {
      name:   "Elixir Auth Tagger",
      desc:   "Identifies Phoenix/Plug authentication patterns (plugs, Guardian, Pow)",
      runner: ElixirAuthTagger,
    },
    ktor_auth: {
      name:   "Ktor Auth Tagger",
      desc:   "Identifies Ktor authentication patterns (authenticate blocks, principals)",
      runner: KtorAuthTagger,
    },
    java_misc_auth: {
      name:   "Java Misc Auth Tagger",
      desc:   "Identifies Vert.x/Armeria/JSP authentication patterns",
      runner: JavaMiscAuthTagger,
    },
    swift_auth: {
      name:   "Swift Auth Tagger",
      desc:   "Identifies Vapor/Kitura/Hummingbird authentication patterns",
      runner: SwiftAuthTagger,
    },
    scala_auth: {
      name:   "Scala Auth Tagger",
      desc:   "Identifies Play/Akka/Scalatra authentication patterns",
      runner: ScalaAuthTagger,
    },
    crystal_auth: {
      name:   "Crystal Auth Tagger",
      desc:   "Identifies Crystal framework authentication patterns (Kemal, Amber, Lucky)",
      runner: CrystalAuthTagger,
    },
  }

  def self.taggers
    HasTaggers
  end

  def self.framework_taggers
    HasFrameworkTaggers
  end

  def self.run_tagger(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers : String)
    tagger_list = [] of Tagger

    HasTaggers.each_value do |tagger|
      if tagger[:runner].class.to_s == "Class"
        instance = tagger[:runner].new(options)
        tagger_list << instance
      end
    end

    # Parsing use_taggers
    use_taggers_arr = use_taggers.split(",")
    use_taggers_arr = use_taggers_arr.map(&.strip)

    # Run taggers
    tagger_list.each do |tagger|
      tagger.perform(endpoints) if use_taggers_arr.includes?(tagger.name) || use_taggers_arr.includes?("all")
    end

    # Run framework taggers (tech-aware, only instantiated when matching endpoints exist)
    run_framework_taggers(endpoints, options, use_taggers_arr)
  end

  private def self.run_framework_taggers(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers_arr : Array(String))
    # Group endpoints by technology for efficient dispatch
    endpoints_by_tech = Hash(String, Array(Endpoint)).new

    endpoints.each do |endpoint|
      tech = endpoint.details.technology
      next if tech.nil?
      endpoints_by_tech[tech] ||= [] of Endpoint
      endpoints_by_tech[tech] << endpoint
    end

    return if endpoints_by_tech.empty?

    is_all = use_taggers_arr.includes?("all")

    # Collect tagger work items, then run in parallel
    WaitGroup.wait do |wg|
      HasFrameworkTaggers.each_value do |tagger_info|
        target_techs = tagger_info[:runner].target_techs
        matching_endpoints = [] of Endpoint
        target_techs.each do |tech|
          if endpoints_by_tech.has_key?(tech)
            matching_endpoints.concat(endpoints_by_tech[tech])
          end
        end

        next if matching_endpoints.empty?

        instance = tagger_info[:runner].new(options)
        next unless is_all || use_taggers_arr.includes?(instance.name)

        wg.spawn do
          instance.perform(matching_endpoints)
        end
      end
    end
  end
end
