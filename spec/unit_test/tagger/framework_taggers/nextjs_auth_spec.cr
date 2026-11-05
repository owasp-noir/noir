require "../../../spec_helper"
require "../../../../src/tagger/tagger"
require "file_utils"

describe "NextjsAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/javascript/nextjs_auth", __DIR__)

  tag = ->(file : String, line : Int32) do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    details = Details.new(PathInfo.new("#{fixture_base}/#{file}", line))
    details.technology = "js_nextjs"
    endpoint = Endpoint.new("/x", "GET", [] of Param, details)
    NextjsAuthTagger.new(noir_options).perform([endpoint])
    endpoint.tags
  end

  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags an app-router handler that replies 401 without a session" do
    tags = tag.call("app/api/me/route.ts", 4)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("if (!session?.user)")
  end

  it "follows a helper that refuses when the token check answers an error message" do
    tags = tag.call("pages/api/token-helper.ts", 4)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("verifyUser")
  end

  it "does not take a type check of the body for a caller check" do
    tag.call("pages/api/typeof-input.ts", 4).should be_empty
  end

  it "does not take a type check that refuses the caller holding a token for a guard" do
    tag.call("pages/api/typeof-inverse.ts", 5).should be_empty
  end

  it "tags a handler that compares the caller's key with a process.env secret" do
    tag.call("app/api/cron/route.ts", 3).map(&.name).should eq(["auth"])
  end

  it "tags a pages-router handler that sets res.status(401)" do
    tag.call("pages/api/profile.ts", 4).map(&.name).should eq(["auth"])
  end

  it "leaves a login route's credential failure untagged" do
    tag.call("app/api/login/route.ts", 4).should be_empty
  end

  it "tags a pages-router handler whose only verb branch refuses others with 405" do
    tag.call("pages/api/settings.ts", 4).map(&.name).should eq(["auth"])
  end

  it "reads a Prettier-wrapped 401 reply up to its if" do
    tag.call("app/api/wrapped/route.ts", 4).map(&.name).should eq(["auth"])
  end

  it "leaves a shared pages-router handler untagged when a verb branch returns first" do
    tag.call("pages/api/shared.ts", 4).should be_empty
  end

  it "stops at the handler's own closing brace" do
    tag.call("app/api/public/route.ts", 4).should be_empty
    tag.call("app/api/public/route.ts", 21).map(&.name).should eq(["auth"])
  end

  it "ignores a closed if, a commented condition and a non-secret env comparison above a 401" do
    tag.call("app/api/public/route.ts", 8).should be_empty
  end

  it "tags a 403 for a key that is in none of the accepted env secrets" do
    tags = tag.call("app/api/cron-key/route.ts", 3)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("replies 403")
  end

  it "leaves a refusal of the caller who has the key untagged" do
    tag.call("app/api/cron-key/route.ts", 11).should be_empty
  end

  it "tags a handler whose first statements call a same-file helper that throws 401" do
    tags = tag.call("app/api/helper/route.ts", 13)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("authMiddleware()")
  end

  it "tags a handler calling an imported helper that refuses a wrong cron key" do
    tag.call("app/api/helper/route.ts", 25).map(&.name).should eq(["auth"])
  end

  it "leaves a helper called under a branch, or one refusing a signed-in caller, untagged" do
    tag.call("app/api/helper/route.ts", 18).should be_empty
    tag.call("app/api/helper/route.ts", 30).should be_empty
  end

  it "leaves a check after a write, and a dropped returned 401, untagged" do
    tag.call("app/api/order/route.ts", 5).should be_empty
    tag.call("app/api/order/route.ts", 12).should be_empty
  end

  it "tags a returned 401 the handler hands on" do
    tag.call("app/api/order/route.ts", 19).map(&.name).should eq(["auth"])
  end

  it "leaves a list with a public value, and a NEXT_PUBLIC_ key, untagged" do
    tag.call("app/api/order/route.ts", 26).should be_empty
    tag.call("app/api/order/route.ts", 35).should be_empty
  end

  it "lets an awaited read and a log line come before the helper, not an awaited write" do
    tag.call("app/api/lead/route.ts", 7).map(&.name).should eq(["auth"])
    tag.call("app/api/lead/route.ts", 15).should be_empty
  end

  it "reads the handler a wrapper is handed, and a secret inside a template literal" do
    tags = tag.call("app/api/lead/route.ts", 22)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("cronHandler")
    tag.call("lib/cron.ts", 11).map(&.name).should eq(["auth"])
  end

  it "leaves a template holding a public value untagged" do
    tag.call("lib/cron.ts", 16).should be_empty
  end

  it "tags a handler that returns the helper's response" do
    tag.call("app/api/lead/route.ts", 24).map(&.name).should eq(["auth"])
  end

  it "leaves a fetch POST, a tagged-template write or an awaiting log line before the helper untagged" do
    tag.call("app/api/effects/route.ts", 5).should be_empty
    tag.call("app/api/effects/route.ts", 11).should be_empty
    tag.call("app/api/effects/route.ts", 17).should be_empty
  end

  it "leaves a pages-router helper called after a verb branch untagged" do
    tag.call("pages/api/branchy.ts", 11).should be_empty
  end

  it "reads the resolved handler, not the export line" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    path = "#{fixture_base}/app/api/me/route.ts"
    details = Details.new(PathInfo.new(path, 12))
    details.technology = "js_nextjs"
    endpoint = Endpoint.new("/api/me", "GET", [] of Param, details)
    endpoint.handler = Handler.new("getHandler", path, 4)
    NextjsAuthTagger.new(noir_options).perform([endpoint])
    endpoint.tags.map(&.name).should eq(["auth"])
  end

  # umami's `parseRequest`: the helper refuses a request its own auth check
  # found no caller for, through a reply helper (`unauthorized()`), and hands
  # the refusal back in a destructured result the handler returns.
  it "reads a parse helper's refusal through a reply helper and a destructured result" do
    tags = tag.call("app/api/parsed/route.ts", 5)
    tags.map(&.name).should eq(["auth"])
    tags[0].description.should contain("parseRequest")
    # At the helper's definition, where `noir reach lib/request.ts` looks.
    tags[0].path.not_nil!.should end_with("lib/request.ts")
  end

  it "leaves the helper untagged when the call opts out of its check" do
    tag.call("app/api/parsed/route.ts", 19).should be_empty
  end

  it "leaves a login helper refusing unknown credentials untagged" do
    tag.call("app/api/parsed/route.ts", 29).should be_empty
  end

  it "leaves a dropped returned refusal untagged" do
    tag.call("app/api/parsed/route.ts", 36).should be_empty
  end

  it "reads a reply helper in the handler itself" do
    tag.call("app/api/parsed/route.ts", 41).map(&.name).should eq(["auth"])
  end

  it "lets a deployment switch and a validator factory come before the helper, not a factory that writes" do
    tag.call("app/api/parsed-factory/route.ts", 5).map(&.name).should eq(["auth"])
    tag.call("app/api/parsed-factory/route.ts", 21).should be_empty
  end

  describe "a helper's options" do
    note = ->(file : String, line : Int32) { tag.call(file, line).first?.try(&.description) }

    it "keeps an option the call sets from a variable, shorthand or env guarded with a note" do
      {6, 14, 86}.each do |line|
        note.call("app/api/options/route.ts", line).not_nil!.should contain("an option can make it public")
      end
    end

    it "does not let an opt-out in an `||` open the route by itself" do
      {93, 99}.each do |line|
        note.call("app/api/options/route.ts", line).not_nil!.should contain("an option can make it public")
      end
    end

    it "opens a call whose option is literally true: through a const, across lines, destructured" do
      {22, 30, 39, 60, 73}.each { |line| tag.call("app/api/options/route.ts", line).should be_empty }
    end

    it "reads an opt-in check as off unless the call turns it on" do
      tag.call("app/api/options/route.ts", 46).should be_empty
      note.call("app/api/options/route.ts", 53).not_nil!.should_not contain("option")
    end

    it "keeps a `!== true` opt-out and a throwing helper guarded when the call leaves the option out" do
      tag.call("app/api/options/route.ts", 66).map(&.name).should eq(["auth"])
      tag.call("app/api/options/route.ts", 80).map(&.name).should eq(["auth"])
    end
  end

  describe "the refusal's hand-off" do
    it "needs the `if` after the call to return the refusal's own name" do
      tag.call("app/api/handoff/route.ts", 7).should be_empty
      tag.call("app/api/handoff/route.ts", 61).map(&.name).should eq(["auth"])
    end

    it "does not take a validation error for a 401 stored in another field" do
      tag.call("app/api/handoff/route.ts", 16).should be_empty
    end

    it "judges a caller check by its definition: a login reading a password or starting a session is not one" do
      tag.call("app/api/handoff/route.ts", 23).should be_empty
      tag.call("app/api/handoff/route.ts", 68).should be_empty
      # Whatever it reads (polar's: a header its middleware sets).
      tag.call("app/api/handoff/route.ts", 77).map(&.name).should eq(["auth"])
    end

    it "does not read a 401 in an else-if as the absence check's" do
      tag.call("app/api/handoff/route.ts", 32).should be_empty
    end

    it "does not take a schema parse of an awaited write for a read" do
      tag.call("app/api/handoff/route.ts", 43).should be_empty
    end

    it "notes a deployment switch that serves data before the check" do
      tag.call("app/api/handoff/route.ts", 51).first.description.should contain("a setting can open it")
    end
  end

  it "opens the body of a `function` handed to a wrapper at its own brace" do
    tag.call("app/api/wrapped-function/route.ts", 1).map(&.name).should eq(["auth"])
    tag.call("pages/api/verbs.ts", 28).map(&.name).should eq(["auth"])
  end

  it "stops at a verb branch read through a name or wrapped across lines" do
    tag.call("pages/api/verbs.ts", 3).should be_empty
    tag.call("pages/api/verbs.ts", 15).should be_empty
  end

  it "stays linear in the handler's reply calls and absence checks" do
    timed = ->(n : Int32) do
      dir = File.tempname("nextjs_linear")
      Dir.mkdir_p(dir)
      body = String.build do |io|
        io << "export async function GET(request) {\n"
        n.times { |k| io << "  const v#{k} = await getSession();\n  if (!v#{k}) { console.log(1); }\n  return f#{k}(1);\n" }
        io << "}\n"
        n.times { |k| io << "function f#{k}(x) { return x; }\n" }
      end
      File.write(File.join(dir, "route.ts"), body)
      options = create_test_options
      options["base"] = YAML::Any.new(dir)
      details = Details.new(PathInfo.new(File.join(dir, "route.ts"), 1))
      details.technology = "js_nextjs"
      endpoint = Endpoint.new("/x", "GET", [] of Param, details)
      started = Time.instant
      NextjsAuthTagger.new(options).perform([endpoint])
      elapsed = (Time.instant - started).total_seconds
      FileUtils.rm_rf(dir)
      elapsed
    end
    small = timed.call(400)
    large = timed.call(1600)
    # Linear is ~4x; the old per-line lookups were ~16x and more.
    (large < small * 10 || large < 0.3).should be_true
  end
end
