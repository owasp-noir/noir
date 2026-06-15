require "yaml"

def valid_yaml?(content : String) : Bool
  YAML.parse(content)
  true
rescue
  false
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
private def blank_whitespace_only_lines(content : String) : String
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
