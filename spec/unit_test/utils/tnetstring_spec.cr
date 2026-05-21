require "../../spec_helper"
require "../../../src/utils/tnetstring"

describe Tnetstring do
  it "encodes and decodes strings" do
    bytes = Tnetstring.encode("hello")
    String.new(bytes).should eq "5:hello,"
    value, _ = Tnetstring.parse(bytes)
    value.should eq "hello"
  end

  it "encodes and decodes integers" do
    bytes = Tnetstring.encode(42_i64)
    String.new(bytes).should eq "2:42#"
    value, _ = Tnetstring.parse(bytes)
    value.should eq 42_i64
  end

  it "encodes and decodes booleans and nil" do
    Tnetstring.parse(Tnetstring.encode(true))[0].should be_true
    Tnetstring.parse(Tnetstring.encode(false))[0].should be_false
    Tnetstring.parse(Tnetstring.encode(nil))[0].should be_nil
  end

  it "encodes and decodes nested dicts and lists" do
    value = {
      "method"  => "GET".as(Tnetstring::Value),
      "headers" => [
        ["Host".as(Tnetstring::Value), "example.com".as(Tnetstring::Value)].as(Tnetstring::Value),
      ].as(Tnetstring::Value),
    } of String => Tnetstring::Value

    bytes = Tnetstring.encode(value)
    decoded, pos = Tnetstring.parse(bytes)
    pos.should eq bytes.size
    decoded.should be_a Hash(String, Tnetstring::Value)
    dict = decoded.as(Hash(String, Tnetstring::Value))
    dict["method"].should eq "GET"
    headers = dict["headers"].as(Array(Tnetstring::Value))
    headers.size.should eq 1
    pair = headers.first.as(Array(Tnetstring::Value))
    pair[0].should eq "Host"
    pair[1].should eq "example.com"
  end

  it "parses a stream of top-level values" do
    a = Tnetstring.encode("a")
    b = Tnetstring.encode("bb")
    stream = IO::Memory.new
    stream.write(a)
    stream.write(b)
    values = Tnetstring.parse_all(stream.to_slice)
    values.should eq ["a", "bb"]
  end

  it "raises on truncated input" do
    bytes = "5:hell".to_slice
    expect_raises(Tnetstring::ParseError) do
      Tnetstring.parse(bytes)
    end
  end

  it "decodes mitmproxy's bytes type (;) the same as a string" do
    # mitmproxy serializes most string-shaped fields with the bytes
    # marker `;` rather than the standard tnetstring `,`. The decoder
    # must accept both.
    bytes = "4:type;".to_slice
    value, pos = Tnetstring.parse(bytes)
    value.should eq "type"
    pos.should eq bytes.size
  end

  it "raises on unknown type byte" do
    bytes = "1:a?".to_slice
    expect_raises(Tnetstring::ParseError) do
      Tnetstring.parse(bytes)
    end
  end
end
