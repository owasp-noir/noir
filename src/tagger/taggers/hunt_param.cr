require "../../models/tagger"
require "../../models/endpoint"

class HuntParamTagger < Tagger
  PATH_ALLOWED_TAGS     = Set{"idor", "file-inclusion"}
  BODY_LIKE_PARAM_TYPES = Set{"json", "form"}

  TAG_DEFINITIONS = {
    "ssti" => {
      "words"       => ["template", "preview", "activity", "content", "redirect"],
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
      "words"       => ["id", "user", "account", "number", "order", "false", "doc", "key", "group", "profile", "edit", "report"],
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

    param.name == "id"
  end

  private def tag_matches_param_name?(tag_name : String, words : Array(String), param : Param) : Bool
    return true if words.includes?(param.name)
    return false unless tag_name == "idor"
    return false unless param.param_type == "path"

    identifier_suffix_like?(param.name)
  end

  private def identifier_suffix_like?(name : String) : Bool
    return true if name == "id"
    return true if name.matches?(/[_-]id$/i)
    return true if name.matches?(/[a-z0-9]Id$/)
    return true if name.matches?(/[a-z0-9]ID$/)

    false
  end
end
