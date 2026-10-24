require "spec"
require "file_utils"
require "../../../src/ext/macos_ca"

describe Noir::MacosCA do
  describe ".fallback_cert_file" do
    dir = File.join(Dir.tempdir, "noir_macos_ca_#{Process.pid}")
    present = File.join(dir, "cert.pem")
    missing = File.join(dir, "missing.pem")

    before_all do
      Dir.mkdir_p(dir)
      File.write(present, "")
    end

    after_all { FileUtils.rm_rf(dir) }

    it "falls back to the system bundle when OpenSSL's default is missing" do
      Noir::MacosCA.fallback_cert_file({} of String => String, missing, present).should eq(present)
    end

    it "leaves a Homebrew install alone" do
      Noir::MacosCA.fallback_cert_file({} of String => String, present, present).should be_nil
    end

    it "respects SSL_CERT_FILE and SSL_CERT_DIR set by the user" do
      Noir::MacosCA.fallback_cert_file({"SSL_CERT_FILE" => "/x"}, missing, present).should be_nil
      Noir::MacosCA.fallback_cert_file({"SSL_CERT_DIR" => "/x"}, missing, present).should be_nil
    end

    it "does nothing when there is no system bundle either" do
      Noir::MacosCA.fallback_cert_file({} of String => String, missing, missing).should be_nil
    end

    it "treats an empty variable as unset" do
      Noir::MacosCA.fallback_cert_file({"SSL_CERT_FILE" => ""}, missing, present).should eq(present)
    end
  end

  {% if flag?(:darwin) %}
    it "reads OpenSSL's compiled-in default cert file" do
      Noir::MacosCA.default_cert_file.should end_with("/cert.pem")
    end

    it "still builds a verifying client context" do
      OpenSSL::SSL::Context::Client.new.verify_mode.should eq(OpenSSL::SSL::VerifyMode::PEER)
    end
  {% end %}
end
