require "../../models/tagger"
require "../../models/endpoint"

class HuntParamTagger < Tagger
  PATH_ALLOWED_TAGS     = Set{"idor", "file-inclusion"}
  BODY_LIKE_PARAM_TYPES = Set{"json", "form", "body"}
  # IDOR identifier-suffix matching (`userId`, `account_id`) only makes
  # sense for inputs that address an object directly. Query and path
  # params qualify; body params stay suppressed to mirror the bare-`id`
  # heuristic below.
  IDOR_SUFFIX_PARAM_TYPES = Set{"path", "query"}

  TAG_DEFINITIONS = {
    "ssti" => {
      "words"       => ["template", "preview", "activity", "redirect"],
      "description" => "This parameter may be vulnerable to Server Side Template Injection (SSTI) attacks.",
    },
    "ssrf" => {
      "words"       => ["dest", "redirect", "uri", "path", "continue", "url", "window", "next", "reference", "site", "html", "validate", "domain", "callback", "return", "feed", "host", "port", "dir", "navigation", "open"],
      "description" => "This parameter may be vulnerable to Server Side Request Forgery (SSRF) attacks.",
    },
    "sqli" => {
      "words"       => ["select", "report", "update", "sort", "where", "search", "params", "process", "row", "table", "sel", "results", "sleep", "fetch", "order", "keyword", "column", "field", "delete", "filter"],
      "description" => "This parameter may be vulnerable to SQL Injection attacks.",
    },
    "idor" => {
      "words"       => ["id", "user", "account", "order", "doc", "key", "group", "profile", "edit", "report"],
      "description" => "This parameter may be vulnerable to Insecure Direct Object Reference (IDOR) attacks.",
    },
    "file-inclusion" => {
      "words"       => ["file", "document", "folder", "root", "path", "pg", "style", "pdf", "template", "php_path", "doc"],
      "description" => "This parameter may be vulnerable to File Inclusion attacks.",
    },
    "debug" => {
      "words"       => ["access", "admin", "dbg", "debug", "edit", "grant", "test", "alter", "clone", "create", "delete", "disable", "enable", "exec", "execute", "load", "make", "modify", "rename", "reset", "shell", "toggle", "adm", "root", "cfg", "config"],
      "description" => "This parameter may be vulnerable to Debug method exploits.",
    },
    "command-injection" => {
      "words"       => ["daemon", "host", "upload", "dir", "execute", "download", "log", "ip", "cli", "cmd"],
      "description" => "This parameter may be vulnerable to Command Injection attacks.",
    },
  }

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "hunt"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      endpoint.params.each do |param|
        TAG_DEFINITIONS.each do |k, v|
          next if param.param_type == "path" && !PATH_ALLOWED_TAGS.includes?(k)
          next if skip_idor_body_heuristic?(k, param)
          if tag_matches_param_name?(k, v["words"].as(Array(String)), param)
            next if param.tags.any? { |existing| existing.name == k && existing.tagger == "Hunt" }
            tag = Tag.new(k, v["description"].to_s, "Hunt")
            param.add_tag(tag)
          end
        end
      end
    end
  end

  private def skip_idor_body_heuristic?(tag_name : String, param : Param) : Bool
    return false unless tag_name == "idor"
    return false unless BODY_LIKE_PARAM_TYPES.includes?(param.param_type)

    normalized = param.name.downcase
    normalized == "id" || normalized == "key"
  end

  private def tag_matches_param_name?(tag_name : String, words : Array(String), param : Param) : Bool
    # Word lists are lowercase; param names in the wild are frequently
    # cased (ID, URL, userId). Normalize so `--use-taggers hunt` doesn't
    # silently miss case variants the way other taggers don't.
    return true if words.includes?(param.name.downcase)

    # Compound names are the common shape in real codebases
    # (`redirectUrl`, `file_path`, `userId`). Match the high-confidence,
    # low-noise classes on a token basis so these aren't silently dropped
    # the way an exact-match-only list would.
    case tag_name
    when "ssrf"
      return true if name_tokens(param.name).any? { |token| token == "url" || token == "uri" }
    when "file-inclusion"
      return true if name_tokens(param.name).includes?("file")
    when "idor"
      if IDOR_SUFFIX_PARAM_TYPES.includes?(param.param_type)
        return true if identifier_suffix_like?(param.name)
      end
    end

    false
  end

  # Split a parameter name into lowercase word tokens, honoring snake_case,
  # kebab-case, dotted, and camelCase boundaries (`redirectUrl` ->
  # ["redirect", "url"], `file_path` -> ["file", "path"]).
  private def name_tokens(name : String) : Array(String)
    name.gsub(/([a-z0-9])([A-Z])/, "\\1_\\2")
      .split(/[^A-Za-z0-9]+/)
      .reject(&.empty?)
      .map(&.downcase)
  end

  private def identifier_suffix_like?(name : String) : Bool
    return true if name == "id"
    return true if name.matches?(/[_-]id$/i)
    return true if name.matches?(/[a-z0-9]Id$/)
    return true if name.matches?(/[a-z0-9]ID$/)

    false
  end
end
