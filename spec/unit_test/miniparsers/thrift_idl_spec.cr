require "../../spec_helper"
require "../../../src/miniparsers/thrift_idl"

describe Noir::ThriftIdl do
  describe ".strip_comments" do
    it "blanks #, // and /* */ comments but keeps literals and line breaks" do
      source = %(a # one\nb // two\n/* three\nfour */ c "x # // y")
      stripped = Noir::ThriftIdl.strip_comments(source)
      stripped.lines.size.should eq(source.lines.size)
      stripped.should_not contain("one")
      stripped.should_not contain("two")
      stripped.should_not contain("four")
      stripped.should contain(%("x # // y"))
    end
  end

  describe ".parse" do
    it "reads includes, services, extends and functions" do
      document = Noir::ThriftIdl.parse(<<-THRIFT)
        include "shared.thrift"
        cpp_include "<vector>"
        namespace java com.ex
        service Calc extends shared.Base {
          i32 add(1: i32 a, 2: i32 b),
          void reset()
        }
        THRIFT

      document.includes.should eq(["shared.thrift"])
      document.services.size.should eq(1)
      service = document.services.first
      service.name.should eq("Calc")
      service.extends.should eq("shared.Base")
      service.line.should eq(4)
      service.functions.map(&.name).should eq(["add", "reset"])
      service.functions.first.args.map(&.name).should eq(["a", "b"])
      service.functions.first.line.should eq(5)
    end

    it "handles multiline functions, containers, defaults, annotations, throws and oneway" do
      document = Noir::ThriftIdl.parse(<<-THRIFT)
        service S {
          map<string, list<i32>> search(
            1: required string query;
            2: optional set<i64> ids = [1, 2]
            3: i32 limit = -1 (py.default = "x(1)")
          ) throws (1: NotFound nf, 2: Bad b) (doc = "y");
          oneway void fire(1: string event)
          list cpp_type "std::deque<int>" <i32> deque()
          string (py.immutable = "") annotated(1: binary (x = "1") blob)
        } (owner = "me")
        THRIFT

      functions = document.services.first.functions
      functions.map(&.name).should eq(["search", "fire", "deque", "annotated"])

      search = functions[0]
      search.return_type.should eq("map<string, list<i32>>")
      search.oneway.should be_false
      search.line.should eq(2)
      search.args.map(&.name).should eq(["query", "ids", "limit"])
      search.args.map(&.id).should eq(["1", "2", "3"])
      search.args.map(&.requiredness).should eq(["required", "optional", nil])
      search.args.map(&.type).should eq(["string", "set<i64>", "i32"])

      functions[1].oneway.should be_true
      functions[2].return_type.should eq("list<i32>")
      functions[3].args.map(&.name).should eq(["blob"])
      functions[3].args.first.type.should eq("binary")
    end

    it "reads fields with no ids and no separators" do
      document = Noir::ThriftIdl.parse("service S { void m(i32 a string b) }")
      args = document.services.first.functions.first.args
      args.map(&.name).should eq(["a", "b"])
      args.map(&.id).should eq([nil, nil])
    end

    it "ignores commented-out services and functions" do
      document = Noir::ThriftIdl.parse(<<-THRIFT)
        /* service Gone { void a() } */
        service Live {
          # void hashed()
          // void slashed()
          void kept()
        }
        THRIFT

      document.services.map(&.name).should eq(["Live"])
      document.services.first.functions.map(&.name).should eq(["kept"])
    end

    it "does not read a service out of a struct field, const or string" do
      document = Noir::ThriftIdl.parse(<<-THRIFT)
        struct Config { 1: string service, 2: Svc service2 }
        const map<string, string> M = {"service X {": "y"}
        const string S = "service Fake { void f() }"
        THRIFT

      document.services.should be_empty
    end

    it "keeps fbthrift stream returns and qualifiers parseable" do
      document = Noir::ThriftIdl.parse(<<-THRIFT)
        service F {
          readonly i32 get(1: i32 k)
          stream<Item throws (1: Ex e)> items()
          idempotent void put(1: i32 k)
        }
        THRIFT

      functions = document.services.first.functions
      functions.map(&.name).should eq(["get", "items", "put"])
      functions[1].return_type.should eq("stream<Item throws (1: Ex e)>")
    end
  end
end
