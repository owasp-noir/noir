require "../../spec_helper"
require "../../../src/models/output_builder.cr"
require "../../../src/output_builder/*"

describe "Initialize" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options["format"] = YAML::Any.new("json")
  options["output"] = YAML::Any.new("output.json")

  it "OutputBuilder" do
    object = OutputBuilder.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderCommon" do
    object = OutputBuilderCommon.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderCurl" do
    object = OutputBuilderCurl.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderHttpie" do
    object = OutputBuilderHttpie.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderMarkdownTable" do
    object = OutputBuilderMarkdownTable.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOas2" do
    object = OutputBuilderOas2.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOas3" do
    object = OutputBuilderOas3.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyUrl" do
    object = OutputBuilderOnlyUrl.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyParam" do
    object = OutputBuilderOnlyParam.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyHeader" do
    object = OutputBuilderOnlyHeader.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderOnlyCookie" do
    object = OutputBuilderOnlyCookie.new options
    object.output_file.should eq("output.json")
  end

  it "OutputBuilderJsonl" do
    object = OutputBuilderJsonl.new options
    object.output_file.should eq("output.json")
  end

  it "truncates an output file on first write and appends later writes" do
    output_file = File.tempname("noir-output-builder")
    File.write(output_file, "old\n")

    begin
      file_options = create_test_options
      file_options["output"] = YAML::Any.new(output_file)

      object = OutputBuilder.new file_options
      object.io = IO::Memory.new
      object.ob_puts "new"
      object.ob_puts "next"

      File.read(output_file).should eq("new\nnext\n")
    ensure
      NoirOutputFiles.reset
      File.delete(output_file) if File.exists?(output_file)
    end
  end

  # One run writes a single `-o` file from *different* builder classes: the
  # diff builder emits its section headers, then delegates the endpoint list
  # to OutputBuilderCommon. Only the first writer may truncate. Crystal gives
  # every subclass its own copy of an inherited class variable, so the
  # per-class truncation bookkeeping this replaces let the second class wipe
  # the first class's output — the "✚ Added" header never reached the file.
  it "appends when a different builder class writes to the same output file" do
    output_file = File.tempname("noir-output-builder-shared")

    begin
      file_options = create_test_options
      file_options["output"] = YAML::Any.new(output_file)

      header = OutputBuilderDiff.new file_options
      header.io = IO::Memory.new
      header.ob_puts "section-header"

      body = OutputBuilderCommon.new file_options
      body.io = IO::Memory.new
      body.ob_puts "endpoint-line"

      File.read(output_file).should eq("section-header\nendpoint-line\n")
    ensure
      NoirOutputFiles.reset
      File.delete(output_file) if File.exists?(output_file)
    end
  end

  # `@is_color` is on whenever stdout is a terminal, so a colorized report
  # used to carry its ANSI codes straight into `-o`. STDOUT keeps the color;
  # the file must not.
  it "strips ANSI color codes from the output file but not from stdout" do
    output_file = File.tempname("noir-output-builder-ansi")

    begin
      file_options = create_test_options
      file_options["output"] = YAML::Any.new(output_file)

      object = OutputBuilder.new file_options
      io = IO::Memory.new
      object.io = io
      object.ob_puts "\e[93m/sign\e[39m"

      File.read(output_file).should eq("/sign\n")
      io.to_s.should eq("\e[93m/sign\e[39m\n")
    ensure
      NoirOutputFiles.reset
      File.delete(output_file) if File.exists?(output_file)
    end
  end

  # The text being colorized is endpoint data lifted out of the scanned
  # repo, so the file copy has to survive escapes `Colorize` would never
  # produce — otherwise a crafted route string is replayed by the terminal
  # of whoever `cat`s the report.
  it "strips non-SGR escape sequences from the output file" do
    output_file = File.tempname("noir-output-builder-escapes")

    begin
      file_options = create_test_options
      file_options["output"] = YAML::Any.new(output_file)

      object = OutputBuilder.new file_options
      object.io = IO::Memory.new
      object.ob_puts "\e[2J/clear"             # CSI, non-SGR final byte
      object.ob_puts "\e[?1049h/altscreen"     # CSI with a private parameter byte
      object.ob_puts "\e]8;;http://evil\a/osc" # OSC 8 hyperlink, BEL-terminated
      object.ob_puts "\ec/reset"               # two-character escape

      File.read(output_file).should eq("/clear\n/altscreen\n/osc\n/reset\n")
    ensure
      NoirOutputFiles.reset
      File.delete(output_file) if File.exists?(output_file)
    end
  end
end

describe OutputBuilderDiff do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options["format"] = YAML::Any.new("json")

  it "calculates the diff correctly" do
    old_endpoints = [Endpoint.new("GET", "/old")]
    new_endpoints = [Endpoint.new("GET", "/new")]
    builder = OutputBuilderDiff.new options

    result = builder.diff(new_endpoints, old_endpoints)

    result[:added].should eq [Endpoint.new("GET", "/new")]
    result[:removed].should eq [Endpoint.new("GET", "/old")]
  end

  it "calculates the diff correctly with multiple endpoints" do
    old_endpoints = [Endpoint.new("GET", "/old"), Endpoint.new("GET", "/old2")]
    new_endpoints = [Endpoint.new("GET", "/new"), Endpoint.new("GET", "/new2")]
    builder = OutputBuilderDiff.new options

    result = builder.diff(new_endpoints, old_endpoints)

    result[:added].should eq [Endpoint.new("GET", "/new"), Endpoint.new("GET", "/new2")]
    result[:removed].should eq [Endpoint.new("GET", "/old"), Endpoint.new("GET", "/old2")]
  end

  it "calculates the diff correctly with multiple endpoints and different methods" do
    old_endpoints = [Endpoint.new("GET", "/old"), Endpoint.new("POST", "/old2")]
    new_endpoints = [Endpoint.new("GET", "/new"), Endpoint.new("POST", "/new2")]
    builder = OutputBuilderDiff.new options

    result = builder.diff(new_endpoints, old_endpoints)

    result[:added].should eq [Endpoint.new("GET", "/new"), Endpoint.new("POST", "/new2")]
    result[:removed].should eq [Endpoint.new("GET", "/old"), Endpoint.new("POST", "/old2")]
  end

  it "calculates the diff correctly with multiple endpoints and different methods and params" do
    old_endpoints = [Endpoint.new("GET", "/old", [Param.new("a", "b", "query"), Param.new("c", "d", "json")])]
    new_endpoints = [Endpoint.new("GET", "/new", [Param.new("e", "f", "query"), Param.new("g", "h", "json")])]
    builder = OutputBuilderDiff.new options

    result = builder.diff(new_endpoints, old_endpoints)

    result[:added].should eq [Endpoint.new("GET", "/new", [Param.new("e", "f", "query"), Param.new("g", "h", "json")])]
    result[:removed].should eq [Endpoint.new("GET", "/old", [Param.new("a", "b", "query"), Param.new("c", "d", "json")])]
  end
end

describe "OutputBuilder#bake_endpoint" do
  options = create_test_options
  builder = OutputBuilder.new options

  it "opens the query string with ? and separates the rest with &" do
    baked = builder.bake_endpoint("/search", [Param.new("q", "1", "query"), Param.new("page", "2", "query")])
    baked[:url].should eq("/search?q=1&page=2")
  end

  it "appends to a query string the route already carries" do
    # WordPress addresses an AJAX handler as `admin-ajax.php?action=…`; a
    # second `?` would swallow everything after it into the first value.
    baked = builder.bake_endpoint("/admin-ajax.php?action=x", [Param.new("id", "1", "query")])
    baked[:url].should eq("/admin-ajax.php?action=x&id=1")
  end

  it "skips a query pair the route already spells out verbatim" do
    baked = builder.bake_endpoint("/admin-ajax.php?action=x", [Param.new("action", "x", "query")])
    baked[:url].should eq("/admin-ajax.php?action=x")
  end

  it "still appends an overridden value for a name already in the query" do
    baked = builder.bake_endpoint("/admin-ajax.php?action=x", [Param.new("action", "FUZZ", "query")])
    baked[:url].should eq("/admin-ajax.php?action=x&action=FUZZ")
  end

  it "treats route-syntax ? as part of the path, not as a query string" do
    # Express optional segments (`/geo/:ip?`) and regex routes (`(?:a|b)`)
    # both spell a `?` that opens no query string. Appending the query with
    # a second `?` said so only to noir: RFC 3986 gives the query to the
    # *first* `?`, so `/geo/:ip??q=1` reached the server as one parameter
    # named `?q`. Percent-encoding keeps the route's `?` in the path, which
    # is what this case has always claimed to do.
    builder.bake_endpoint("/geo/:ip?", [Param.new("q", "1", "query")])[:url]
      .should eq("/geo/:ip%3F?q=1")
    builder.bake_endpoint("/grp/(?:a|b)", [Param.new("q", "1", "query")])[:url]
      .should eq("/grp/(%3F:a|b)?q=1")
  end

  it "leaves a route-syntax ? alone when there is no query to append" do
    builder.bake_endpoint("/geo/:ip?", [] of Param)[:url].should eq("/geo/:ip?")
    builder.bake_endpoint("/geo/:ip?", [Param.new("X-Trace", "1", "header")])[:url]
      .should eq("/geo/:ip?")
  end

  it "encodes a route-syntax ? that precedes the route's own query string" do
    builder.bake_endpoint("/geo/:ip?/lookup.php?action=go", [] of Param)[:url]
      .should eq("/geo/:ip%3F/lookup.php?action=go")
  end

  it "keeps tags from a query param that was skipped as redundant" do
    param = Param.new("action", "x", "query")
    param.add_tag(Tag.new("pii", "personal data", "metadata_tagger"))
    builder.bake_endpoint("/a.php?action=x", [param])[:tags].should eq(["pii"])
  end
end
