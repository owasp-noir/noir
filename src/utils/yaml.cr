require "yaml"

# Strict `YAML.parse`-or-nil.
def yaml_any?(content : String) : YAML::Any?
  YAML.parse(content)
rescue
  nil
end

# Parses YAML, recovering from a stray-tab failure that libyaml (Crystal's
# YAML backend) is stricter about than most other parsers.
#
# Real-world OpenAPI/Swagger documents occasionally carry a TAB character on an
# otherwise-blank line inside a block scalar (descriptions, examples, embedded
# code). libyaml rejects it with "found a tab character where an indentation
# space is expected", which drops the *entire* document — and with it every
# endpoint noir would have found — even though PyYAML, JS, and Go parsers accept
# it. As a last resort we blank out lines that consist solely of whitespace and
# retry. That transformation never touches real indentation, keys, or values, so
# a document that already parses is returned unchanged.
def parse_yaml(content : String) : YAML::Any
  YAML.parse(content)
rescue
  YAML.parse(blank_whitespace_only_lines(content))
end

# Replaces lines made up entirely of spaces/tabs with empty lines, preserving
# the original newline characters. A blank line is legal anywhere in YAML
# (including inside a block scalar) regardless of indentation, so this is a
# structurally safe normalization.
#
# Line *count* is preserved exactly — only the characters before each newline
# are dropped — so a position-aware second pass over the recovered text
# (`Noir::SpecLineIndex`) reports the same line numbers as the original.
def blank_whitespace_only_lines(content : String) : String
  String.build do |io|
    content.each_line(chomp: false) do |line|
      stripped = line.rstrip("\r\n")
      if !stripped.empty? && stripped.each_char.all? { |c| c == ' ' || c == '\t' }
        io << line[stripped.size..]
      else
        io << line
      end
    end
  end
end

# `YAML.parse_all`, retried on `untemplate_yaml` when a Helm/Kustomize
# template's `{{ ... }}` actions are what broke the parse. A chart's
# `templates/` directory is the usual home of Istio and Gateway API routes,
# and the whole file used to be dropped without a word.
def parse_all_yaml_template(content : String) : Array(YAML::Any)
  YAML.parse_all(content)
rescue e : YAML::ParseException
  raise e unless content.includes?("{{")
  YAML.parse_all(untemplate_yaml(content))
end

private YAML_TEMPLATE_KEY_LINE  = /\A([ \t]*(?:-[ \t]+)?[^\s{#\-][^:]*:)[ \t]/
private YAML_TEMPLATE_ITEM_LINE = /\A([ \t]*-)[ \t]/

# Best-effort YAML out of a Go-template manifest, line by line so the line
# count is kept:
#
# - a line holding only actions (`{{- if .Values.x }}`, `{{- end }}`,
#   `{{- toYaml . | nindent 4 }}`) is blanked;
# - a `key: ...` or `- ...` line whose value has an action gets a null value,
#   so `host: {{ .Values.host }}` or `prefix: {{ .base }}/v1` reads as "not
#   known" rather than as a made-up string.
#
# Anything else is left alone, and the parse may still fail.
def untemplate_yaml(content : String) : String
  String.build(content.bytesize) do |io|
    content.each_line(chomp: false) do |line|
      body = line.rstrip("\r\n")
      eol = line[body.size..]
      if !body.includes?("{{")
        io << line
      elsif without_template_actions(body).blank?
        io << eol
      elsif m = body.match(YAML_TEMPLATE_KEY_LINE) || body.match(YAML_TEMPLATE_ITEM_LINE)
        io << m[1] << " ~" << eol
      else
        io << line
      end
    end
  end
end

# `line` with every `{{ ... }}` action removed; an unclosed `{{` is kept.
private def without_template_actions(line : String) : String
  String.build(line.bytesize) do |io|
    pos = 0
    while (open = line.byte_index("{{", pos)) && (close = line.byte_index("}}", open + 2))
      io.write(line.to_slice[pos, open - pos])
      pos = close + 2
    end
    io.write(line.to_slice[pos, line.bytesize - pos])
  end
end
