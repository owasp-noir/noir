require "../../engines/php_engine"

module Analyzer::Php
  class Php < PhpEngine
    def analyze_file(path : String) : Array(Endpoint)
      return [] of Endpoint unless File.extname(path) == ".php"

      endpoints = [] of Endpoint
      relative_path = get_relative_path(php_base_path_for(path), path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        params_query = [] of Param
        params_body = [] of Param
        methods = [] of String

        content.each_line do |line|
          if allow_patterns.any? { |pattern| line.includes? pattern }
            superglobal_matches = line.scan(/\$_(GET|POST|REQUEST|SERVER|COOKIE|FILES)\s*\[\s*['"]([^'"]+)['"]\s*\]/)
            superglobal_matches.each do |match|
              apply_param_reference(match[1], match[2], params_query, params_body, methods)
            end

            filter_input_matches = line.scan(/filter_input\s*\(\s*INPUT_(GET|POST|REQUEST|SERVER|COOKIE)\s*,\s*['"]([^'"]+)['"]/)
            filter_input_matches.each do |match|
              apply_param_reference(match[1], match[2], params_query, params_body, methods)
            end
          end
        rescue
          next
        end

        # For the pure-PHP analyzer we are parameter-driven (not route-driven).
        # A file with thousands of superglobal references (e.g. a large controller
        # with many action methods) used to produce thousands of near-identical
        # Endpoint objects for the same pseudo-path. The optimizer would later
        # collapse them by (method, url) while merging params. Creating the
        # duplicates up-front was extremely expensive on large files.
        #
        # We emit at most the POST pseudo-endpoint (when any POST/REQUEST/FILES
        # reference was seen) plus the always-present GET pseudo-endpoint (for
        # query/cookie/header params discovered in the file). We also deduplicate
        # params by (name, param_type) in first-seen order so that the Endpoint
        # objects we hand to later stages carry the same logical set that the
        # optimizer would have produced. This is semantically identical to the
        # previous behaviour for all observable outputs and test expectations,
        # but avoids the O(N) explosion in intermediate objects.
        #
        # Note: unlike real framework analyzers, this one only ever contributes
        # "POST" (or nothing) to the methods list; the GET is emitted separately.
        # The wording is intentionally specific to avoid implying full multi-verb
        # route support here.
        distinct_methods = methods.uniq
        query_params = unique_params_preserve_order(params_query)
        body_params = unique_params_preserve_order(params_body)

        details = Details.new(PathInfo.new(path))
        distinct_methods.each do |method|
          endpoints << Endpoint.new("/#{relative_path}", method, body_params, details)
        end
        endpoints << Endpoint.new("/#{relative_path}", "GET", query_params, details)
        attach_file_callees(endpoints, content, path) if include_callee
      end

      endpoints
    end

    private def apply_param_reference(method : String,
                                      param_name : String,
                                      params_query : Array(Param),
                                      params_body : Array(Param),
                                      methods : Array(String))
      if method == "GET"
        params_query << Param.new(param_name, "", "query")
      elsif method == "POST"
        params_body << Param.new(param_name, "", "form")
        methods << "POST"
      elsif method == "REQUEST"
        params_query << Param.new(param_name, "", "query")
        params_body << Param.new(param_name, "", "form")
        methods << "POST"
      elsif method == "SERVER"
        if param_name.includes? "HTTP_"
          header_name = param_name.sub("HTTP_", "").gsub("_", "-")
          params_query << Param.new(header_name, "", "header")
          params_body << Param.new(header_name, "", "header")
        end
      elsif method == "COOKIE"
        params_query << Param.new(param_name, "", "cookie")
        params_body << Param.new(param_name, "", "cookie")
      elsif method == "FILES"
        params_body << Param.new(param_name, "", "file")
        methods << "POST"
      end
    end

    # Order-preserving dedup of params by (name, param_type).
    # The pure-PHP analyzer accumulates every superglobal reference it sees.
    # For files with repeated references the lists can contain many
    # duplicates. The final endpoint(s) for a pseudo-path must expose the
    # unique set (as params_to_hash and the optimizer's merge logic do).
    # We dedup here in first-seen order so that we construct far fewer
    # Endpoint objects while still producing identical observable param
    # sets for every (method, url) pair.
    private def unique_params_preserve_order(params : Array(Param)) : Array(Param)
      seen = Set(Tuple(String, String)).new
      result = [] of Param
      params.each do |p|
        key = {p.name, p.param_type}
        unless seen.includes?(key)
          seen.add(key)
          result << p
        end
      end
      result
    end

    private def attach_file_callees(endpoints : Array(Endpoint), content : String, path : String)
      callees = Noir::PhpCalleeExtractor.callees_for_body(executable_file_content(content), path, 1)
      endpoints.each do |endpoint|
        attach_php_callees(endpoint, callees)
      end
    end

    private def executable_file_content(content : String) : String
      declaration_ranges = [] of Tuple(Int32, Int32)
      declaration_regex = /\b(?:abstract\s+|final\s+)?(?:class|interface|trait|enum)\s+[A-Za-z_]\w*[^{]*\{|\bfunction\s+&?\s*[A-Za-z_]\w*[^{]*\{/m
      offset = 0

      while offset < content.size
        match = declaration_regex.match(content, offset)
        break unless match

        brace_pos = match.end(0) - 1
        close_pos = find_matching_php_close_brace(content, brace_pos)
        unless close_pos
          offset = match.end(0)
          next
        end

        declaration_ranges << {match.begin(0), close_pos + 1}
        offset = close_pos + 1
      end

      return content if declaration_ranges.empty?

      blank_ranges(content, declaration_ranges)
    end

    private def blank_ranges(content : String, ranges : Array(Tuple(Int32, Int32))) : String
      String.build do |io|
        offset = 0
        ranges.each do |range_start, range_end|
          io << content[offset...range_start]
          io << blank_preserving_newlines(content[range_start...range_end])
          offset = range_end
        end
        io << content[offset..]
      end
    end

    private def blank_preserving_newlines(content : String) : String
      String.build do |io|
        content.each_char do |char|
          io << (char == '\n' ? '\n' : ' ')
        end
      end
    end

    def allow_patterns
      ["$_GET", "$_POST", "$_REQUEST", "$_SERVER", "$_COOKIE", "$_FILES", "filter_input"]
    end
  end
end
