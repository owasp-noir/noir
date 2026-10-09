require "../../engines/specification_engine"
require "../../../utils/url_path"

module Analyzer::Specification
  # HAProxy: every path pattern an ACL matches on (`path`, `path_beg`,
  # `path_reg`, `path_dir`) is a path the proxy routes, whether it is declared
  # as a named `acl` or inline as `{ path_beg /x }`. Rules that use it add
  # context: `use_backend` names the backend, `http-request deny` (and
  # `reject`, `tarpit`, `silent-drop`, legacy `block`) marks it denied. ACLs
  # are scoped to their section. HAProxy rules carry no verb, so every
  # endpoint is `ANY`.
  class Haproxy < SpecificationEngine
    analyzer_for "haproxy"

    SECTION_RE = /^(?:global|defaults|frontend|backend|listen|resolvers|peers|userlist|program|cache|mailers|ring|http-errors)\b/
    FETCH      = /path(?:_beg|_end|_reg|_dir|_sub)?/
    ACL_RE     = /^acl\s+(\S+)\s+(#{FETCH})(?:,\S+)?(?:\s+(.*))?$/
    ANON_RE    = /(!?)\s*\{\s*(#{FETCH})(?:,\S+)?\s+([^}]*)\}/
    RULE_RE    = /\s(if|unless)\s+(.+)$/
    BACKEND_RE = /^use_backend\s+(\S+)/
    DENY_RE    = /^(?:http-request\s+(deny|reject|tarpit|silent-drop)|tcp-request\s+\S+\s+(reject)|block)\b/
    COMMENT_RE = /(?:^|\s)#.*$/

    # Match mode by fetch name; `-m <mode>` overrides it.
    MODES = {"path" => "str", "path_beg" => "beg", "path_end" => "end",
             "path_reg" => "reg", "path_dir" => "dir", "path_sub" => "sub"}
    # Modes whose pattern is a routable path, with the tag each one gets.
    PATH_TYPES = {"str" => "exact", "beg" => "prefix", "reg" => "regex", "dir" => "dir"}

    private record Rec, path : String, path_type : String, line : Int32, tags : Array(Tag)

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::HAPROXY_SPEC) do |path, details|
        process(read_file_content(path), details)
      end

      @result
    end

    private def process(content : String, details : Details)
      recs = [] of Rec
      acls = {} of String => Array(Int32)

      content.each_line.with_index(1) do |raw, number|
        line = raw.sub(COMMENT_RE, "").strip
        next if line.empty?

        if line.matches?(SECTION_RE)
          acls.clear
        elsif m = ACL_RE.match(line)
          indexes = acls[m[1]] ||= [] of Int32
          patterns(m[2], m[3]? || "").each do |pattern, path_type|
            indexes << recs.size
            recs << Rec.new(pattern, path_type, number, [] of Tag)
          end
        elsif rule = RULE_RE.match(line)
          tag = rule_tag(line)
          keyword_if = rule[1] == "if"
          condition = rule[2]

          condition.scan(ANON_RE) do |anon|
            positive = keyword_if == anon[1].empty?
            patterns(anon[2], anon[3]).each do |pattern, path_type|
              recs << Rec.new(pattern, path_type, number, positive && tag ? [tag] : [] of Tag)
            end
          end
          next unless tag

          condition.gsub(ANON_RE, " ").split.each do |token|
            negated = token.starts_with?('!')
            next unless indexes = acls[token.lchop('!')]?
            next unless keyword_if != negated
            indexes.each { |i| recs[i].tags << tag unless recs[i].tags.includes?(tag) }
          end
        end
      end

      recs.each do |rec|
        endpoint = Endpoint.new(rec.path, "ANY", details_at(details, rec.line))
        endpoint.add_tag(Tag.new("haproxy-path-type", rec.path_type, "haproxy_analyzer"))
        rec.tags.each { |tag| endpoint.add_tag(tag) }
        @result << endpoint
      end
    end

    private def rule_tag(line : String) : Tag?
      if m = BACKEND_RE.match(line)
        Tag.new("haproxy-backend", m[1], "haproxy_analyzer")
      elsif m = DENY_RE.match(line)
        Tag.new("haproxy-action", m[1]? || m[2]? || "block", "haproxy_analyzer")
      end
    end

    # `{pattern, path type}` for each routable pattern after the fetch,
    # skipping flags (`-i`, `-m beg`, `-f file`, ...).
    private def patterns(fetch : String, args : String) : Array({String, String})
      mode = MODES[fetch]
      values = [] of String
      tokens = args.split
      i = 0
      while i < tokens.size
        token = tokens[i]
        if token == "-m"
          mode = tokens[i + 1]? || mode
          i += 2
        elsif token.in?("-f", "-M")
          i += 2
        elsif token.starts_with?('-')
          i += 1
        else
          values << token
          i += 1
        end
      end

      return [] of {String, String} unless path_type = PATH_TYPES[mode]?
      values.compact_map do |value|
        value = value.strip('"').strip('\'')
        value = Noir::URLPath.strip_regex_anchors(value) if mode == "reg"
        {value, path_type} if value.starts_with?('/')
      end
    end
  end
end
