require "xml"
require "uri"
require "../../../models/analyzer"

module Analyzer::Specification
  class WSDL < Analyzer
    SOAP11_NS = "http://schemas.xmlsoap.org/wsdl/soap/"
    SOAP12_NS = "http://schemas.xmlsoap.org/wsdl/soap12/"

    alias FieldList = Array(String)
    alias BindingInfo = NamedTuple(port_type: String, soap_version: String, actions: Hash(String, String))

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

      element_fields = collect_element_fields(definitions)
      messages = collect_messages(definitions)
      port_types = collect_port_types(definitions)
      bindings = collect_bindings(definitions)

      emit_endpoints(definitions, source, bindings, port_types, messages, element_fields)
    end

    # Walks `wsdl:types` and indexes every named `xs:element` and
    # `xs:complexType` by local name → list of top-level field names. This
    # is what becomes the SOAP body param list per operation.
    private def collect_element_fields(definitions : XML::Node) : Hash(String, FieldList)
      element_fields = {} of String => FieldList
      types_node = find_child(definitions, "types")
      return element_fields unless types_node

      each_child(types_node, "schema") do |schema|
        each_child(schema, "element") do |elem|
          name = elem["name"]?
          next unless name
          fields = [] of String
          if complex_type = find_child(elem, "complexType")
            collect_sequence_fields(complex_type, fields)
          elsif type_attr = elem["type"]?
            # Reference to a named complexType — resolved in a second pass.
            element_fields[name] = [type_attr] of String
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
      element_fields.each do |name, fields|
        next unless fields.size == 1
        ref = strip_prefix(fields.first)
        next if ref == name
        if resolved = element_fields[ref]?
          element_fields[name] = resolved.dup unless resolved.size == 1 && strip_prefix(resolved.first) == name
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

    # `message name="..."` → local name of the element (or type) carried by
    # its first `part`. The element's name is what we later look up in
    # `element_fields` to expand body params.
    private def collect_messages(definitions : XML::Node) : Hash(String, String)
      messages = {} of String => String
      each_child(definitions, "message") do |msg|
        name = msg["name"]?
        next unless name
        part = find_child(msg, "part")
        next unless part
        if elem_ref = part["element"]?
          messages[name] = strip_prefix(elem_ref)
        elsif type_ref = part["type"]?
          messages[name] = strip_prefix(type_ref)
        end
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
              if element_name = messages[message_name]?
                if fields = element_fields[element_name]?
                  fields.each do |fname|
                    params << Param.new(fname, "", "json")
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
      rescue
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
