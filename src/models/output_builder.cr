require "./logger"
require "./analyzer_failure"
require "./endpoint"
require "./passive_scan"
require "../utils/*"
require "colorize"

# Process-wide registry of `-o` file handles, one per output path.
#
# A standalone type, deliberately, rather than a `@@` on OutputBuilder:
# Crystal gives every *subclass* its own copy of an inherited class
# variable. The `@@prepared_output_files` set this replaces therefore
# tracked "already truncated?" separately per builder class, so the second
# builder to write a given run's `-o` file re-opened it in "w" and erased
# what the first had put there. In diff mode that silently ate the
# `✚ Added (n)` section header: OutputBuilderDiff writes the header, then
# the OutputBuilderCommon it delegates to truncates the file out from under
# it. One registry, keyed by path only, gives every builder in the run the
# same handle — truncate once on open, append from then on.
module NoirOutputFiles
  @@handles = {} of String => File
  # Guards open/close only, not the per-line writes: report emission runs
  # after analysis on a single fiber, so lines can't interleave, but an
  # unguarded double-open would have two handles truncating one path — the
  # failure this registry exists to prevent.
  @@mutex = Mutex.new

  # Every write is flushed as it happens, so the only thing left at exit is
  # to release descriptors. One handler for the whole registry rather than
  # one per opened file, so `reset` fully undoes what `handle` did instead
  # of leaving a closure behind per call.
  at_exit { reset }

  # Opened lazily so a builder constructed with an `-o` path but never
  # written to (the format never emits, or the run has no results) doesn't
  # leave an empty file behind.
  def self.handle(path : String) : File
    @@mutex.synchronize do
      @@handles[path] ||= File.open(path, "w")
    end
  end

  # Specs write to a tempname, read it back, then delete it; without this
  # a later example reusing a path would keep writing to the stale handle.
  def self.reset : Nil
    @@mutex.synchronize do
      @@handles.each_value { |file| close(file) }
      @@handles.clear
    end
  end

  # Every line is flushed as it is written, so a failure here can only mean
  # the descriptor is already gone (the `-o` target was unlinked mid-run, a
  # write error took the file down). There is no report content left to
  # lose and nowhere useful to report it from a shutdown hook.
  private def self.close(file : File) : Nil
    file.close unless file.closed?
  rescue IO::Error
  end
end

# Marks an `OutputBuilder` subclass as the implementation of one
# `-f/--format` value.
#
#     @[Noir::OutputFormat(name: "json", description: "JSON", order: 30)]
#     class OutputBuilderJson < OutputBuilder
#
# `Noir::OutputFormats` reads the catalog off the annotated classes, so this
# line is the only place a format's name, its help/`noir list formats`
# description, and the class that renders it are written down. Before it,
# those three facts lived in five hand-maintained lists (the dispatch `case`
# in `NoirRunner#report`, `CliValidation::VALID_OUTPUT_FORMATS`, the `-f`
# help text, and the zsh/bash/fish completion strings) that nothing linked
# together — a new format silently missed whichever ones the author forgot.
#
# `order` decides where the format appears in help output and `noir list
# formats`; it has no runtime meaning. Values are spaced by 10 so a format
# can be slotted between two others without renumbering.
#
# Builders that are not `-f` values (the diff renderer, the passive-scan
# section) carry no annotation and stay out of the registry.
annotation Noir::OutputFormat
end

class OutputBuilder
  # Escape sequences removed on the way into the `-o` file. `Colorize` only
  # ever emits the SGR form (`\e[…m`), but the text being colorized comes
  # out of the scanned repo, so the pattern covers the rest of the escape
  # space too — a route or param string carrying `\e[2J`, `\e[?1049h`, `\ec`
  # or an OSC-8 hyperlink would otherwise be replayed by the terminal of
  # whoever `cat`s the report. Three alternatives, matched in order: CSI
  # (parameter bytes, intermediate bytes, then a final byte in `@`–`~`),
  # OSC (terminated by BEL or ST), and every other escape — optional
  # intermediates and one final byte. CSI and OSC come first so their
  # introducers aren't consumed as a bare two-character escape.
  ANSI_ESCAPE = /\e\[[0-?]*[ -\/]*[@-~]|\e\][^\a\e]*(?:\a|\e\\)|\e[ -\/]*[0-~]/

  # A `?` in a Noir URL is not always a query separator — it is also route
  # syntax (Express `/geo/:ip?`, F# `/legacy(/?)`, a regex route
  # `/grp/(?:a|b)/(.*)?`). Only a `?` that introduces a `key=value` pair
  # before the next path separator opens a query string. Shared by
  # `bake_endpoint`, which appends to a URL, and the builders that take one
  # apart, so the two can never disagree about where the route ends.
  INLINE_QUERY = /\?([^?\/#]*=[^?#]*)/

  # `scheme://authority` at the head of an absolute endpoint URL.
  ROUTE_AUTHORITY = /\A[a-z][a-z0-9+.\-]*:\/\/[^\/]*/i

  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @output_file : String
  @stdout_broken : Bool

  property io : IO

  # Tech analyzers that raised during the scan being reported. Carried as a
  # property rather than a third `print` argument: only three of the thirty
  # builders have anywhere to put it, and the other twenty-seven would have
  # grown a parameter they ignore. Defaults to empty so a builder constructed
  # directly (specs, library callers) reports a clean scan.
  property analyzer_failures : Array(AnalyzerFailure) = [] of AnalyzerFailure

  def initialize(options : Hash(String, YAML::Any))
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @options = options
    # Auto-disable color when STDOUT isn't a terminal — the `only-url`,
    # `only-param`, `only-header`, `only-cookie`, and `only-tag`
    # formats use `.colorize(...).toggle(@is_color)`, which (unlike a
    # bare `.colorize`) bypasses Crystal's TTY auto-detect and emits
    # ANSI codes even into pipes. `noir -f only-url | sort -u` ended up
    # with `\e[93m/sign\e[39m` in the pipe, breaking the downstream
    # tools these formats exist to feed.
    # `--no-color` / `NO_COLOR` (handled at the router) still take
    # precedence; this only flips off the default-on behavior when
    # stdout is redirected.
    @is_color = any_to_bool(options["color"]) && STDOUT.tty?
    @is_log = any_to_bool(options["nolog"])
    @output_file = options["output"].to_s
    @io = STDOUT
    @stdout_broken = false

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log
  end

  def ob_puts(message)
    unless @stdout_broken
      begin
        @io.puts message
      rescue ex : IO::Error
        raise ex unless NoirLogger.broken_pipe?(ex)
        # Downstream reader closed its end (`noir ... | head`, `| jq -e`,
        # ...). Stop writing to it, but keep going below so a run that's
        # both piped and saved via `-o` still ends up with a complete file
        # instead of a truncated one — killing the whole process here
        # would cut the `-o` write off mid-report.
        @stdout_broken = true
      end
    end
    unless @output_file.empty?
      begin
        file = output_handle
        # The stdout copy above keeps its color; the file copy must not.
        # `@is_color` is on whenever stdout is a terminal, so `noir -f
        # only-url -o urls.txt` wrote `\e[93m/sign\e[39m` into urls.txt —
        # the same ANSI-into-a-pipe problem the constructor already fixed
        # for `| sort -u`, just via the other output path.
        file.puts strip_ansi(message.to_s)
        # Flush per line rather than relying on the buffer: a run can be
        # cut short (upstream broken pipe, Ctrl-C) and the `-o` file is the
        # artifact the user asked to keep. One `write` per line is still
        # far cheaper than the open+write+close this replaced.
        file.flush
      rescue e : IO::Error
        STDERR.puts "ERROR: Could not write output file '#{@output_file}': #{e.message}".colorize(:red)
        exit(1)
      end
    end
  end

  private def output_handle : File
    NoirOutputFiles.handle(@output_file)
  end

  # Drops escape sequences from report text on its way to a file, so the
  # saved report is plain text whether the color came from `Colorize` or
  # from the scanned repo.
  #
  # Scope note: this covers the file only. The stdout copy is written raw,
  # because the color codes there are the point and stripping them would
  # have to happen before each builder colorizes rather than after. Escapes
  # that originate in scanned source therefore still reach a terminal —
  # unchanged from before, and true of `NoirLogger`'s output as well.
  private def strip_ansi(message : String) : String
    return message unless message.includes?('\e')

    message.gsub(ANSI_ESCAPE, "")
  end

  def print
    # After inheriting the class, write an action code here.
  end

  # Two-argument entry point every `-f` format answers to, so
  # `Noir::OutputFormats.render` can hand each builder the same pair.
  # Formats with nothing to say about passive findings inherit this and
  # implement only `print(endpoints)`.
  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    print(endpoints)
  end

  # The block form of `NoirLogger#debug`, not the String one: `bake_endpoint`
  # runs once per endpoint for most builders, and the String overload would
  # build all seven of these messages on every call only for the logger to
  # drop them with debug off.
  def bake_endpoint(url : String, params : Array(Param))
    @logger.debug { "Baking endpoint #{url} with #{params.size} params." }

    final_url = url
    final_body = ""
    final_path_params = [] of String
    final_headers = [] of String
    final_cookies = [] of String
    final_tags = [] of String
    is_json = false
    first_form = true

    if final_url.starts_with?("//")
      if final_url.size != 2 && final_url[2] != ':'
        final_url = final_url[1..]
      end
    end

    # A route can arrive carrying its own query string —
    # `/wp-admin/admin-ajax.php?action=get_user_data` is how WordPress
    # addresses an AJAX handler, and the analyzer records `action` as a query
    # param on top of it. Opening the baked params with another `?` produced
    # `...?action=get_user_data?action=get_user_data`, where the second `?`
    # and everything after it is swallowed into the first value: a URL that no
    # longer addresses the endpoint, in every format that bakes one (plain,
    # only-url, curl, httpie, powershell, html, adb, simctl).
    #
    # `?` here does not always open a query string — it is also route syntax
    # (Express `/geo/:ip?`, regex routes `/grp/(?:a|b)`). Only a `?` that
    # introduces a `key=value` pair before the next path separator does.
    existing_query = final_url.match(INLINE_QUERY).try(&.[1])
    existing_pairs = existing_query.try(&.split('&')) || [] of String
    existing_names = existing_pairs.map { |pair| pair.split('=', 2)[0] }
    first_query = existing_query.nil?

    unless params.nil?
      params.each do |param|
        if param.request_type == "query"
          pair = "#{param.name}=#{param.value}"
          # A pair the route already spells out verbatim adds nothing, and
          # neither does a value-less declaration of a name the route already
          # pins — the analyzer records `action` precisely *because* the route
          # spells `action=save_settings`. Appending `&action=` there would
          # blank the value out, since the later pair is the one servers read:
          # the URL would stop addressing the handler it was found on.
          #
          # A *different, non-empty* value is a real override (`--pvalue
          # query=…`) and is still appended, for that same last-pair-wins
          # reason. Skipping with `next` would also skip this param's tag
          # collection at the bottom of the block.
          redundant = existing_pairs.includes?(pair) ||
                      (param.value.empty? && existing_names.includes?(param.name))
          unless redundant
            if first_query
              final_url += "?#{pair}"
              first_query = false
            else
              final_url += "&#{pair}"
            end
          end
        end

        if param.request_type == "form"
          if first_form
            final_body += "#{param.name}=#{param.value}"
            first_form = false
          else
            final_body += "&#{param.name}=#{param.value}"
          end
        end

        if param.request_type == "path"
          # `name=value`, like the cookie row and the form body below. The
          # value was dropped here, so the plain report printed a bare
          # `path: userId` while `-f json` carried `"value": "Integer"` —
          # 42 path params across the fixture tree lost the only thing the
          # analyzer knew about them beyond the name.
          #
          # A value equal to the name is skipped: Giraffe's `%i`/`%s` route
          # format names a segment after its own type, and `path: int=int`
          # says nothing the name did not.
          redundant_value = param.value.empty? || param.value == param.name
          final_path_params << (redundant_value ? param.name : "#{param.name}=#{param.value}")
        end

        if param.request_type == "header"
          final_headers << "#{param.name}: #{param.value}"
        end

        if param.request_type == "cookie"
          final_cookies << "#{param.name}=#{param.value}"
        end

        if param.request_type == "json"
          is_json = true
        end

        unless param.tags.empty?
          param.tags.each do |tag|
            final_tags << tag.name
          end
        end
      end

      if is_json
        json_tmp = Hash(String, String).new

        params.each do |param|
          if param.request_type == "json"
            json_tmp[param.name] = param.value
          end
        end

        final_body = json_tmp.to_json
      end
    end

    @logger.debug { "Baked endpoints" }
    @logger.debug { " + Final URL: #{final_url}" }
    @logger.debug { " + Path Params: #{final_path_params}" }
    @logger.debug { " + Body: #{final_body}" }
    @logger.debug { " + Headers: #{final_headers}" }
    @logger.debug { " + Cookies: #{final_cookies}" }
    @logger.debug { " + Tags: #{final_tags}" }

    {
      url:        final_url,
      body:       final_body,
      path_param: final_path_params,
      header:     final_headers,
      cookie:     final_cookies,
      tags:       final_tags.uniq,
      body_type:  is_json ? "json" : "form",
    }
  end

  # Splits a Noir endpoint URL into the route itself and the two parts a
  # `paths` key / Postman URL cannot hold: the query string the route spells
  # out (`admin-ajax.php?action=save_settings`, how WordPress addresses an
  # AJAX handler) and the `#fragment` Noir uses to address many operations on
  # one path (`POST /graphql#Query.users`, `POST /rpc#eth_getBalance`).
  #
  # Deliberately not `URI.parse`: an endpoint URL is a route *pattern*, not a
  # URI. `URI.parse` reads the `?` in `/grp/(?:a|b)/(.*)?` as a query
  # separator, truncating the path to `/grp/(` and handing back a query
  # parameter named `:a|b)/(.*)?` that nothing ever declared.
  protected def split_route_url(url : String) : NamedTuple(route: String, query: Array(Tuple(String, String)), fragment: String?)
    route = url
    query = [] of Tuple(String, String)

    if match = route.match(INLINE_QUERY)
      query = match[1].split('&').compact_map do |pair|
        next if pair.empty?
        name, _, value = pair.partition('=')
        {name, value}
      end
      route = route[0...match.begin] + route[match.end..]
    end

    fragment = nil
    if index = route.index('#')
      candidate = route[(index + 1)..]
      fragment = candidate unless candidate.empty?
      route = route[0...index]
    end

    {route: route, query: query, fragment: fragment}
  end

  # `scheme://host[:port]` when the route is absolute, nil when it is a bare
  # path. Absolute endpoint URLs are real — an OpenAPI `servers` entry, a HAR
  # capture spanning domains — and the host is the only thing telling
  # `demo.example.com` from `demo.example.com.evil`.
  protected def route_authority(route : String) : String?
    route.match(ROUTE_AUTHORITY).try(&.[0])
  end

  # The path portion of a route, with any `scheme://authority` prefix removed.
  # Textual rather than `URI#path` for the same reason as `split_route_url`.
  protected def route_path(route : String) : String
    authority = route_authority(route)
    return route unless authority

    tail = route[authority.size..]
    tail.empty? ? "/" : tail
  end

  protected def noir_callee_json(callee : Callee) : JSON::Any
    data = {
      "name" => JSON::Any.new(callee.name),
    } of String => JSON::Any

    if path = callee.path
      data["path"] = JSON::Any.new(path)
    end

    if line = callee.line
      data["line"] = JSON::Any.new(line.to_i64)
    end

    JSON::Any.new(data)
  end

  protected def noir_callees_json(endpoint : Endpoint) : Array(JSON::Any)
    endpoint.callees.map { |callee| noir_callee_json(callee) }
  end

  protected def add_noir_callees_extension(operation : Hash(String, JSON::Any), endpoint : Endpoint)
    return if endpoint.callees.empty?

    operation["x-noir-callees"] = JSON::Any.new(noir_callees_json(endpoint))
  end

  protected def noir_ai_context_entry_json(entry : AIContextEntry) : JSON::Any
    data = {
      "kind" => JSON::Any.new(entry.kind),
      "name" => JSON::Any.new(entry.name),
    } of String => JSON::Any

    if source = entry.source
      data["source"] = JSON::Any.new(source)
    end

    if description = entry.description
      data["description"] = JSON::Any.new(description)
    end

    if path = entry.path
      data["path"] = JSON::Any.new(path)
    end

    if line = entry.line
      data["line"] = JSON::Any.new(line.to_i64)
    end

    if confidence = entry.confidence
      data["confidence"] = JSON::Any.new(confidence.to_i64)
    end

    if snippet = entry.snippet
      data["snippet"] = JSON::Any.new(snippet)
    end

    JSON::Any.new(data)
  end

  protected def noir_ai_context_json(endpoint : Endpoint) : JSON::Any?
    context = endpoint.ai_context
    return unless context
    return if context.empty?

    JSON::Any.new({
      "guards"     => JSON::Any.new(context.guards.map { |entry| noir_ai_context_entry_json(entry) }),
      "callees"    => JSON::Any.new(context.callees.map { |entry| noir_ai_context_entry_json(entry) }),
      "sources"    => JSON::Any.new(context.sources.map { |entry| noir_ai_context_entry_json(entry) }),
      "sinks"      => JSON::Any.new(context.sinks.map { |entry| noir_ai_context_entry_json(entry) }),
      "validators" => JSON::Any.new(context.validators.map { |entry| noir_ai_context_entry_json(entry) }),
      "signals"    => JSON::Any.new(context.signals.map { |entry| noir_ai_context_entry_json(entry) }),
    } of String => JSON::Any)
  end

  protected def add_noir_ai_context_extension(operation : Hash(String, JSON::Any), endpoint : Endpoint)
    context_json = noir_ai_context_json(endpoint)
    if context_json
      operation["x-noir-ai-context"] = context_json
    end
  end

  protected def noir_callees_description(endpoint : Endpoint) : String?
    return if endpoint.callees.empty?

    lines = ["Noir callees:"]
    endpoint.callees.each do |callee|
      lines << "- #{format_noir_callee(callee)}"
    end
    lines.join("\n")
  end

  protected def noir_ai_context_description(endpoint : Endpoint) : String?
    context = endpoint.ai_context
    return unless context
    return if context.empty?

    lines = ["Noir AI context:"]
    append_ai_context_description(lines, "guards", context.guards)
    append_ai_context_description(lines, "callees", context.callees)
    append_ai_context_description(lines, "sources", context.sources)
    append_ai_context_description(lines, "sinks", context.sinks)
    append_ai_context_description(lines, "validators", context.validators)
    append_ai_context_description(lines, "signals", context.signals)
    lines.join("\n")
  end

  # `(path:line)` / `(path)` / `(line N)`, or nil when neither is known.
  # Callees and AI-context entries both render a source location and used
  # to spell this out separately, so a change to one (making paths relative
  # to the scan root, say) could silently leave the other behind.
  private def format_location(path : String?, line : Int32?) : String?
    return "(#{path}:#{line})" if path && line
    return "(#{path})" if path
    return "(line #{line})" if line

    nil
  end

  private def format_noir_callee(callee : Callee) : String
    location = format_location(callee.path, callee.line)
    location ? "#{callee.name} #{location}" : callee.name
  end

  # One-line rendering of an AI-context entry, shared by the plain-text
  # report (OutputBuilderCommon) and the Postman item description. The two
  # had separate copies that disagreed on where `[source]` goes, so the same
  # entry read differently depending on the format; `[source]` sits next to
  # the name — the terminal ordering, and the more widely seen of the two.
  protected def format_ai_context_entry(entry : AIContextEntry) : String
    String.build do |label|
      label << entry.kind << ": " << entry.name
      label << " [" << entry.source << ']' if entry.source
      if location = format_location(entry.path, entry.line)
        label << ' ' << location
      end
      label << " - " << entry.description if entry.description
      label << " :: " << entry.snippet if entry.snippet
    end
  end

  private def append_ai_context_description(lines : Array(String), label : String, entries : Array(AIContextEntry))
    return if entries.empty?

    lines << "- #{label}:"
    entries.each do |entry|
      lines << "  - #{format_ai_context_entry(entry)}"
    end
  end

  getter logger, output_file
end
