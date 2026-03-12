require "./taggers/*"
require "./framework_taggers/**"
require "../models/tagger"
require "../models/framework_tagger"

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
  }

  def self.taggers
    HasTaggers
  end

  def self.framework_taggers
    HasFrameworkTaggers
  end

  def self.run_tagger(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers : String)
    tagger_list = [] of Tagger # This will hold instances of taggers

    # Define taggers by creating instances
    # Assuming HuntParamTagger is defined and is the only tagger
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

    # Run framework taggers
    run_framework_taggers(endpoints, options, use_taggers_arr)
  end

  private def self.run_framework_taggers(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers_arr : Array(String))
    # Group endpoints by technology
    endpoints_by_tech = Hash(String, Array(Endpoint)).new

    endpoints.each do |endpoint|
      tech = endpoint.details.technology
      next if tech.nil?
      endpoints_by_tech[tech] ||= [] of Endpoint
      endpoints_by_tech[tech] << endpoint
    end

    return if endpoints_by_tech.empty?

    HasFrameworkTaggers.each_value do |tagger_info|
      instance = tagger_info[:runner].new(options)

      next unless use_taggers_arr.includes?(instance.name) || use_taggers_arr.includes?("all")

      # Get endpoints matching this tagger's target technologies
      matching_endpoints = [] of Endpoint
      tagger_info[:runner].target_techs.each do |tech|
        if endpoints_by_tech.has_key?(tech)
          matching_endpoints.concat(endpoints_by_tech[tech])
        end
      end

      next if matching_endpoints.empty?

      instance.perform(matching_endpoints)
    end
  end
end
