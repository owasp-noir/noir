require "../../spec_helper"
require "../../../src/analyzer/analyzers/csharp/common.cr"

private class SignatureProbe
  include Analyzer::CSharp::Common

  def signature(lines : Array(String), start : Int32)
    build_signature(lines, lines, start)
  end
end

describe "Analyzer::CSharp::Common#build_signature" do
  it "joins a signature spanning lines up to its closing paren" do
    lines = ["public void M(int a,", "    string b)", "{", "}"]
    SignatureProbe.new.signature(lines, 0).should eq({"public void M(int a,     string b)", 1})
  end

  it "stops reading at MAX_SIGNATURE_LINES when the parens never balance" do
    lines = Array.new(5_000) { |i| "[WolverineGet(\"/r#{i}\"" }
    signature, last = SignatureProbe.new.signature(lines, 10)
    last.should eq 10 + Analyzer::CSharp::Common::MAX_SIGNATURE_LINES - 1
    signature.count('\n').should eq 0
  end
end
