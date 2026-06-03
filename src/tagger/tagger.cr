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
    mcp: {
      name:   "MCP Tagger",
      desc:   "Identifies Model Context Protocol endpoints",
      runner: McpTagger,
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
    pii: {
      name:   "PII Tagger",
      desc:   "Identifies endpoints handling personally identifiable information",
      runner: PiiTagger,
    },
    admin: {
      name:   "Admin Tagger",
      desc:   "Identifies administrative and privileged endpoints",
      runner: AdminTagger,
    },
    payment: {
      name:   "Payment Tagger",
      desc:   "Identifies payment and financial transaction endpoints",
      runner: PaymentTagger,
    },
    webhook: {
      name:   "Webhook Tagger",
      desc:   "Identifies inbound webhook and callback endpoints",
      runner: WebhookTagger,
    },
    crypto: {
      name:   "Crypto Tagger",
      desc:   "Identifies cryptographic operation endpoints (encryption, signing, hashing, key management)",
      runner: CryptoTagger,
    },
    debug: {
      name:   "Debug Tagger",
      desc:   "Identifies debug, diagnostic, and internal-only endpoints (debug consoles, profilers, actuator, pprof, internal APIs)",
      runner: DebugTagger,
    },
    api_docs: {
      name:   "API Docs Tagger",
      desc:   "Identifies API documentation/schema endpoints (Swagger, OpenAPI, GraphiQL, ReDoc, WSDL)",
      runner: ApiDocsTagger,
    },
    account_recovery: {
      name:   "Account Recovery Tagger",
      desc:   "Identifies credential-management and account-recovery endpoints (password reset/change, MFA/OTP, verification)",
      runner: AccountRecoveryTagger,
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
    spring_security: {
      name:   "Spring Security Tagger",
      desc:   "Identifies Spring security signals beyond auth (CSRF disabled, CORS policy, security headers, input validation)",
      runner: SpringSecurityTagger,
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
    go_security: {
      name:   "Go Security Tagger",
      desc:   "Identifies Go security middleware (CSRF, security headers, rate limiting, body-size limits)",
      runner: GoSecurityTagger,
    },
    rust_auth: {
      name:   "Rust Auth Tagger",
      desc:   "Identifies Rust authentication patterns (guards, extractors, middleware)",
      runner: RustAuthTagger,
    },
    rust_security: {
      name:   "Rust Security Tagger",
      desc:   "Identifies Rust framework security protections (CORS, rate limiting, security headers, body-size limits)",
      runner: RustSecurityTagger,
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
    rails_security: {
      name:   "Rails Security Tagger",
      desc:   "Identifies Rails controller security signals (CSRF protection, mass assignment, rate limiting)",
      runner: RailsSecurityTagger,
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
    fastendpoints_auth: {
      name:   "FastEndpoints Auth Tagger",
      desc:   "Identifies FastEndpoints authentication patterns (Roles, Permissions, Policies)",
      runner: FastEndpointsAuthTagger,
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
    hono_auth: {
      name:   "Hono Auth Tagger",
      desc:   "Identifies Hono authentication patterns (bearerAuth, jwt, basicAuth, custom middleware)",
      runner: HonoAuthTagger,
    },
    perl_auth: {
      name:   "Perl Auth Tagger",
      desc:   "Identifies Perl authentication patterns (Dancer2 Auth::Extensible, Mojolicious, Catalyst)",
      runner: PerlAuthTagger,
    },
  }

  def self.taggers
    HasTaggers
  end

  def self.framework_taggers
    HasFrameworkTaggers
  end

  def self.available_tagger_names : Array(String)
    names = [] of String
    HasTaggers.each_key { |name| names << name.to_s }
    HasFrameworkTaggers.each_key { |name| names << name.to_s }
    names << "all"
    names.sort
  end

  def self.unknown_tagger_names(use_taggers : String) : Array(String)
    requested = use_taggers.split(",").map(&.strip).reject(&.empty?)
    valid_names = available_tagger_names
    # Case-insensitive match: canonical names in `valid_names` are
    # lowercase. `--use-taggers Hunt` and `--use-taggers HUNT` were
    # rejected pre-fix even though the user clearly intended `hunt`;
    # `noir list taggers` doesn't communicate that the names are
    # case-sensitive either.
    requested.reject { |name| valid_names.includes?(name.downcase) }
  end

  def self.validate_tagger_names!(use_taggers : String)
    unknown = unknown_tagger_names(use_taggers)
    return if unknown.empty?

    raise ArgumentError.new("Unknown tagger(s): #{unknown.join(", ")}")
  end

  def self.run_tagger(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers : String)
    validate_tagger_names!(use_taggers)

    # Every entry in HasTaggers maps a tagger key to a runnable
    # Tagger subclass. The previous `class.to_s == "Class"` guard was
    # always true (Crystal class objects are instances of Class) and
    # therefore a no-op; instantiate directly.
    tagger_list = [] of Tagger
    HasTaggers.each_value do |tagger|
      tagger_list << tagger[:runner].new(options)
    end

    # Parsing use_taggers — normalize to lowercase so case-insensitive
    # input matches the lowercase canonical tagger names. Validation
    # (`validate_tagger_names!` above) uses the same shape.
    use_taggers_arr = use_taggers.split(",").map(&.strip.downcase)

    logger = build_logger(options)

    # Run taggers. A single tagger raising must not abort the rest of the
    # tagging pass (or, for framework taggers below, tear down the whole
    # program from inside a fiber) — degrade to "this tagger failed".
    tagger_list.each do |tagger|
      next unless use_taggers_arr.includes?(tagger.name) || use_taggers_arr.includes?("all")
      begin
        tagger.perform(endpoints)
      rescue ex
        logger.warning "Tagger '#{tagger.name}' failed: #{ex.message}"
      end
    end

    # Run framework taggers (tech-aware, only instantiated when matching endpoints exist)
    run_framework_taggers(endpoints, options, use_taggers_arr, logger)
  end

  private def self.build_logger(options : Hash(String, YAML::Any)) : NoirLogger
    NoirLogger.new(
      any_to_bool(options["debug"]),
      any_to_bool(options["verbose"]),
      any_to_bool(options["color"]),
      any_to_bool(options["nolog"])
    )
  end

  private def self.run_framework_taggers(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers_arr : Array(String), logger : NoirLogger)
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

        tagger_instance = tagger_info[:runner].new(options)
        next unless is_all || use_taggers_arr.includes?(tagger_instance.name)

        # Bind to local variables to ensure each fiber captures its own copy
        local_instance = tagger_instance
        local_endpoints = matching_endpoints

        wg.spawn do
          begin
            local_instance.perform(local_endpoints)
          rescue ex
            logger.warning "Framework tagger '#{local_instance.name}' failed: #{ex.message}"
          end
        end
      end
    end
  end
end
