#!/usr/bin/env crystal
# noir/scripts/generate_supported_docs.cr
# Generate docs/content/usage/supported/language_and_frameworks/index.md
# Generate docs/content/usage/supported/specification/index.md
# from `./bin/noir --list-techs` output.

require "json"

struct Tech
  property key : String
  property framework : String
  property language : String?
  getter? is_format : Bool
  setter is_format : Bool
  property formats : Array(String)?
  getter? endpoint : Bool
  setter endpoint : Bool
  getter? method : Bool
  setter method : Bool
  getter? query : Bool
  setter query : Bool
  getter? path : Bool
  setter path : Bool
  getter? body : Bool
  setter body : Bool
  getter? header : Bool
  setter header : Bool
  getter? cookie : Bool
  setter cookie : Bool
  getter? static_path : Bool
  setter static_path : Bool
  getter? websocket : Bool
  setter websocket : Bool

  # Backwards-compatible non-predicate getters
  def is_format
    @is_format
  end

  def endpoint
    @endpoint
  end

  def method
    @method
  end

  def query
    @query
  end

  def path
    @path
  end

  def body
    @body
  end

  def header
    @header
  end

  def cookie
    @cookie
  end

  def static_path
    @static_path
  end

  def websocket
    @websocket
  end

  def initialize(@key : String)
    @framework = ""
    @language = nil
    @is_format = false
    @formats = nil
    @endpoint = false
    @method = false
    @query = false
    @path = false
    @body = false
    @header = false
    @cookie = false
    @static_path = false
    @websocket = false
  end
end

# Render a boolean as a checkmark or cross
def check(b : Bool) : String
  b ? "✅" : "❌"
end

def project_root_from_script : String
  # Determine project root assuming this file lives in <root>/scripts/generate_supported_docs.cr
  script_dir = File.dirname(File.expand_path(__FILE__))
  # If we're in .../scripts, go one up; otherwise, assume current dir is root.
  if File.basename(script_dir) == "scripts"
    File.expand_path("..", script_dir)
  else
    script_dir
  end
end

def default_output_path(root : String) : String
  File.join(root, "docs", "content", "usage", "supported", "language_and_frameworks", "index.md")
end

def run_list_techs(root : String) : {Int32, String}
  bin = File.join(root, "bin", "noir")
  output = IO::Memory.new
  status = Process.run(bin, args: ["--list-techs"], output: output, error: output, shell: false) rescue begin
    # When execution fails (e.g., file missing), simulate non-zero status
    return {127, "Failed to execute #{bin} --list-techs. Is the binary built? Run `just build`.\n"}
  end
  code = status.exit_code || (status.success? ? 0 : 1)
  {code, output.to_s}
end

TECH_HEADER = <<-MD
+++
title = "Supported Languages and Frameworks"
description = "A detailed overview of the programming languages and frameworks supported by Noir, including feature compatibility for each."
weight = 1
sort_by = "weight"

[extra]
+++

Noir is a tool designed to analyze and understand codebases by identifying endpoints and their specifications. This section provides a comprehensive list of the programming languages that Noir supports. For each language, this page shows a single table with a Framework column and the following fields: endpoint, method, query, path, body, header, cookie, static_path, websocket.

MD

def parse_tech_blocks(text : String) : Array(Tech)
  lines = text.lines
  techs = [] of Tech

  # Find the start marker (optional)
  start_idx = lines.index(&.includes?("Available technologies")) || 0

  i = start_idx
  current : Tech? = nil
  block_lines = [] of String

  id_regex = /^\s{4}([a-z0-9_]+)\s*$/

  while i < lines.size
    line = lines[i]
    if m = id_regex.match(line)
      # Flush previous block
      if current && !block_lines.empty?
        current.try { |c| techs << finalize_block(c, block_lines) }
      end
      # Start new block
      current = Tech.new(m[1])
      block_lines = [] of String
    else
      # Accumulate details under current tech
      if current
        block_lines << line
      end
    end
    i += 1
  end

  # Flush last block
  if current && !block_lines.empty?
    current.try { |c| techs << finalize_block(c, block_lines) }
  end

  techs
end

def finalize_block(tech : Tech, block_lines : Array(String)) : Tech
  # Parse line-by-line to avoid end-of-string regex pitfalls
  t_framework = nil
  t_language = nil
  formats = [] of String
  is_format = false

  block_lines.each do |raw|
    line = raw.strip

    # Framework
    if line.starts_with?("➔ framework:") || line.starts_with?("framework:")
      value = line.split(":", 2)[1]?.try &.strip
      t_framework = value || ""

      # Language
    elsif line.starts_with?("➔ language:") || line.starts_with?("language:")
      value = line.split(":", 2)[1]?.try &.strip
      t_language = value

      # Format (specification)
    elsif line.starts_with?("➔ format:") || line.starts_with?("format:")
      if m = line.match(/\[(.+)\]/)
        is_format = true
        formats = m[1].split(",").map(&.strip.gsub(/^"|"$/, ""))
      else
        is_format = true
      end

      # Supported flags
    elsif line.includes?("endpoint:")
      tech.endpoint = line.includes?("true")
    elsif line.includes?("method:")
      tech.method = line.includes?("true")
    elsif line.includes?("websocket:")
      tech.websocket = line.includes?("true")
    elsif line.includes?("static_path:")
      tech.static_path = line.includes?("true")

      # Params hash line
    elsif line.starts_with?("└── params:") || line.starts_with?("params:")
      if m = line.match(/\{(.+)\}/)
        params_str = m[1]
        tech.query = params_str.includes?(":query => true")
        tech.path = params_str.includes?(":path => true")
        tech.body = params_str.includes?(":body => true")
        tech.header = params_str.includes?(":header => true")
        tech.cookie = params_str.includes?(":cookie => true")
      else
        tech.query = line.includes?(":query => true")
        tech.path = line.includes?(":path => true")
        tech.body = line.includes?(":body => true")
        tech.header = line.includes?(":header => true")
        tech.cookie = line.includes?(":cookie => true")
      end
    end
  end

  # Assign parsed values
  if t_framework
    tech.framework = t_framework
  end
  if t_language
    tech.language = t_language unless t_language.empty?
  end
  if is_format
    tech.is_format = true
    tech.formats = formats unless formats.empty?
  end

  # Normalize framework
  if tech.framework.nil? || tech.framework.empty?
    tech.framework = "Pure"
  end

  tech
end

def friendly_format_name(key : String, block : Tech) : String
  # Attempt to produce a nice display name for formats/specs
  case key
  when "har"     then "HAR"
  when "oas2"    then "OpenAPI 2.0 (Swagger)"
  when "oas3"    then "OpenAPI 3.0"
  when "graphql" then "GraphQL"
  when "raml"    then "RAML"
  else
    # Fallback to framework or capitalized key
    block.framework.presence || key.gsub("_", " ").split.map(&.capitalize).join(" ")
  end
end

def generate_markdown(techs : Array(Tech)) : String
  # Group by language; formats/specs will go in a separate bucket
  by_language = Hash(String, Array(Tech)).new { |h, k| h[k] = [] of Tech }
  formats = [] of {name: String, tech: Tech}

  techs.each do |t|
    if t.is_format || t.language.nil?
      formats << {name: friendly_format_name(t.key, t), tech: t}
    else
      if lang = t.language
        by_language[lang] << t
      end
    end
  end

  # Sort languages and frameworks
  lang_keys = by_language.keys.sort!
  lang_keys.each do |lang|
    by_language[lang].sort_by!(&.framework)
  end
  formats.sort_by! { |e| e[:name] }

  io = IO::Memory.new
  io << TECH_HEADER

  lang_keys.each do |lang|
    io << "## #{lang}\n\n"
    io << "| Framework | endpoint | method | query | path | body | header | cookie | static_path | websocket |\n"
    io << "|-----------|----------|--------|-------|------|------|--------|--------|-------------|-----------|\n"
    by_language[lang].each do |t|
      io << "| #{t.framework} | #{check(t.endpoint)} | #{check(t.method)} | #{check(t.query)} | #{check(t.path)} | #{check(t.body)} | #{check(t.header)} | #{check(t.cookie)} | #{check(t.static_path)} | #{check(t.websocket)} |\n"
    end
    io << "\n"
  end

  io.to_s
end

def ensure_parent_dir(path : String)
  dir = File.dirname(path)
  Dir.mkdir_p(dir) unless Dir.exists?(dir)
end

AUTOGEN_MARKER = "<!-- AUTOGENERATED-->"

def language_pages_dir(root : String) : String
  File.join(root, "docs", "content", "usage", "supported", "language_and_frameworks")
end

def generate_language_tables(techs : Array(Tech)) : String
  # Group by language (exclude formats/specs and techs without language)
  by_language = Hash(String, Array(Tech)).new { |h, k| h[k] = [] of Tech }

  techs.each do |t|
    next if t.is_format || t.language.nil?
    if lang = t.language
      by_language[lang] << t
    end
  end

  # Sort languages and frameworks
  lang_keys = by_language.keys.sort!
  lang_keys.each do |lang|
    by_language[lang].sort_by!(&.framework)
  end

  io = IO::Memory.new
  lang_keys.each do |lang|
    io << "## #{lang}\n\n"
    io << "| Framework | endpoint | method | query | path | body | header | cookie | static_path | websocket |\n"
    io << "|-----------|----------|--------|-------|------|------|--------|--------|-------------|-----------|\n"
    by_language[lang].each do |t|
      io << "| #{t.framework} | #{check(t.endpoint)} | #{check(t.method)} | #{check(t.query)} | #{check(t.path)} | #{check(t.body)} | #{check(t.header)} | #{check(t.cookie)} | #{check(t.static_path)} | #{check(t.websocket)} |\n"
    end
    io << "\n"
  end

  io.to_s
end

def inject_autogen_into_language_pages(root : String, tables : String) : Array(String)
  dir = language_pages_dir(root)
  updated = [] of String

  Dir.glob(File.join(dir, "*.md")).each do |path|
    content = File.read(path)
    parts = content.split(AUTOGEN_MARKER, 2)
    next unless parts.size == 2

    new_content = parts[0] + AUTOGEN_MARKER + "\n\n" + tables
    new_content += "\n" unless new_content.ends_with?("\n")

    ensure_parent_dir(path)
    File.write(path, new_content)
    updated << path
  end

  updated
end

def main
  # Resolve project root
  root = project_root_from_script

  status, text = run_list_techs(root)
  if status != 0
    STDERR.puts text
    STDERR.puts "Cannot generate docs without `./bin/noir --list-techs` output. Ensure the binary is built (e.g., `just build`)."
    exit status
  end

  techs = parse_tech_blocks(text)

  # Generate tables-only content and inject into all language_and_frameworks/*.md pages
  tables = generate_language_tables(techs)
  updated_files = inject_autogen_into_language_pages(root, tables)
  updated_files.each { |p| puts "Updated: #{p}" }

  # Generate specification page (with full header retained)
  content_specs = generate_specs_markdown(techs)
  spec_output_path = default_spec_output_path(root)
  ensure_parent_dir(spec_output_path)
  File.write(spec_output_path, content_specs)
  puts "Generated: #{spec_output_path}"
end

main

def default_spec_output_path(root : String) : String
  File.join(root, "docs", "content", "usage", "supported", "specification", "index.md")
end

SPEC_HEADER = <<-MD
+++
title = "Supported Specifications"
description = "This page provides a detailed overview of the API and data specifications that Noir supports, including OpenAPI (Swagger), RAML, HAR, and GraphQL. See the compatibility table for more information."
weight = 2
sort_by = "weight"

[extra]
+++

In addition to analyzing source code directly, Noir can also parse various API and data specification formats. This allows you to use Noir to analyze existing API documentation, captured network traffic, and more.

This section provides a compatibility table for the different specifications that Noir supports.

MD

def generate_specs_markdown(techs : Array(Tech)) : String
  specs = techs.select { |t| t.is_format || t.language.nil? }
  entries = specs.map { |t| {name: friendly_format_name(t.key, t), tech: t} }.sort_by! { |e| e[:name] }

  io = IO::Memory.new
  io << SPEC_HEADER
  io << "| Specification | Format | endpoint | method | query | path | body | header | cookie | static_path | websocket |\n"
  io << "|---|---|---|---|---|---|---|---|---|---|---|\n"
  entries.each do |entry|
    t = entry[:tech]
    name = entry[:name]
    formats = t.formats || [] of String
    if formats.empty?
      io << "| #{name} |  | #{check(t.endpoint)} | #{check(t.method)} | #{check(t.query)} | #{check(t.path)} | #{check(t.body)} | #{check(t.header)} | #{check(t.cookie)} | #{check(t.static_path)} | #{check(t.websocket)} |\n"
    else
      formats.each do |fmt|
        io << "| #{name} | #{fmt} | #{check(t.endpoint)} | #{check(t.method)} | #{check(t.query)} | #{check(t.path)} | #{check(t.body)} | #{check(t.header)} | #{check(t.cookie)} | #{check(t.static_path)} | #{check(t.websocket)} |\n"
      end
    end
  end
  io.to_s
end
