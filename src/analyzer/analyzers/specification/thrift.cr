require "../../engines/specification_engine"
require "../../../miniparsers/thrift_idl"

module Analyzer::Specification
  # Apache Thrift IDL services, represented the way the gRPC analyzer
  # represents a pure protobuf service: one `POST /<Service>/<function>`
  # endpoint per function with `protocol = "thrift"` and the function's
  # arguments as body params.
  #
  # The URL carries no namespace. Unlike a protobuf `package`, a Thrift
  # `namespace` is per target language and never reaches the wire — the
  # message header names only the function (or `Service:function` behind a
  # TMultiplexedProtocol).
  class Thrift < SpecificationEngine
    analyzer_for "thrift"

    TAGGER = "thrift_analyzer"

    alias Document = Noir::ThriftIdl::Document
    alias ThriftService = Noir::ThriftIdl::Service
    alias ThriftFunction = Noir::ThriftIdl::Function

    record SourcedFunction, function : ThriftFunction, path : String, origin : String?

    @documents = {} of String => Tuple(String, Document)

    def analyze
      return @result if CodeLocator.instance.all(Noir::LocatorKeys::THRIFT_IDL).empty?

      # A base service usually lives in an included file (often one with no
      # service of its own worth reporting, or none at all), so index every
      # `.thrift` in scope before resolving `extends`.
      CodeLocator.instance.files_by_extension(".thrift").each do |path|
        document_for(path)
      end

      each_spec_file(Noir::LocatorKeys::THRIFT_IDL) do |path|
        document = document_for(path)
        next unless document
        document.services.each do |service|
          emit_service(service, path, document)
        end
      end

      @result
    end

    private def document_for(path : String) : Document?
      key = File.expand_path(path)
      if cached = @documents[key]?
        return cached[1]
      end
      document = Noir::ThriftIdl.parse(read_file_content(path))
      @documents[key] = {path, document}
      document
    rescue IO::Error
      nil
    end

    private def emit_service(service : ThriftService, path : String, document : Document)
      seen = Set(String).new
      functions = [] of SourcedFunction
      service.functions.each do |function|
        next unless seen.add?(function.name)
        functions << SourcedFunction.new(function, path, nil)
      end
      collect_inherited(service, path, document, functions, seen, Set{"#{File.expand_path(path)}::#{service.name}"})

      functions.each do |sourced|
        @result << build_endpoint(service.name, sourced)
      end
    end

    # Appends the functions `service` inherits through `extends`, nearest
    # base first. A function the derived service already declares wins;
    # `visited` stops an `extends` cycle.
    private def collect_inherited(service : ThriftService, path : String, document : Document,
                                  functions : Array(SourcedFunction), seen : Set(String),
                                  visited : Set(String))
      base_name = service.extends
      return unless base_name

      resolved = resolve_service(base_name, path, document)
      return unless resolved
      base, base_path, base_document = resolved
      return unless visited.add?("#{File.expand_path(base_path)}::#{base.name}")

      base.functions.each do |function|
        next unless seen.add?(function.name)
        functions << SourcedFunction.new(function, base_path, base_name)
      end
      collect_inherited(base, base_path, base_document, functions, seen, visited)
    end

    # `extends Base` names a service in the same document;
    # `extends shared.Base` names one in the included document whose file is
    # `shared.thrift` (the Thrift compiler prefixes included symbols with the
    # included file's base name).
    private def resolve_service(name : String, path : String, document : Document) : Tuple(ThriftService, String, Document)?
      unless name.includes?('.')
        service = document.services.find { |candidate| candidate.name == name }
        return service ? {service, path, document} : nil
      end

      prefix, _, service_name = name.rpartition('.')
      included = included_document(prefix, path, document)
      return unless included
      included_path, included_document = included
      service = included_document.services.find { |candidate| candidate.name == service_name }
      service ? {service, included_path, included_document} : nil
    end

    # Resolves an include prefix to a parsed document. The include path is
    # tried relative to the including file first, as the compiler does; when
    # it was meant for an `-I` search directory instead, fall back to the one
    # scanned file with that base name (an ambiguous name resolves nowhere
    # rather than to an arbitrary file).
    private def included_document(prefix : String, path : String, document : Document) : Tuple(String, Document)?
      include_path = document.includes.find { |candidate| File.basename(candidate, ".thrift") == prefix }
      if include_path
        relative = File.expand_path(include_path, File.dirname(File.expand_path(path)))
        if found = @documents[relative]?
          return found
        end
      end

      basename = include_path ? File.basename(include_path) : "#{prefix}.thrift"
      matches = @documents.values.select { |entry| File.basename(entry[0]) == basename }
      matches.size == 1 ? matches.first : nil
    end

    # The field as declared minus its name — `1: required map<string, i32>`.
    # The id matters as much as the type: the binary, compact and JSON
    # protocols all key arguments by field id, not by name.
    private def field_declaration(field : Noir::ThriftIdl::Field) : String
      String.build do |io|
        if id = field.id
          io << id << ": "
        end
        if requiredness = field.requiredness
          io << requiredness << ' '
        end
        io << field.type
      end
    end

    private def build_endpoint(service_name : String, sourced : SourcedFunction) : Endpoint
      function = sourced.function
      params = function.args.map do |field|
        param = Param.new(field.name, "", "json")
        param.add_tag(Tag.new("thrift-field", field_declaration(field), TAGGER))
        param
      end

      details = Details.new(PathInfo.new(sourced.path, function.line))
      endpoint = Endpoint.new("/#{service_name}/#{function.name}", "POST", params, details)
      endpoint.protocol = "thrift"
      if function.oneway
        endpoint.add_tag(Tag.new("oneway", "Thrift oneway function: fire-and-forget, the server sends no response", TAGGER))
      end
      if origin = sourced.origin
        endpoint.add_tag(Tag.new("thrift-inherited", "Inherited from #{origin}", TAGGER))
      end
      endpoint
    end
  end
end
