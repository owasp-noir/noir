require "../../spec_helper"
require "../../../src/utils/xml_comments"

describe Noir::XmlComments do
  it "replaces each comment with the newlines it spanned" do
    Noir::XmlComments.strip("<a><!-- x\ny\n --><b/></a>").should eq("<a>\n\n<b/></a>")
  end

  it "drops an unterminated comment to the end of the document" do
    Noir::XmlComments.strip("<a/><!-- <jsp-file>\n</a>").should eq("<a/>\n")
  end

  it "leaves comment markers inside CDATA alone" do
    xml = "<r><![CDATA[<!-- body -->]]><!-- gone --><s/></r>"
    Noir::XmlComments.strip(xml).should eq("<r><![CDATA[<!-- body -->]]><s/></r>")
  end

  # Read as comment openers, these swallowed the rest of the document.
  it "leaves comment markers inside processing instructions and the DOCTYPE alone" do
    pi = "<?pi <!-- ?><r><!-- c --><s>x</s></r>"
    Noir::XmlComments.strip(pi).should eq("<?pi <!-- ?><r><s>x</s></r>")

    doctype = %(<!DOCTYPE r [<!ENTITY e "<!--">]><r><!-- c --><s>x</s></r>)
    Noir::XmlComments.strip(doctype).should eq(%(<!DOCTYPE r [<!ENTITY e "<!--">]><r><s>x</s></r>))
    Noir::XmlComments.parse(doctype).xpath_string("string(//s)").should eq("x")
  end

  it "returns comment-free input unchanged" do
    Noir::XmlComments.strip("<a><b/></a>").should eq("<a><b/></a>")
  end

  # libxml2 copies the comment text parsed so far into every error it raises
  # inside a comment, and each `--` is one: 400k of them took ~15s, 200k
  # unterminated `<!--` ~6s.
  it "parses comment-heavy documents in linear time" do
    hyphens = "<r><!-- " + "-- " * 400_000 + "--><s>x</s></r>"
    openers = "<r><!-- c --><s>x</s>" + "<!--" * 400_000 + "</r>"
    elapsed = Time.measure do
      Noir::XmlComments.parse(hyphens).xpath_string("string(//s)").should eq("x")
      Noir::XmlComments.parse(openers).xpath_string("string(//s)").should eq("x")
    end
    elapsed.should be < 2.seconds

    repeated = "<!-- c -->" + "<!DOCTYPE <?" * 200_000
    Time.measure { Noir::XmlComments.strip(repeated) }.should be < 1.second
  end
end
