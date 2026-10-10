require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/java_type_model_extractor_ts"
require "../../../miniparsers/java_parameter_extractor_ts"
require "../../../utils/url_path"
require "../../../detector/detectors/java/spring_data_rest"

module Analyzer::Java
  # Spring Data REST exports every public repository interface as a CRUD +
  # search API with no controller code. Routes come from the repository
  # *types*: `@RepositoryRestResource(path=)` only renames them.
  class SpringDataRest < Analyzer
    analyzer_for "java_spring_data_rest"

    include JavaEngine

    alias Model = Noir::TreeSitterJavaTypeModel

    # Spring Data base interfaces, mapped to what they export: 2 = full
    # CRUD, 1 = collection GET only, 0 = only what the interface declares.
    # `PagingAndSortingRepository` extends `CrudRepository` up to Spring
    # Data 2.x and is counted as CRUD; on 3.x it is paging-only, which
    # over-reports the write verbs of a repository that extends nothing else.
    BASE_LEVELS = {
      "Repository"                     => 0,
      "ListPagingAndSortingRepository" => 1,
      "CrudRepository"                 => 2,
      "ListCrudRepository"             => 2,
      "PagingAndSortingRepository"     => 2,
      "JpaRepository"                  => 2,
      "MongoRepository"                => 2,
      "CassandraRepository"            => 2,
      "Neo4jRepository"                => 2,
      "KeyValueRepository"             => 2,
      "CouchbaseRepository"            => 2,
      "ElasticsearchRepository"        => 2,
    }

    CRUD_METHODS = Set{
      "findAll", "findById", "findAllById", "existsById", "count",
      "save", "saveAll", "saveAndFlush", "saveAllAndFlush",
      "delete", "deleteById", "deleteAll", "deleteAllById", "deleteAllInBatch", "deleteAllByIdInBatch",
      "flush", "getById", "getOne", "getReferenceById",
    }
    # Data REST exports DELETE through either method, so hiding it takes both.
    DELETE_METHODS = Set{"delete", "deleteById"}

    QUERY_METHOD_RE = /^(?:find|read|get|query|search|stream|count|exists|delete|remove)[A-Z]/
    SOURCE_MARKER   = Regex.union("org.springframework.data.rest")
    INTERFACE_GATE  = /\binterface\s+\w+[^{]*\bextends\b/
    BUILD_FILES     = %w[pom.xml build.gradle build.gradle.kts]
    MAX_BASE_DEPTH  = 8

    private record Candidate, path : String, decl : Model::TypeDecl, dto_index : Noir::TreeSitterJavaDtoIndex::Index, owned : Bool

    def analyze
      # Build-file directory -> whether a build file there pulls in Data
      # REST. A repository belongs to its nearest build file, so a sibling
      # module with plain Spring Data JPA exports nothing.
      build_dirs = Hash(String, Bool).new(false)
      BUILD_FILES.each do |name|
        get_files_by_basename(name).each do |file|
          isolating_file_errors(file) do
            dir = File.dirname(file) + "/"
            build_dirs[dir] = build_dirs[dir] || content_matches?(read_file_content(file), Detector::Java::SpringDataRest::BUILD_MARKERS)
          end
        end
      end

      dto_builder = Noir::TreeSitterJavaDtoIndex.new
      interfaces = Hash(String, Model::TypeDecl).new
      candidates = [] of Candidate
      get_files_by_extension(".java").each do |path|
        next if JavaEngine.test_path?(base_relative_path(path))
        isolating_file_errors(path) do
          content = read_file_content(path)
          next unless content_matches?(content, INTERFACE_GATE)

          owned = content_matches?(content, SOURCE_MARKER) || owned_by_build?(path, build_dirs)
          Noir::TreeSitter.parse_java(content) do |root|
            dto_index = nil.as(Noir::TreeSitterJavaDtoIndex::Index?)
            Model.extract_from(root, content).each do |decl|
              next if decl.kind != "interface" || decl.supertypes.empty?
              interfaces[decl.name] ||= decl
              dto_index ||= dto_builder.build_for_with_root(path, content, root)
              candidates << Candidate.new(path, decl, dto_index, owned)
            end
          end
        end
      end
      # Data REST pulled in from somewhere the nearest-build-file rule
      # cannot see (a parent POM, a sibling app module, a Gradle convention
      # plugin): the detector fired, so keep every repository.
      owned = candidates.select(&.owned)
      owned = candidates if owned.empty?

      configs = Hash(String, Hash(String, String)).new
      owned.each do |candidate|
        isolating_file_errors(candidate.path) do
          root = project_root_for(candidate.path)
          config = configs[root] ||= spring_config_values_for(root)
          emit_repository(candidate, interfaces, config)
        end
      end

      @result
    end

    # No build file above `path` means the scan holds bare sources; the
    # detector already saw Data REST, so they count.
    private def owned_by_build?(path : String, build_dirs : Hash(String, Bool)) : Bool
      nearest = build_dirs.keys.select { |dir| path.starts_with?(dir) }.max_by?(&.size)
      nearest.nil? || build_dirs[nearest]
    end

    # `spring.data.rest.detection-strategy`; the default exports public
    # interfaces and annotated ones.
    private def exported?(decl : Model::TypeDecl, type_annotation : Model::Annotation?, config : Hash(String, String)) : Bool
      return false if type_annotation.try(&.string("exported")) == "false"
      is_public = decl.modifiers.includes?("public")
      strategy = config["spring.data.rest.detection-strategy"]? || config["spring.data.rest.detectionStrategy"]? || ""
      case strategy.downcase.tr("_", "-")
      when "all"                             then true
      when "visibility"                      then is_public
      when "annotated", "explicit-annotated" then !type_annotation.nil?
      else                                        is_public || !type_annotation.nil?
      end
    end

    private def emit_repository(candidate : Candidate, interfaces : Hash(String, Model::TypeDecl), config : Hash(String, String))
      decl = candidate.decl
      return if decl.annotation("NoRepositoryBean")
      type_annotation = decl.annotation("RepositoryRestResource") || decl.annotation("RestResource")
      return unless exported?(decl, type_annotation, config)
      return unless resolved = resolve_repository(decl.supertypes, interfaces, 0)
      level, entity, inherited = resolved
      return if entity.empty?

      entity = Model.simple_type_name(entity)
      resource = type_annotation.try(&.string("path")) || SpringDataRest.pluralize(uncapitalize(entity))
      base = Noir::URLPath.join_absorbing(
        normalize_optional_path(config["server.servlet.context-path"]?),
        normalize_optional_path(config["spring.data.rest.base-path"]? || config["spring.data.rest.basePath"]?))
      collection = Noir::URLPath.join_rooted(base, resource.strip('/'))
      item = "#{collection}/{id}"

      # Own declarations override the ones on user base repositories.
      methods = (decl.methods + inherited).uniq(&.name)
      declared = methods.map(&.name).to_set
      hidden = methods.select { |method| rest_annotation(method).try(&.string("exported")) == "false" }.map(&.name).to_set
      deletes = level >= 2 ? DELETE_METHODS : DELETE_METHODS & declared

      collection_get = (level >= 1 || declared.includes?("findAll")) && !hidden.includes?("findAll")
      item_get = (level >= 2 || declared.includes?("findById")) && !hidden.includes?("findById")
      save = (level >= 2 || declared.includes?("save")) && !hidden.includes?("save")
      delete = !deletes.empty? && !deletes.subset_of?(hidden)

      line = decl.line + 1
      body = (candidate.dto_index[entity]? || [] of Noir::TreeSitterJavaParameterExtractor::FieldInfo).map { |field| Param.new(field.name, "", "json") }
      add(collection, "GET", line, candidate.path, %w[page size sort].map { |name| Param.new(name, "", "query") }) if collection_get
      add(collection, "POST", line, candidate.path, body) if save
      add(item, "GET", line, candidate.path) if item_get
      if save
        add(item, "PUT", line, candidate.path, body)
        add(item, "PATCH", line, candidate.path, body)
      end
      add(item, "DELETE", line, candidate.path) if delete

      searches = methods.select do |method|
        !CRUD_METHODS.includes?(method.name) && !hidden.includes?(method.name) &&
          !method.modifiers.includes?("default") && !method.modifiers.includes?("static") &&
          (method.name.matches?(QUERY_METHOD_RE) || method.annotations.any? { |ann| ann.name == "Query" })
      end
      return if searches.empty?

      search_root = "#{collection}/search"
      add(search_root, "GET", line, candidate.path)
      searches.each do |method|
        name = rest_annotation(method).try(&.string("path")) || method.name
        # Inherited finders point at the repository, not the base file.
        method_line = decl.methods.includes?(method) ? method.line + 1 : line
        add("#{search_root}/#{name.strip('/')}", "GET", method_line, candidate.path, search_params(method))
      end
    end

    # `{level, entity, methods}`: the strongest Spring Data base reached
    # through `supertypes`, following user-declared base repositories and
    # collecting the methods they declare; nil when none is a repository.
    private def resolve_repository(supertypes : Array(String), interfaces : Hash(String, Model::TypeDecl),
                                   depth : Int32) : Tuple(Int32, String, Array(Model::Method))?
      best = nil.as(Tuple(Int32, String)?)
      methods = [] of Model::Method
      supertypes.each do |type|
        name = Model.simple_type_name(type)
        entity = Model.type_arguments(type).first? || ""
        found = if level = BASE_LEVELS[name]?
                  {level, entity}
                elsif depth < MAX_BASE_DEPTH && (parent = interfaces[name]?)
                  resolve_repository(parent.supertypes, interfaces, depth + 1).try do |deep|
                    methods.concat(parent.methods).concat(deep[2])
                    {deep[0], entity.empty? ? deep[1] : entity}
                  end
                end
        best = found if found && (best.nil? || found[0] > best[0])
      end
      best.try { |result| {result[0], result[1], methods} }
    end

    private def search_params(method : Model::Method) : Array(Param)
      params = [] of Param
      method.params.each do |param|
        case Model.simple_type_name(param.type)
        when "Pageable" then %w[page size sort].each { |name| params << Param.new(name, "", "query") }
        when "Sort"     then params << Param.new("sort", "", "query")
        else
          name = param.annotations.find { |ann| ann.name == "Param" }.try(&.string) || param.name
          params << Param.new(name, "", "query")
        end
      end
      params
    end

    private def rest_annotation(method : Model::Method) : Model::Annotation?
      method.annotations.find { |ann| ann.name == "RestResource" }
    end

    private def add(url : String, verb : String, line : Int32, path : String, params = [] of Param)
      @result << Endpoint.new(url, verb, params, Details.new(PathInfo.new(path, line)))
    end

    private def uncapitalize(name : String) : String
      name.empty? ? name : name[0].downcase + name[1..]
    end

    # `{pattern, replacement}` turning each of `words` (all ending in
    # `singular`) into its plural.
    def self.category(words : Array(String), singular : String, plural : String) : Tuple(Regex, String)
      {Regex.new("(#{words.map(&.rchop(singular)).join('|')})#{singular}\\z", Regex::Options::IGNORE_CASE), "\\1#{plural}"}
    end

    # Evo Inflector 1.3's anglicized `English.plural`, which Spring Data REST
    # derives the default path with: every rule is a case-insensitive suffix
    # match and the first one that matches wins. `person` is not irregular
    # there, so `Person` maps to `/persons`.
    PLURAL_RULES = [
      category(%w[fish ois sheep deer pox itis bison flounder pliers bream gallows proceedings breeches graffiti
        rabies britches headquarters salmon carp herpes scissors chassis high-jinks sea-bass clippers homework
        series cod innings shears contretemps jackanapes species corps mackerel swine debris measles trout
        diabetes mews tuna djinn mumps whiting eland news wildebeest elk pincers sugar], "", ""),
      {/(c)hild\z/i, "\\1hildren"}, {/(e)phemeris\z/i, "\\1phemerides"}, {/(m)ongoose\z/i, "\\1ongoose"},
      {/(m)ythos\z/i, "\\1ythoi"}, {/(s)oliloquy\z/i, "\\1oliloquies"}, {/(t)rilby\z/i, "\\1rilbys"},
      {/(g)enus\z/i, "\\1enera"}, {/(q)uiz\z/i, "\\1uizzes"}, {/(b)eef\z/i, "\\1eefs"},
      {/(b)rother\z/i, "\\1rothers"}, {/(c)ow\z/i, "\\1ows"}, {/(g)enie\z/i, "\\1enies"},
      {/(m)oney\z/i, "\\1oneys"}, {/(o)ctopus\z/i, "\\1ctopuses"}, {/(o)pus\z/i, "\\1puses"},
      # Evo's other `-man` exceptions are capitalized and never match.
      category(%w[human], "", "s"),
      {/man\z/i, "men"}, {/([lm])ouse\z/i, "\\1ice"}, {/tooth\z/i, "teeth"}, {/goose\z/i, "geese"},
      {/foot\z/i, "feet"}, {/zoon\z/i, "zoa"}, {/([csx])is\z/i, "\\1es"},
      category(%w[codex murex silex], "ex", "ices"),
      category(%w[radix helix], "ix", "ices"),
      category(%w[bacterium agendum desideratum erratum stratum datum ovum extremum candelabrum], "um", "a"),
      category(%w[criterion perihelion aphelion phenomenon prolegomenon noumenon organon asyndeton hyperbaton], "on", "a"),
      category(%w[alumna alga vertebra persona], "a", "ae"),
      category(%w[alumnus alveolus bacillus bronchus locus nucleus stimulus meniscus thesaurus], "us", "i"),
      {/([cs]h|[zx])\z/i, "\\1es"},
      category(%w[acropolis chaos lens aegis cosmos mantis alias dais marquis asbestos digitalis metropolis atlas
        epidermis pathos bathos ethos pelvis bias gas polis caddis glottis rhinoceros cannabis sassafras canvas
        ibis trellis iris clitoris apparatus impetus prospectus cantus nexus sinus coitus plexus status hiatus], "", "es"),
      {/(us)\z/i, "\\1es"},
      category(%w[anathema enema oedema bema enigma sarcoma carcinoma gumma schema charisma lemma soma diploma
        lymphoma stigma dogma magma stoma drama melisma trauma edema miasma], "", "s"),
      {/ss\z/i, "sses"},
      {/([aeo]l)f\z/i, "\\1ves"}, {/([^d]ea)f\z/i, "\\1ves"}, {/(ar)f\z/i, "\\1ves"}, {/([nlw]i)fe\z/i, "\\1ves"},
      {/([aeiou]y)\z/i, "\\1s"}, {/y\z/i, "ies"},
      category(%w[solo soprano basso alto contralto tempo piano virtuoso albino archipelago armadillo commando
        crescendo fiasco ditto dynamo embryo ghetto guano inferno jumbo lumbago magneto manifesto medico octavo
        photo pro quarto canto lingo generalissimo stylo rhino casino auto macro zero todo], "o", "os"),
      {/([aeiou]o)\z/i, "\\1s"}, {/o\z/i, "oes"},
      {/(ul)um\z/i, "\\1a"},
      {/s\z/i, "ses"},
    ]

    def self.pluralize(word : String) : String
      return word if word.empty?
      PLURAL_RULES.each { |(pattern, replacement)| return word.sub(pattern, replacement) if word.matches?(pattern) }
      "#{word}s"
    end
  end
end
