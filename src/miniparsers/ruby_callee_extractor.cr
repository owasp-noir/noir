require "../models/endpoint"
require "./callee_extractor_base"

module Noir::RubyCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

  RESERVED = Set{
    "alias", "and", "begin", "break", "case", "class", "def",
    "defined?", "do", "else", "elsif", "end", "ensure", "false",
    "for", "if", "in", "module", "next", "nil", "not", "or",
    "redo", "rescue", "retry", "return", "self", "super", "then",
    "true", "undef", "unless", "until", "when", "while", "yield",
  }

  RECEIVER_CALL_REGEX = /((?:@{1,2})?[A-Za-z_][\w]*(?:::[A-Za-z_][\w]*)*(?:\.[A-Za-z_][\w]*[!?=]?)+)\s*(\()?/
  BARE_CALL_REGEX     = /(?<![.\w:])([a-z_][\w]*[!?=]?)(?:\s*\(|(?=\s+(?:[:'"]|@{1,2}[A-Za-z_]|[A-Za-z_][\w]*[!?=]?)))/
  RAILS_FORMAT_CALLS  = Set{"html", "json", "js", "xml", "rss", "atom", "turbo_stream", "api"}
  RAILS_RESPONSE_DSL  = Set{"respond_to"}
  REQUEST_ACCESSORS   = Set{"get", "post", "put", "patch", "delete", "xhr", "xhr?", "remote_ip", "raw_post"}
  ATTRIBUTE_READERS   = Set{
    "id", "ids", "uuid", "guid", "token", "key",
    "name", "username", "title", "description", "text", "body", "message",
    "url", "uri", "path", "email", "status", "state", "type", "role",
    "score", "size", "length", "first", "last", "active",
    "attributes", "safe_attributes", "password", "password_confirmation", "scheme_name",
  }

  def callees_for_body(body : String, file_path : String, start_line : Int32) : Array(Entry)
    entries = [] of Entry

    body.lines.each_with_index do |line, index|
      scan_line(strip_comment(line), file_path, start_line + index, entries)
    end

    dedup_entries(entries)
  end

  private def scan_line(line : String, file_path : String, line_number : Int32, entries : Array(Entry))
    line.scan(RECEIVER_CALL_REGEX) do |match|
      name = match[1]
      has_parens = !!match[2]?
      next if skip_callee?(name, has_parens)

      entries << {name, file_path, line_number}
    end

    line.scan(BARE_CALL_REGEX) do |match|
      name = match[1]
      next if skip_callee?(name)

      entries << {name, file_path, line_number}
    end
  end

  private def skip_callee?(name : String, has_parens : Bool = false) : Bool
    return true if name.empty?

    last = name.split('.').last
    return true if RESERVED.includes?(last)
    return true if RAILS_RESPONSE_DSL.includes?(last)
    return true if request_accessor_callee?(name, last)
    return true if rails_format_callee?(name, last, has_parens)
    return true if attribute_reader_callee?(name, last, has_parens)

    false
  end

  private def rails_format_callee?(name : String, last : String, has_parens : Bool) : Bool
    return false if has_parens
    name.starts_with?("format.") && RAILS_FORMAT_CALLS.includes?(last)
  end

  private def request_accessor_callee?(name : String, last : String) : Bool
    name.starts_with?("request.") && REQUEST_ACCESSORS.includes?(last)
  end

  private def attribute_reader_callee?(name : String, last : String, has_parens : Bool) : Bool
    return false if has_parens
    return false if name.starts_with?("response.")
    return false if last.ends_with?("?") || last.ends_with?("!") || last.ends_with?("=")
    ATTRIBUTE_READERS.includes?(last) ||
      last.starts_with?("is_") ||
      last.ends_with?("_id") ||
      last.ends_with?("_ids") ||
      last.ends_with?("_ip") ||
      last.ends_with?("_name") ||
      last.ends_with?("_at") ||
      last.ends_with?("_attributes")
  end

  def strip_comment(line : String, preserve_strings : Bool = false) : String
    stripped = String::Builder.new
    in_string = false
    escaped = false
    quote = '\0'

    line.each_char do |char|
      if in_string
        if escaped
          stripped << (preserve_strings ? char : ' ')
          escaped = false
        elsif char == '\\'
          stripped << (preserve_strings ? char : ' ')
          escaped = true
        elsif char == quote
          stripped << char
          in_string = false
        else
          stripped << (preserve_strings ? char : ' ')
        end
      elsif char == '"' || char == '\''
        in_string = true
        quote = char
        stripped << char
      elsif char == '#'
        return stripped.to_s
      else
        stripped << char
      end
    end

    stripped.to_s
  end
end
