require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/tagger.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "crypto rule (src/tagger/rules/crypto.yml)" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!
      tagger.name.should eq("crypto")
    end
  end

  describe "perform" do
    it "tags an endpoint under an /encrypt path" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/encrypt", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("crypto")
    end

    it "tags a JWKS key endpoint" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/.well-known/jwks.json", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("crypto")
    end

    it "tags an endpoint with a plaintext/ciphertext parameter" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/op", "POST", [
        Param.new("ciphertext", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("crypto")
    end

    it "tags a named primitive path (e.g. /aes/...)" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/rsa/sign", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("crypto")
    end

    it "tags modern and legacy primitive paths (sha3, chacha20, rc4, 3des, pkcs12)" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoints = [
        Endpoint.new("/api/sha3/digest", "POST"),
        Endpoint.new("/v1/chacha20/encrypt", "POST"),
        Endpoint.new("/legacy/rc4", "POST"),
        Endpoint.new("/cipher/3des", "POST"),
        Endpoint.new("/keys/export.pkcs12", "GET"),
      ]

      tagger.perform(endpoints)

      endpoints.each(&.tags.map(&.name).should(contain("crypto")))
    end

    it "tags a JOSE jwe/jws path" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/token/jwe", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("crypto")
    end

    it "tags an endpoint with a pubkey/privkey parameter" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/op", "POST", [
        Param.new("privkey", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("crypto")
    end

    it "tags when two distinct weak signals co-occur" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/signature", "POST", [
        Param.new("algorithm", "RS256", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("crypto")
    end

    it "does not let one weak token echoed in path and param reach the threshold" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/cert", "GET", [
        Param.new("cert", "name", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a non-crypto nonce + fingerprint pair" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/track", "POST", [
        Param.new("nonce", "", "json"),
        Param.new("fingerprint", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "tags hashing endpoints exposing algorithm + digest" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/op", "POST", [
        Param.new("algorithm", "sha256", "json"),
        Param.new("digest", "", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("crypto")
    end

    it "does not tag on a single weak signal" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/verify", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag auth sign-in / sign-up routes" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      signin = Endpoint.new("/signin", "POST")
      signup = Endpoint.new("/sign-up", "POST")

      tagger.perform([signin, signup])

      signin.tags.size.should eq(0)
      signup.tags.size.should eq(0)
    end

    it "does not tag a generic api key parameter" do
      tagger = NoirTaggers.build("crypto", default_tagger_options).not_nil!

      endpoint = Endpoint.new("/api/data", "GET", [
        Param.new("key", "abc123", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
