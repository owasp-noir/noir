require "openssl"

# The macOS release tarballs bundle Homebrew's libssl/libcrypto
# (scripts/package-macos.sh). Their compiled-in OPENSSLDIR still points at
# the Homebrew prefix, so on a Mac without Homebrew OpenSSL loads no CA
# certificates and every verified HTTPS request fails (#3197). macOS ships
# its own bundle at /etc/ssl/cert.pem; load it as well.
#
# This hooks the context rather than setting SSL_CERT_FILE: an exported
# variable would reach every child noir starts (ACP agents, git, $EDITOR),
# and tools that read it as their only trust store would stop consulting
# the Keychain.
module Noir::MacosCA
  SYSTEM_CERT_FILE = "/etc/ssl/cert.pem"

  # The bundle to add, or nil to leave OpenSSL alone: the user already chose
  # a location, OpenSSL's own default exists (a Homebrew install), or there
  # is no system bundle to fall back to. An empty variable is unset, which
  # is how OpenSSL fails on it too: it loads nothing.
  def self.fallback_cert_file(env : Hash(String, String) | ENV.class, default_file : String,
                              system_file : String = SYSTEM_CERT_FILE) : String?
    return if env["SSL_CERT_FILE"]?.presence || env["SSL_CERT_DIR"]?.presence
    return if File.exists?(default_file)
    system_file if File.exists?(system_file)
  end
end

{% if flag?(:darwin) %}
  lib LibCrypto
    fun x509_get_default_cert_file = X509_get_default_cert_file : LibC::Char*
  end

  module Noir::MacosCA
    def self.default_cert_file : String
      String.new(LibCrypto.x509_get_default_cert_file)
    end
  end

  # Every verifying context runs this from `Context#initialize`, so deliver,
  # probe and the AI transport are all covered. Insecure contexts skip it.
  abstract class OpenSSL::SSL::Context
    def set_default_verify_paths
      previous_def
      if file = Noir::MacosCA.fallback_cert_file(ENV, Noir::MacosCA.default_cert_file)
        self.ca_certificates = file
      end
    end
  end
{% end %}
