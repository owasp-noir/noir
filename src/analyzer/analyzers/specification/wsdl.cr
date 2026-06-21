require "xml"
require "uri"
require "../../../models/analyzer"

module Analyzer::Specification
  class WSDL < Analyzer
    SOAP12_NS        = "http://schemas.xmlsoap.org/wsdl/soap12/"
    MAX_IMPORT_DEPTH = 8

    alias FieldList = Array(String)
    alias BindingInfo = NamedTuple(port_type: String, soap_version: String, actions: Hash(String, String))
    # A `wsdl:part` carries either a document-style `element` reference or
    # an RPC-style `type` reference. `name` is the part's own name, which
    # becomes the parameter for RPC parts whose type is a built-in scalar.
    alias PartRef = NamedTuple(name: String, ref: String, is_element: Bool)

    def analyze
      locator = CodeLocator.instance
      wsdl_specs = locator.all("wsdl-spec")
      return @result unless wsdl_specs.is_a?(Array(String))

      wsdl_specs.each do |path|
        next unless File.exists?(path)
        begin
          content = read_file_content(path)
          parse_wsdl(content, path)
        rescue e
          @logger.debug "Failed to parse WSDL #{path}: #{e.message}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def parse_wsdl(content : String, source : String)
      doc = XML.parse(content)
      definitions = find_child(doc, "definitions")
      return unless definitions

      # WSDL is commonly split across files: the `service`/`binding` live in
      # one document and the `portType`/`message`/`types` in another, wired
      # together by `<wsdl:import>`. Without resolving those imports a
      # binding can't find its portType and every operation is dropped
      # (false negative). Merge the definitions of all reachable imports.
      docs = [doc] # keep parsed documents alive while their nodes are read
      all_defs = [definitions]
      load_imports(definitions, File.dirname(source), all_defs, docs, Set(String).new, 0)

      element_fields = {} of String => FieldList
      messages = {} of String => Array(PartRef)
      port_types = {} of String => Hash(String, String)
      bindings = {} of String => BindingInfo
      all_defs.each do |defs|
        element_fields.merge!(collect_element_fields(defs))
        messages.merge!(collect_messages(defs))
        port_types.merge!(collect_port_types(defs))
        bindings.merge!(collect_bindings(defs))
      end

      # Emit only from the services declared in this document; an imported
      # file that also declares a service is analyzed on its own pass.
      emit_endpoints(definitions, source, bindings, port_types, messages, element_fields)
    end

    # Recursively loads every `<wsdl:import location="...">` reachable from
    # `definitions`, appending each imported `<definitions>` node to
    # `all_defs` (and its document to `docs`, which must outlive the nodes).
    # Remote and already-visited locations are skipped, and a depth cap
    # guards against pathological or cyclic import graphs.
    private def load_imports(definitions : XML::Node, base_dir : String, all_defs : Array(XML::Node), docs : Array(XML::Node), visited : Set(String), depth : Int32)
      return if depth >= MAX_IMPORT_DEPTH

      each_child(definitions, "import") do |imp|
        loc = imp["location"]?
        next unless loc
        next if loc.empty? || loc.starts_with?("http://") || loc.starts_with?("https://")

        path = File.expand_path(loc, base_dir)
        next if visited.includes?(path)
        visited << path
        next unless File.exists?(path)

        begin
          sub_doc = XML.parse(read_file_content(path))
          sub_def = find_child(sub_doc, "definitions")
          next unless sub_def
          docs << sub_doc
          all_defs << sub_def
          load_imports(sub_def, File.dirname(path), all_defs, docs, visited, depth + 1)
        rescue e
          @logger.debug "Failed to load WSDL import #{path}: #{e.message}"
        end
      end
    end

    # Walks `wsdl:types` and indexes every named `xs:element` and
    # `xs:complexType` by local name → list of top-level field names. This
    # is what becomes the SOAP body param list per operation.
    private def collect_element_fields(definitions : XML::Node) : Hash(String, FieldList)
      element_fields = {} of String => FieldList
      types_node = find_child(definitions, "types")
      return element_fields unless types_node

      # Track type references explicitly instead of overloading "a 1-element
      # array means a reference" — a real single-field structure was being
      # mistaken for a reference and overwritten with an unrelated type's fields.
      references = {} of String => String

      each_child(types_node, "schema") do |schema|
        each_child(schema, "element") do |elem|
          name = elem["name"]?
          next unless name
          fields = [] of String
          if complex_type = find_child(elem, "complexType")
            collect_sequence_fields(complex_type, fields)
          elsif type_attr = elem["type"]?
            # Reference to a named complexType — resolved in a second pass.
            references[name] = strip_prefix(type_attr)
            element_fields[name] = [] of String
            next
          end
          element_fields[name] = fields
        end

        each_child(schema, "complexType") do |ct|
          name = ct["name"]?
          next unless name
          fields = [] of String
          collect_sequence_fields(ct, fields)
          element_fields[name] = fields
        end
      end

      # Second pass: elements that referenced a named type get its fields.
      references.each do |name, ref|
        next if ref == name
        if resolved = element_fields[ref]?
          element_fields[name] = resolved.dup
        end
      end

      element_fields
    end

    private def collect_sequence_fields(node : XML::Node, fields : FieldList)
      container = find_child(node, "sequence") || find_child(node, "all")
      return unless container
      each_child(container, "element") do |f|
        if name = f["name"]?
          fields << name
        end
      end
    end

    # `message name="..."` → every `part` it carries. A message can declare
    # multiple parts (each an independent RPC argument), so all are kept —
    # reading only the first dropped the rest. Each part records whether it
    # points at an `element` (document style) or a `type` (RPC style); the
    # distinction drives how params are expanded at emit time.
    private def collect_messages(definitions : XML::Node) : Hash(String, Array(PartRef))
      messages = {} of String => Array(PartRef)
      each_child(definitions, "message") do |msg|
        name = msg["name"]?
        next unless name
        parts = [] of PartRef
        each_child(msg, "part") do |part|
          part_name = part["name"]? || ""
          if elem_ref = part["element"]?
            parts << {name: part_name, ref: strip_prefix(elem_ref), is_element: true}
          elsif type_ref = part["type"]?
            parts << {name: part_name, ref: strip_prefix(type_ref), is_element: false}
          end
        end
        messages[name] = parts
      end
      messages
    end

    # portType name → (operation name → input message local name).
    private def collect_port_types(definitions : XML::Node) : Hash(String, Hash(String, String))
      port_types = {} of String => Hash(String, String)
      each_child(definitions, "portType") do |pt|
        pt_name = pt["name"]?
        next unless pt_name
        ops = {} of String => String
        each_child(pt, "operation") do |op|
          op_name = op["name"]?
          next unless op_name
          if input = find_child(op, "input")
            if msg_ref = input["message"]?
              ops[op_name] = strip_prefix(msg_ref)
            end
          end
        end
        port_types[pt_name] = ops
      end
      port_types
    end

    # binding name → port type ref, soap version, and per-operation
    # soapAction header values.
    private def collect_bindings(definitions : XML::Node) : Hash(String, BindingInfo)
      bindings = {} of String => BindingInfo
      each_child(definitions, "binding") do |b|
        b_name = b["name"]?
        next unless b_name
        pt_ref = b["type"]?
        next unless pt_ref

        soap_version = detect_soap_version(b)

        actions = {} of String => String
        each_child(b, "operation") do |op|
          op_name = op["name"]?
          next unless op_name
          if soap_op = find_child(op, "operation")
            actions[op_name] = soap_op["soapAction"]? || ""
          else
            actions[op_name] = ""
          end
        end
        bindings[b_name] = {port_type: strip_prefix(pt_ref), soap_version: soap_version, actions: actions}
      end
      bindings
    end

    # Detects SOAP 1.2 by the presence of a soap12-namespaced `<binding>`
    # child; everything else defaults to SOAP 1.1 (the vast majority).
    private def detect_soap_version(binding : XML::Node) : String
      binding.children.each do |child|
        next unless child.element? && child.name == "binding"
        if (ns = child.namespace) && ns.href == SOAP12_NS
          return "1.2"
        end
      end
      "1.1"
    end

    private def emit_endpoints(definitions, source, bindings, port_types, messages, element_fields)
      each_child(definitions, "service") do |service|
        each_child(service, "port") do |port|
          binding_ref = port["binding"]?
          next unless binding_ref
          binding_info = bindings[strip_prefix(binding_ref)]?
          next unless binding_info

          location = address_location(port)
          port_ops = port_types[binding_info[:port_type]]?
          next unless port_ops

          binding_info[:actions].each do |op_name, soap_action|
            params = soap_headers(soap_action, binding_info[:soap_version])

            if message_name = port_ops[op_name]?
              if parts = messages[message_name]?
                parts.each do |part|
                  if fields = element_fields[part[:ref]]?
                    # Known element/complexType: expand its top-level fields.
                    fields.each { |fname| add_body_param(params, fname) }
                  elsif !part[:is_element] && !part[:name].empty?
                    # RPC part typed as a built-in scalar (`xsd:string`,
                    # `xsd:int`, …): the part name is itself the parameter.
                    add_body_param(params, part[:name])
                  end
                end
              end
            end

            url = endpoint_url(location, op_name)
            details = Details.new(PathInfo.new(source))
            @result << Endpoint.new(url, "POST", params, details)
          end
        end
      end
    end

    private def address_location(port : XML::Node) : String
      port.children.each do |child|
        next unless child.element? && child.name == "address"
        if loc = child["location"]?
          return loc
        end
      end
      ""
    end

    # Real SOAP servers route every operation through the same URL and
    # dispatch on `SOAPAction` — but Noir's downstream pipeline keys
    # endpoints by (method, URL), so collapsing them there would merge
    # all operations and erase the per-operation body/header shape. We
    # synthesize a per-operation path (`{service_path}/{Operation}`) to
    # keep each operation independently testable; the real wire-level
    # dispatch is still represented by the preserved `SOAPAction`
    # header param.
    private def endpoint_url(location : String, op_name : String) : String
      base = base_path(location).rstrip('/')
      "#{base}/#{op_name}"
    end

    private def base_path(location : String) : String
      return "" if location.empty?
      begin
        uri = URI.parse(location)
        if uri.scheme && uri.host
          return uri.path || ""
        end
      rescue e
        logger.debug "Failed to parse WSDL location '#{location}': #{e}"
      end
      location
    end

    # SOAP transport is HTTP POST with two mandatory headers:
    # `SOAPAction` (the dispatch key SOAP 1.1 servers route on) and a
    # SOAP-version-specific `Content-Type`. The `soap` tagger picks up
    # `SOAPAction` and marks the endpoint as SOAP.
    private def soap_headers(soap_action : String, soap_version : String) : Array(Param)
      content_type = soap_version == "1.2" ? "application/soap+xml; charset=utf-8" : "text/xml; charset=utf-8"
      [
        Param.new("SOAPAction", soap_action, "header"),
        Param.new("Content-Type", content_type, "header"),
      ]
    end

    # Multi-part messages and shared field names can produce the same
    # body param twice; keep the SOAP body param list unique.
    private def add_body_param(params : Array(Param), name : String)
      param = Param.new(name, "", "json")
      params << param unless params.includes?(param)
    end

    private def strip_prefix(qname : String) : String
      if idx = qname.index(':')
        qname[(idx + 1)..]
      else
        qname
      end
    end

    private def find_child(node : XML::Node, local_name : String) : XML::Node?
      node.children.each do |c|
        return c if c.element? && c.name == local_name
      end
      nil
    end

    private def each_child(node : XML::Node, local_name : String, &)
      node.children.each do |c|
        yield c if c.element? && c.name == local_name
      end
    end
  end
end
