require "../../spec_helper"
require "../../../src/output_builder/diff"
require "../../../src/models/endpoint"
require "../../../src/models/noir"
require "../../../src/utils/utils"

describe "OutputBuilderDiff" do
  describe "diff" do
    it "correctly identifies added endpoints" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderDiff.new(options)

      new_endpoints = [
        Endpoint.new("/test", "GET"),
        Endpoint.new("/api/users", "POST"),
      ]
      old_endpoints = [
        Endpoint.new("/test", "GET"),
      ]

      result = builder.diff(new_endpoints, old_endpoints)

      result[:added].size.should eq(1)
      result[:added][0].url.should eq("/api/users")
      result[:added][0].method.should eq("POST")
      result[:removed].size.should eq(0)
      result[:changed].size.should eq(0)
    end

    it "correctly identifies removed endpoints" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderDiff.new(options)

      new_endpoints = [
        Endpoint.new("/test", "GET"),
      ]
      old_endpoints = [
        Endpoint.new("/test", "GET"),
        Endpoint.new("/api/users", "POST"),
      ]

      result = builder.diff(new_endpoints, old_endpoints)

      result[:added].size.should eq(0)
      result[:removed].size.should eq(1)
      result[:removed][0].url.should eq("/api/users")
      result[:removed][0].method.should eq("POST")
      result[:changed].size.should eq(0)
    end

    it "correctly identifies changed endpoints" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderDiff.new(options)

      new_endpoint = Endpoint.new("/test", "GET")
      new_endpoint.push_param(Param.new("id", "1", "query"))

      old_endpoint = Endpoint.new("/test", "GET")
      # No params in old endpoint

      result = builder.diff([new_endpoint], [old_endpoint])

      result[:added].size.should eq(0)
      result[:removed].size.should eq(0)
      result[:changed].size.should eq(1)
      result[:changed][0].url.should eq("/test")
      result[:changes].size.should eq(1)
      result[:changes][0].params_added.map { |p| {p.name, p.param_type} }.should eq([{"id", "query"}])
      result[:changes][0].params_removed.should be_empty
    end

    it "does not report a route whose params differ only in value" do
      builder = OutputBuilderDiff.new(create_test_options)

      new_endpoint = Endpoint.new("/test", "GET")
      new_endpoint.push_param(Param.new("id", "2", "query"))
      old_endpoint = Endpoint.new("/test", "GET")
      old_endpoint.push_param(Param.new("id", "1", "query"))

      result = builder.diff([new_endpoint], [old_endpoint])

      result[:changed].should be_empty
      result[:changes].should be_empty
    end

    it "matches params by name and request type, so body and json are one param" do
      builder = OutputBuilderDiff.new(create_test_options)

      new_endpoint = Endpoint.new("/test", "POST")
      new_endpoint.push_param(Param.new("name", "", "json"))
      new_endpoint.push_param(Param.new("id", "", "header"))
      old_endpoint = Endpoint.new("/test", "POST")
      old_endpoint.push_param(Param.new("name", "", "body"))
      old_endpoint.push_param(Param.new("id", "", "query"))

      change = builder.diff([new_endpoint], [old_endpoint])[:changes].first

      change.params_added.map { |p| {p.name, p.param_type} }.should eq([{"id", "header"}])
      change.params_removed.map { |p| {p.name, p.param_type} }.should eq([{"id", "query"}])
    end

    it "flags a route that lost its auth tag" do
      builder = OutputBuilderDiff.new(create_test_options)

      new_endpoint = Endpoint.new("/admin", "GET")
      new_endpoint.add_tag(Tag.new("cors", "", "cors"))
      old_endpoint = Endpoint.new("/admin", "GET")
      old_endpoint.add_tag(Tag.new("auth", "Protected by login_required", "flask_auth"))

      change = builder.diff([new_endpoint], [old_endpoint])[:changes].first

      change.auth_removed?.should be_true
      change.tags_removed.should eq(["auth"])
      change.tags_added.should eq(["cors"])
    end

    it "ignores a tag that moved between taggers under the same name" do
      builder = OutputBuilderDiff.new(create_test_options)

      new_endpoint = Endpoint.new("/admin", "GET")
      new_endpoint.add_tag(Tag.new("auth", "", "python_misc_auth"))
      old_endpoint = Endpoint.new("/admin", "GET")
      old_endpoint.add_tag(Tag.new("auth", "", "flask_auth"))

      builder.diff([new_endpoint], [old_endpoint])[:changed].should be_empty
    end

    it "handles empty endpoint arrays" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderDiff.new(options)

      result = builder.diff([] of Endpoint, [] of Endpoint)

      result[:added].size.should eq(0)
      result[:removed].size.should eq(0)
      result[:changed].size.should eq(0)
    end

    it "matches endpoints by url and method combination" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderDiff.new(options)

      new_endpoints = [
        Endpoint.new("/test", "GET"),
        Endpoint.new("/test", "POST"),
      ]
      old_endpoints = [
        Endpoint.new("/test", "GET"),
      ]

      result = builder.diff(new_endpoints, old_endpoints)

      # POST /test should be added, GET /test should be unchanged
      result[:added].size.should eq(1)
      result[:added][0].method.should eq("POST")
      result[:removed].size.should eq(0)
      result[:changed].size.should eq(0)
    end
  end

  # `diff` itself has no emptiness gate — the `.size > 0` -> `!.empty?`
  # conversion (#1121) lives in `print` and `generate_toml_from_diff`,
  # which skip a section entirely when its bucket is empty. Assert on the
  # rendered output so the gate is what's actually covered.
  describe "section gating" do
    it "says there is nothing to report when every bucket is empty" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new

      endpoints = [
        Endpoint.new("/test", "GET"),
        Endpoint.new("/api/users", "POST"),
      ]
      diff_app = NoirRunner.new(create_test_options)
      diff_app.endpoints.concat(endpoints)

      builder.print(builder.diff(endpoints, diff_app.endpoints))

      builder.io.to_s.should eq("No endpoint was added, removed or changed.\n")
    end

    it "does not open a report with a blank line when the first section is not Added" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new

      diff_app = NoirRunner.new(create_test_options)
      diff_app.endpoints << Endpoint.new("/gone", "GET")
      builder.print(builder.diff([] of Endpoint, diff_app.endpoints))

      builder.io.to_s.should start_with("─")
      builder.io.to_s.should contain("Removed (1)")
    end

    it "renders only the sections whose bucket is populated" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new

      diff_app = NoirRunner.new(create_test_options)
      diff_app.endpoints << Endpoint.new("/test", "GET")

      # POST /api/users is new, GET /test is gone, nothing changed in place.
      builder.print_toml(builder.diff([Endpoint.new("/api/users", "POST")], diff_app.endpoints))

      output = builder.io.to_s
      output.should contain("[added]")
      output.should contain("[removed]")
      output.should_not contain("[changed]")
    end

    it "quotes a metadata key that is not a bare TOML key" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new

      # This builder used to emit keys raw, so a key containing a dot would be
      # read as a dotted table path (`path.permissions` -> [path].permissions)
      # and corrupt the document. Endpoint field names are all bare-safe, but
      # `metadata` keys come from analyzers, so the quoting has to be here.
      endpoint = Endpoint.new("content://com.example/items", "GET")
      endpoint.protocol = "android-provider"
      endpoint.metadata = {"path.permissions" => "read"}

      builder.print_toml(builder.diff([endpoint], [] of Endpoint))
      output = builder.io.to_s

      output.should contain(%("path.permissions" = "read"))
      output.should_not contain(%(path.permissions = "read"))
    end
  end

  describe "machine format output byte 0" do
    it "does not start json diff with a leading newline" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new

      endpoints = [Endpoint.new("/test", "GET")]
      diff_app = NoirRunner.new(create_test_options)

      builder.print_json(builder.diff(endpoints, diff_app.endpoints))
      output = builder.io.to_s

      output[0].should eq('{')
      output.should_not start_with("\n")
    end

    it "does not start yaml diff with a leading newline" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new

      endpoints = [Endpoint.new("/test", "GET")]
      diff_app = NoirRunner.new(create_test_options)

      builder.print_yaml(builder.diff(endpoints, diff_app.endpoints))
      output = builder.io.to_s

      output.should_not start_with("\n")
      (output.starts_with?("---") || output.starts_with?("added:")).should be_true
    end

    it "does not start toml diff with a leading newline" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new

      endpoints = [Endpoint.new("/test", "GET")]
      diff_app = NoirRunner.new(create_test_options)

      builder.print_toml(builder.diff(endpoints, diff_app.endpoints))
      output = builder.io.to_s

      output[0].should eq('[')
      output.should_not start_with("\n")
    end
  end

  describe "change details in the rendered report" do
    it "lists what changed under a changed endpoint in the text report" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new

      old_endpoint = Endpoint.new("/admin", "GET")
      old_endpoint.push_param(Param.new("token", "", "header"))
      old_endpoint.add_tag(Tag.new("auth", "", "flask_auth"))
      diff_app = NoirRunner.new(create_test_options)
      diff_app.endpoints << old_endpoint

      new_endpoint = Endpoint.new("/admin", "GET")
      new_endpoint.push_param(Param.new("q", "", "query"))
      builder.print(builder.diff([new_endpoint], diff_app.endpoints))
      output = builder.io.to_s

      output.should contain("Changed (1)")
      output.should contain("! auth tag removed")
      output.should contain("+ query: q")
      output.should contain("- header: token")
      # The auth row already says it; a second `- tag: auth` is noise.
      output.should_not contain("- tag: auth")
    end

    it "emits the change records next to the endpoints in json" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new

      diff_app = NoirRunner.new(create_test_options)
      diff_app.endpoints << Endpoint.new("/a", "GET")
      new_endpoint = Endpoint.new("/a", "GET")
      new_endpoint.push_param(Param.new("id", "", "path"))

      builder.print_json(builder.diff([new_endpoint], diff_app.endpoints))
      json = JSON.parse(builder.io.to_s)

      json["changed"].as_a.size.should eq(1)
      change = json["changes"].as_a.first
      change["url"].should eq("/a")
      change["params_added"].as_a.first["name"].should eq("id")
      change["auth_removed"].as_bool.should be_false
    end

    it "names change records as change tables in toml" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new

      diff_app = NoirRunner.new(create_test_options)
      diff_app.endpoints << Endpoint.new("/a", "GET")
      new_endpoint = Endpoint.new("/a", "GET")
      new_endpoint.push_param(Param.new("id", "", "query"))

      builder.print_toml(builder.diff([new_endpoint], diff_app.endpoints))
      output = builder.io.to_s

      output.should contain("[[changed.endpoint]]")
      output.should contain("[[changes.change]]")
    end
  end

  describe "pull request formats" do
    # new: GET /profile lost auth, POST /new added, GET /search gained `q`;
    # old: DELETE /gone removed.
    fixture = -> do
      old_profile = Endpoint.new("/profile", "GET", Details.new(PathInfo.new("app.py", 14)))
      old_profile.add_tag(Tag.new("auth", "", "flask_auth"))
      old_endpoints = [old_profile, Endpoint.new("/search", "GET"), Endpoint.new("/gone", "DELETE")]

      new_search = Endpoint.new("/search", "GET", Details.new(PathInfo.new("app.py", 20)))
      new_search.push_param(Param.new("q", "", "query"))
      new_added = Endpoint.new("/new|pipe", "POST", Details.new(PathInfo.new("app.py", 30)))
      new_added.push_param(Param.new("x", "", "form"))
      new_endpoints = [Endpoint.new("/profile", "GET", Details.new(PathInfo.new("app.py", 14))), new_search, new_added]

      OutputBuilderDiff.new(create_test_options).diff(new_endpoints, old_endpoints)
    end

    it "counts each --fail-on category" do
      counts = OutputBuilderDiff.gate_counts(fixture.call)
      counts.should eq({"added" => 1, "removed" => 1, "changed" => 2, "auth-removed" => 1})
    end

    it "renders a markdown summary with the lost-auth routes first" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new
      builder.print_markdown(fixture.call)
      output = builder.io.to_s

      output.should contain("| 1 | 1 | 2 | 1 |")
      output.index!("Auth removed").should be < output.index!("### Added")
      output.should contain("| `GET /profile` | app.py:14 |")
      # A pipe in a route must not split the table row.
      output.should contain("`POST /new\\|pipe`")
      output.should contain("| `POST /new\\|pipe` | `x (form)` | app.py:30 |")
      output.should contain("| `DELETE /gone` | - |")
      output.should contain("added `q (query)`")
    end

    it "says so when nothing changed" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new
      builder.print_markdown(builder.diff([Endpoint.new("/a", "GET")], [Endpoint.new("/a", "GET")]))

      builder.io.to_s.should contain("No endpoint was added, removed or changed.")
      builder.io.to_s.should_not contain("| Added |")
    end

    it "annotates only the new surface in sarif" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new
      builder.print_sarif(fixture.call)
      run = JSON.parse(builder.io.to_s)["runs"][0]

      results = run["results"].as_a.map { |r| {r["ruleId"].as_s, r["level"].as_s} }
      results.should eq([
        {"diff-endpoint-added", "note"},
        {"diff-auth-removed", "warning"},
        {"diff-params-added", "note"},
      ])
      # DELETE /gone has no line left in the reviewed tree to point at.
      run["results"].as_a.none? { |r| r["message"]["text"].as_s.includes?("/gone") }.should be_true
      run["results"][1]["locations"][0]["physicalLocation"]["region"]["startLine"].should eq(14)
    end

    it "marks the sarif run unsuccessful when either scan lost an analyzer" do
      builder = OutputBuilderDiff.new(create_test_options)
      builder.io = IO::Memory.new
      builder.analyzer_failures = [AnalyzerFailure.new("python_flask", "boom")]
      builder.print_sarif(fixture.call)

      JSON.parse(builder.io.to_s)["runs"][0]["invocations"][0]["executionSuccessful"].as_bool.should be_false
    end
  end
end
