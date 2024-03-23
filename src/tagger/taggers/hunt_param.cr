require "../../models/tagger"
require "../../models/endpoint"

class HuntParamTagger < Tagger
  def perform(endpoints : Array(Endpoint))
    tagger = Hash(String, Array(String)).new
    tagger["ssti"] = ["template", "preview", "id", "view", "activity", "name", "content", "redirect"]
    tagger["ssrf"] = ["dest", "redirect", "uri", "path", "continue", "url", "window", "next", "data", "reference", "site", "html", "val", "validate", "domain", "callback", "return", "page", "feed", "host", "port", "to", "out", "view", "dir", "show", "navigation", "open"]
    tagger["sqli"] = ["id", "select", "report", "role", "update", "query", "user", "name", "sort", "where", "search", "params", "process", "row", "view", "table", "from", "sel", "results", "sleep", "fetch", "order", "keyword", "column", "field", "delete", "string", "number", "filter"]
    tagger["idor"] = ["id", "user", "account", "number", "order", "no", "doc", "key", "email", "group", "profile", "edit", "report"]
    tagger["file_inclusion"] = ["file", "document", "folder", "root", "path", "pg", "style", "pdf", "template", "php_path", "doc"]
    tagger["debug"] = ["access", "admin", "dbg", "debug", "edit", "grant", "test", "alter", "clone", "create", "delete", "disable", "enable", "exec", "execute", "load", "make", "modify", "rename", "reset", "shell", "toggle", "adm", "root", "cfg", "config"]
    tagger["command_injection"] = ["daemon", "host", "upload", "dir", "execute", "download", "log", "ip", "cli", "cmd"]

    endpoints.each do |endpoint|
      endpoint.params.each do |param|
        tagger.each do |key, values|
          if values.includes? param.name
            tag = Tag.new(key, "HUNT Param")
            param.add_tag(tag)
          end
        end
      end
    end
  end
end
