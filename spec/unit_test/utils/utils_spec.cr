require "../../spec_helper"
require "../../../src/utils/*"

describe "remove_start_slash" do
  it "with slash" do
    remove_start_slash("/abcd/1234").should eq("abcd/1234")
  end
  it "without slash" do
    remove_start_slash("abcd/1234").should eq("abcd/1234")
  end
end

describe "get_relative_path" do
  it "start with ./" do
    get_relative_path("./abcd", "1.cr").should eq("1.cr")
  end

  it "start with /" do
    get_relative_path("/abcd", "1.cr").should eq("1.cr")
  end

  it "end with /" do
    get_relative_path("/abcd/", "1.cr").should eq("1.cr")
  end
end

describe "get_symbol" do
  it "get" do
    get_symbol("GET").should eq(:get)
  end
  it "post" do
    get_symbol("POST").should eq(:post)
  end
  it "put" do
    get_symbol("PUT").should eq(:put)
  end
  it "delete" do
    get_symbol("DELETE").should eq(:delete)
  end
  it "head" do
    get_symbol("HEAD").should eq(:head)
  end
  it "options" do
    get_symbol("OPTIONS").should eq(:options)
  end
  it "trace" do
    get_symbol("TRACE").should eq(:trace)
  end
  it "connect" do
    get_symbol("CONNECT").should eq(:connect)
  end
  it "patch" do
    get_symbol("PATCH").should eq(:patch)
  end
end

describe "any_to_bool" do
  it true do
    any_to_bool(true).should be_true
  end
  it false do
    any_to_bool(false).should be_false
  end
  it "any string" do
    any_to_bool("hahwul").should be_false
  end
end

describe "valid_json?" do
  it "valid json" do
    valid_json?("{\"test\":\"test\"}").should be_true
  end
  it "invalid json" do
    valid_json?("{\"test\":\"test\"").should be_false
  end
end

describe "valid_yaml?" do
  it "valid yaml" do
    valid_yaml?("test: test").should be_true
  end
  it "invalid yaml" do
    valid_yaml?(":").should be_false
  end
end

describe "escape_glob_path" do
  it "no special chars" do
    escape_glob_path("/tmp/test-noir/app").should eq("/tmp/test-noir/app")
  end

  it "curly braces" do
    escape_glob_path("/tmp/test-noir/{{project_name}}/app").should eq("/tmp/test-noir/\\{\\{project_name\\}\\}/app")
  end

  it "square brackets" do
    escape_glob_path("/data/[abc]/file").should eq("/data/\\[abc\\]/file")
  end

  it "asterisk and question" do
    escape_glob_path("/data/a*/b?c").should eq("/data/a\\*/b\\?c")
  end

  it "mixed specials" do
    escape_glob_path("/x/{a}[b]*?\\c").should eq("/x/\\{a\\}\\[b\\]\\*\\?\\\\c")
  end
end
