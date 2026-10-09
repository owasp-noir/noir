require "../../engines/specification_engine"
require "../../../utils/http_symbols"
require "../../../utils/json"

module Analyzer::Specification
  # Parses Hurl (`.hurl`) request files.
  #
  # An entry starts with a `METHOD url` line, followed by header lines,
  # `[Section]` blocks of `key: value` lines (`[QueryStringParams]`,
  # `[FormParams]`, `[MultipartFormData]`, `[Cookies]`, `[BasicAuth]`, …)
  # and an optional body. An `HTTP <status>` line opens the response half
  # (captures and asserts), which carries no request surface. `{{var}}`
  # placeholders come from the Hurl command line, so an unresolved one in the
  # path becomes a `:var` path parameter.
  class Hurl < SpecificationEngine
    analyzer_for "hurl"

    TEMPLATE_VAR  = /\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}/
    REQUEST_LINE  = /^(#{ALLOWED_HTTP_METHODS.join('|')})[ \t]+(\S+)/
    RESPONSE_LINE = /^HTTP(?:\/[\d.]+)?[ \t]+(?:\d{3}|\*)/
    SECTION_LINE  = /^\[([A-Za-z]+)\]$/

    def analyze
      each_spec_file(Noir::LocatorKeys::HURL_FILE) do |path|
        process_file(read_file_content(path), path)
      end

      @result
    end

    private class Entry
      getter method : String
      getter url : String
      getter line : Int32
      getter params = [] of Param
      getter body = [] of String

      def initialize(@method, @url, @line)
      end
    end

    private def process_file(content : String, path : String)
      entry = nil
      section = ""
      in_response = false
      in_fence = false

      content.each_line.with_index(1) do |raw, line_no|
        line = raw.strip

        if in_fence
          if line.starts_with?("```")
            in_fence = false
          elsif entry && !in_response
            entry.body << raw
          end
          next
        end

        if m = line.match(REQUEST_LINE)
          emit(entry, path) if entry
          entry = Entry.new(m[1], m[2], line_no)
          section = ""
          in_response = false
          next
        end

        next if line.empty? || line.starts_with?('#')
        next unless entry

        if line.matches?(RESPONSE_LINE)
          in_response = true
          next
        end
        next if in_response

        if m = line.match(SECTION_LINE)
          section = m[1]
          next
        end

        if !entry.body.empty?
          entry.body << raw
        elsif line.starts_with?("```")
          in_fence = !(line.size > 3 && line.ends_with?("```"))
        elsif line.starts_with?('{') || line.starts_with?('[')
          entry.body << raw
        else
          add_key_value(entry.params, section, line)
        end
      end

      emit(entry, path) if entry
    end

    private def add_key_value(params : Array(Param), section : String, line : String)
      name, sep, value = line.partition(':')
      name = name.strip
      return if sep.empty? || name.empty?
      value = value.strip

      case section
      when ""
        push_param_once(params, Param.new(name, value, "header")) unless skipped_request_header?(name)
      when "QueryStringParams", "Query"
        push_param_once(params, Param.new(name, value, "query"))
      when "FormParams", "Form", "MultipartFormData", "Multipart"
        push_param_once(params, Param.new(name, value, "form"))
      when "Cookies"
        push_param_once(params, Param.new(name, value, "cookie"))
      when "BasicAuth"
        push_param_once(params, Param.new("Authorization", "", "header"))
      end
    end

    private def emit(entry : Entry, path : String)
      url_path = template_url_path(entry.url, TEMPLATE_VAR)
      return if url_path.empty?

      params = entry.params
      request_query_pairs(entry.url).each do |name, value|
        push_param_once(params, Param.new(name, value, "query"))
      end
      request_path_vars(url_path).each do |name|
        push_param_once(params, Param.new(name, "", "path"))
      end
      json_body_keys(entry.body.join('\n')).each do |name, value|
        push_param_once(params, Param.new(name, value, "json"))
      end

      @result << Endpoint.new(url_path, entry.method, params, Details.new(PathInfo.new(path, entry.line)))
    end

    # Top-level keys of a JSON object body. Hurl allows an unquoted
    # `{{var}}` as a JSON value, which is invalid JSON, so a failed parse is
    # retried with every placeholder nulled out.
    private def json_body_keys(text : String) : Array(Tuple(String, String))
      stripped = text.strip
      return [] of Tuple(String, String) unless stripped.starts_with?('{')
      parsed = json_any?(stripped) || json_any?(stripped.gsub(TEMPLATE_VAR, "null"))
      hash = parsed.try(&.as_h?)
      return [] of Tuple(String, String) unless hash
      hash.map { |k, v| {k, v.to_s} }
    end
  end
end
