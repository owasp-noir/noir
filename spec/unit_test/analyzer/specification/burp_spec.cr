require "base64"
require "file_utils"
require "../../../spec_helper"
require "../../../../src/analyzer/analyzers/specification/burp"
require "../../../../src/models/code_locator"
require "../../../../src/models/locator_keys"

private def burp_item(raw : Bytes) : String
  %(<item><request base64="true"><![CDATA[#{Base64.strict_encode(raw)}]]></request></item>)
end

describe "Burp sitemap with a binary multipart upload" do
  after_each { CodeLocator.instance.clear_all }

  it "keeps every item and reads the upload's field name" do
    dir = File.tempname("noir_burp_binary")
    Dir.mkdir_p(dir)
    begin
      upload = IO::Memory.new
      upload << "POST /upload HTTP/1.1\r\nContent-Type: multipart/form-data; boundary=XyZ\r\n\r\n"
      upload << "--XyZ\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.png\"\r\n\r\n"
      upload.write(Bytes[0x89, 0x50, 0x4e, 0x47, 0x80, 0xfe, 0xff])
      upload << "\r\n--XyZ--\r\n"

      entry = File.join(dir, "sitemap.xml")
      File.write(entry, "<?xml version=\"1.0\"?>\n<items>" +
                        burp_item("GET /before HTTP/1.1\r\n\r\n".to_slice) +
                        burp_item(upload.to_slice) +
                        burp_item("GET /after HTTP/1.1\r\n\r\n".to_slice) + "</items>\n")

      CodeLocator.instance.clear_all
      CodeLocator.instance.push(Noir::LocatorKeys::BURP_SITEMAP, entry)
      endpoints = Analyzer::Specification::Burp.new(create_test_options).analyze

      endpoints.map { |e| "#{e.method} #{e.url}" }.sort!.should eq(["GET /after", "GET /before", "POST /upload"])
      endpoints.find!(&.url.==("/upload")).params.map(&.name).should eq(["file"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
