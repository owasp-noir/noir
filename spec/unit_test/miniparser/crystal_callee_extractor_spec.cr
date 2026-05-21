require "spec"
require "../../../src/miniparsers/crystal_callee_extractor"

describe Noir::CrystalCalleeExtractor do
  describe "callees_for_body" do
    it "extracts receiver, namespaced, and bare callees" do
      body = <<-CR
        UserService.find(id)
        Noir::Models::User.create!
        log("hello")
        render "ok"
        CR

      callees = Noir::CrystalCalleeExtractor.callees_for_body(body, "svc.cr", 10)
      names = callees.map { |name, _, line| {name, line} }

      names.should contain({"UserService.find", 10})
      names.should contain({"Noir::Models::User.create!", 11})
      names.should contain({"log", 12})
      names.should contain({"render", 13})
    end

    it "preserves source file and start_line offsets" do
      body = "do_work(arg)\n"
      callees = Noir::CrystalCalleeExtractor.callees_for_body(body, "app/foo.cr", 42)
      callees.size.should eq(1)
      name, path, line = callees[0]
      name.should eq("do_work")
      path.should eq("app/foo.cr")
      line.should eq(42)
    end

    it "ignores Crystal reserved words even when followed by parens" do
      body = <<-CR
        return(value)
        if(condition)
        while(more)
        CR

      callees = Noir::CrystalCalleeExtractor.callees_for_body(body, "x.cr", 1)
      callees.map { |name, _, _| name }.should be_empty
    end

    it "skips callees that appear inside a comment" do
      body = <<-CR
        real_call(arg)
        # ignored_call("nope")
        CR

      callees = Noir::CrystalCalleeExtractor.callees_for_body(body, "x.cr", 1)
      names = callees.map { |name, _, _| name }
      names.should contain("real_call")
      names.should_not contain("ignored_call")
    end

    it "dedups identical name+path+line entries" do
      # Same line, same call: should appear once
      body = "save(x) save(y)\n"
      callees = Noir::CrystalCalleeExtractor.callees_for_body(body, "x.cr", 1)
      callees.count { |name, _, _| name == "save" }.should eq(1)
    end

    it "captures instance and class variable receivers" do
      body = "@logger.info(\"hi\")\n@@cache.fetch!(key)\n"
      callees = Noir::CrystalCalleeExtractor.callees_for_body(body, "x.cr", 1)
      names = callees.map { |name, _, _| name }
      names.should contain("@logger.info")
      names.should contain("@@cache.fetch!")
    end
  end

  describe "strip_comment" do
    it "removes everything after an unquoted '#'" do
      Noir::CrystalCalleeExtractor.strip_comment("foo # bar").should eq("foo ")
    end

    it "ignores '#' inside a double-quoted string" do
      line = "puts \"value #x\" # trailing"
      result = Noir::CrystalCalleeExtractor.strip_comment(line)
      result.should eq("puts \"value #x\" ")
    end

    it "ignores '#' inside a single-quoted character literal" do
      line = "x = '#' # comment"
      result = Noir::CrystalCalleeExtractor.strip_comment(line)
      result.should eq("x = '#' ")
    end

    it "respects escaped quotes so the string is not closed prematurely" do
      line = "puts \"a\\\"#\" # actual comment"
      result = Noir::CrystalCalleeExtractor.strip_comment(line)
      result.should eq("puts \"a\\\"#\" ")
    end

    it "returns the line unchanged when no comment is present" do
      Noir::CrystalCalleeExtractor.strip_comment("call_thing(a, b)")
        .should eq("call_thing(a, b)")
    end
  end

  describe "attach_to" do
    it "pushes each callee onto the endpoint" do
      endpoint = Endpoint.new("/api/v1/users", "GET")
      entries = [
        {"Service.find", "app/svc.cr", 10},
        {"helper", "app/svc.cr", 12},
      ] of Noir::CrystalCalleeExtractor::Entry

      Noir::CrystalCalleeExtractor.attach_to(endpoint, entries)

      endpoint.callees.size.should eq(2)
      endpoint.callees[0].name.should eq("Service.find")
      endpoint.callees[1].line.should eq(12)
    end

    it "dedups callees with the same name+path inside the endpoint" do
      endpoint = Endpoint.new("/", "GET")
      entries = [
        {"helper", "app/svc.cr", 10},
        {"helper", "app/svc.cr", 99}, # same name+path => deduped by push_callee
      ] of Noir::CrystalCalleeExtractor::Entry

      Noir::CrystalCalleeExtractor.attach_to(endpoint, entries)
      endpoint.callees.size.should eq(1)
    end
  end
end
